"""
FastAPI router for report listing, filter hydration, preview, and job submission.
"""
from __future__ import annotations

import logging
import re
import time
from datetime import datetime, date
from decimal import Decimal
from typing import Any

import psycopg2.errors
from fastapi import APIRouter, Depends, HTTPException
from functools import lru_cache
from pydantic import BaseModel
from redis import Redis
from rq import Queue
from sqlalchemy.orm import Session

from api.auth import CurrentUser
from api.config import settings
from api.database import ControlSessionLocal, get_moodle_conn
from api.jobs import process_report_job, _build_params
from api.models import Solicitud
from api.reportes.registry import REPORTES, get_reporte

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/reportes", tags=["reportes"])

_ROLE_LABELS = {
    "manager": "Gestor",
    "coursecreator": "Creador de cursos",
    "editingteacher": "Instructor editor",
    "teacher": "Instructor",
    "student": "Aprendiz",
}

# Cache de opciones de filtros dinámicos (TTL 5 min, single-process safe)
_DYNAMIC_FILTER_CACHE: dict[str, Any] = {"expires_at": 0.0, "options": {}}
_DYNAMIC_FILTER_TTL = 300

# Vista previa: tiempo máx. acordado 30s. Si la consulta lo excede, se
# devuelve un mensaje en lugar de colgar (la generación completa sí funciona).
_PREVIEW_TIMEOUT_MS = 30000
_PREVIEW_ROWS = 50
# Quita el ORDER BY final (de nivel superior, sin paréntesis hasta el fin) para
# que LIMIT pueda cortar temprano. No afecta ORDER BY dentro de OVER(...)/subqueries.
_TRAILING_ORDER_BY = re.compile(r'\bORDER\s+BY\b[^()]*$', re.IGNORECASE)


def get_db():
    db = ControlSessionLocal()
    try:
        yield db
    finally:
        db.close()


@lru_cache(maxsize=1)
def _get_queue() -> Queue:
    """Singleton RQ queue — one Redis connection per process lifetime."""
    return Queue("reportes", connection=Redis.from_url(settings.redis_url))


def _validate_required_filters(reporte, filtros: dict[str, Any]) -> None:
    missing = [
        f.etiqueta
        for f in reporte.filtros
        if f.requerido and _build_params(filtros or {}, reporte.codigo).get(f.nombre) is None
    ]
    if missing:
        raise HTTPException(
            status_code=400,
            detail="Faltan filtros obligatorios: " + ", ".join(missing),
        )


def _moodle_role_label(shortname: str, name: str | None) -> str:
    clean_name = (name or "").strip()
    return clean_name or _ROLE_LABELS.get(shortname, shortname)


def _get_dynamic_filter_options() -> dict[str, list[dict[str, str]]]:
    now = time.monotonic()
    cached = _DYNAMIC_FILTER_CACHE.get("options") or {}
    if cached and now < float(_DYNAMIC_FILTER_CACHE.get("expires_at", 0.0)):
        return cached

    options: dict[str, list[dict[str, str]]] = {
        "rol_usuario": [{"value": "", "label": "Todas"}],
        "modalidad": [{"value": "", "label": "Todas"}],
        "nivel": [
            {"value": "", "label": "Todas"},
            {"value": "Titulada", "label": "Titulada"},
            {"value": "Complementaria", "label": "Complementaria"},
        ],
        "id_categoria": [{"value": "", "label": "Todas"}],
    }

    try:
        with get_moodle_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT shortname, name FROM public.mdl_role
                    WHERE shortname NOT IN ('guest', 'user', 'frontpage')
                    ORDER BY sortorder, id
                    """
                )
                for row in cur.fetchall():
                    options["rol_usuario"].append(
                        {"value": row["shortname"], "label": _moodle_role_label(row["shortname"], row.get("name"))}
                    )

                cur.execute(
                    """
                    WITH m AS (
                        SELECT DISTINCT
                            CASE
                                WHEN SUBSTRING(shortname FROM '^[0-9]*P_[0-9]+_([A-Za-z]+)_') = 'V'  THEN 'Virtual'
                                WHEN SUBSTRING(shortname FROM '^[0-9]*P_[0-9]+_([A-Za-z]+)_') = 'A'  THEN 'A distancia'
                                WHEN SUBSTRING(shortname FROM '^[0-9]*P_[0-9]+_([A-Za-z]+)_') IN ('P','PI') THEN 'Presencial'
                            END AS modalidad
                        FROM public.mdl_course WHERE id <> 1
                    )
                    SELECT modalidad FROM m WHERE modalidad IS NOT NULL ORDER BY modalidad
                    """
                )
                for row in cur.fetchall():
                    options["modalidad"].append({"value": row["modalidad"], "label": row["modalidad"]})

                cur.execute(
                    "SELECT id, name FROM public.mdl_course_categories ORDER BY sortorder, id"
                )
                for row in cur.fetchall():
                    options["id_categoria"].append({"value": str(row["id"]), "label": row["name"]})
    except Exception as exc:
        logger.warning("No fue posible cargar filtros dinámicos desde Moodle: %s", exc)

    _DYNAMIC_FILTER_CACHE["options"] = options
    _DYNAMIC_FILTER_CACHE["expires_at"] = now + _DYNAMIC_FILTER_TTL
    return options


def _hydrate_dynamic_filters(filtros: list[dict[str, Any]]) -> list[dict[str, Any]]:
    dynamic_options = _get_dynamic_filter_options()
    for filtro in filtros:
        nombre = filtro.get("nombre")
        if nombre in dynamic_options:
            filtro["tipo"] = "select"
            filtro["opciones"] = dynamic_options[nombre]
            if nombre == "id_categoria":
                filtro["etiqueta"] = "Categoría del curso"
    return filtros


def _safe(v: Any) -> Any:
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    return v


class GenerarReporteRequest(BaseModel):
    usuario_email: str | None = None
    usuario_id: str | None = None
    filtros: dict[str, Any] = {}
    formato: str = "xlsx"


@router.get("")
def list_reportes(current_user: CurrentUser) -> list[dict]:
    return [
        {
            "codigo": r.codigo,
            "nombre": r.nombre,
            "descripcion": r.descripcion,
            "num_filtros": len(r.filtros),
        }
        for r in REPORTES.values()
    ]


@router.get("/{codigo}/filtros")
def get_filtros(codigo: str, current_user: CurrentUser) -> dict:
    if codigo not in REPORTES:
        raise HTTPException(status_code=404, detail=f"Reporte '{codigo}' no encontrado.")
    r = REPORTES[codigo]
    return {
        "codigo": r.codigo,
        "nombre": r.nombre,
        "descripcion": r.descripcion,
        "filtros": _hydrate_dynamic_filters(r.filtros_dict()),
    }


@router.post("/{codigo}/generar", status_code=202)
def generar_reporte(
    codigo: str,
    body: GenerarReporteRequest,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
) -> dict:
    if codigo not in REPORTES:
        raise HTTPException(status_code=404, detail=f"Reporte '{codigo}' no encontrado.")
    if body.formato not in ("xlsx", "csv"):
        raise HTTPException(status_code=400, detail="Formato debe ser 'xlsx' o 'csv'.")

    reporte = REPORTES[codigo]
    _validate_required_filters(reporte, body.filtros or {})

    solicitud = Solicitud(
        reporte_codigo=codigo,
        reporte_nombre=reporte.nombre,
        usuario_email=current_user,
        usuario_id=body.usuario_id,
        filtros=body.filtros,
        estado="PENDIENTE",
        formato=body.formato,
        fecha_solicitud=datetime.now(),
    )
    db.add(solicitud)
    db.commit()
    db.refresh(solicitud)

    _get_queue().enqueue(process_report_job, solicitud.id, job_timeout=3600, result_ttl=86400)

    logger.info("Solicitud %d encolada para reporte '%s'.", solicitud.id, codigo)

    return {
        "message": "Su reporte está siendo procesado. Cuando finalice podrá descargarlo desde esta pantalla.",
        "solicitud_id": solicitud.id,
        "estado": "PENDIENTE",
    }


@router.post("/{codigo}/preview")
def preview_reporte(
    codigo: str,
    body: GenerarReporteRequest,
    current_user: CurrentUser,
) -> dict:
    if codigo not in REPORTES:
        raise HTTPException(status_code=404, detail=f"Reporte '{codigo}' no encontrado.")

    reporte = get_reporte(codigo)
    _validate_required_filters(reporte, body.filtros or {})
    sql = reporte.load_sql()
    params = _build_params(body.filtros or {}, codigo)
    # Sin el ORDER BY final, LIMIT puede cortar temprano en reportes sin agregación.
    sql_preview = _TRAILING_ORDER_BY.sub("", sql)
    preview_sql = f"SELECT * FROM ({sql_preview}) AS _preview LIMIT {_PREVIEW_ROWS}"

    try:
        with get_moodle_conn() as conn:
            with conn.cursor() as cur:
                # Acota la vista previa al SLA acordado (30s).
                cur.execute(f"SET LOCAL statement_timeout = {_PREVIEW_TIMEOUT_MS}")
                cur.execute(preview_sql, params)
                columns = [desc[0] for desc in cur.description]
                raw_rows = cur.fetchall()
    except psycopg2.errors.QueryCanceled:
        logger.warning("Preview de '%s' excedió %sms con filtros %s", codigo, _PREVIEW_TIMEOUT_MS, body.filtros)
        raise HTTPException(
            status_code=503,
            detail=(
                "La vista previa con estos filtros supera el límite de 30 segundos. "
                "Genera el reporte completo para obtener los datos."
            ),
        )
    except Exception as exc:
        logger.error("Error en preview de '%s': %s", codigo, exc)
        raise HTTPException(status_code=500, detail=f"Error ejecutando la consulta: {exc}")

    rows = [{col: _safe(row.get(col)) for col in columns} for row in raw_rows]
    return {"columns": columns, "rows": rows, "count": len(rows)}
