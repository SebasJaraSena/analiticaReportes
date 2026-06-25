"""
Reportes ZAJUNA — FastAPI application
"""
from __future__ import annotations

import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from redis import Redis
from rq import Queue
from sqlalchemy.orm import Session

from api.auth import CurrentUser, CurrentAdmin, get_current_user, get_current_admin
from api.config import settings
from api.database import ControlSessionLocal, init_control_db, get_moodle_conn
from api.jobs import process_report_job, _build_params
from api.models import Solicitud, ReporteUser
from api.reportes.registry import REPORTES, get_reporte


def _media_type(solicitud: Solicitud) -> str:
    if solicitud.archivo_ruta and solicitud.archivo_ruta.endswith(".zip"):
        return "application/zip"
    if solicitud.formato == "xlsx":
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    return "text/csv"


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Reportes ZAJUNA",
    description="Sistema de reportes administrativos para Moodle/ZAJUNA",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Startup ──────────────────────────────────────────────────────────────────

@app.on_event("startup")
def startup_event() -> None:
    init_control_db()
    from api.auth import seed_admin_user
    seed_admin_user()
    logger.info("Reportes ZAJUNA iniciado. Puerto 8089.")


# ── Dependencies ─────────────────────────────────────────────────────────────

def get_db() -> Session:
    db = ControlSessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_queue() -> Queue:
    conn = Redis.from_url(settings.redis_url)
    return Queue("reportes", connection=conn)


# ── Schemas ──────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    username: str
    password: str


class GenerarReporteRequest(BaseModel):
    usuario_email: str | None = None
    usuario_id: str | None = None
    filtros: dict[str, Any] = {}
    formato: str = "xlsx"


class SolicitudResponse(BaseModel):
    id: int
    reporte_codigo: str
    reporte_nombre: str
    usuario_email: str | None
    filtros: dict | None
    estado: str
    formato: str
    archivo_nombre: str | None
    archivo_tamano: int | None
    mensaje_error: str | None
    fecha_solicitud: str | None
    fecha_inicio: str | None
    fecha_fin: str | None


# ── API Routes ────────────────────────────────────────────────────────────────

@app.get("/api/health")
def health() -> dict:
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}


@app.post("/api/auth/login")
def login(body: LoginRequest, db: Session = Depends(get_db)) -> dict:
    """Authenticate against own reportes_users table."""
    from api.auth import authenticate_user, create_token
    user = authenticate_user(db, body.username, body.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Usuario o contraseña incorrectos.")
    return {"access_token": create_token(user.email), "token_type": "bearer"}


@app.get("/api/auth/me")
def get_me(current_user: CurrentUser) -> dict:
    return {"email": current_user}


@app.get("/api/reportes")
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


@app.get("/api/reportes/{codigo}/filtros")
def get_filtros(codigo: str, current_user: CurrentUser) -> dict:
    if codigo not in REPORTES:
        raise HTTPException(status_code=404, detail=f"Reporte '{codigo}' no encontrado.")
    r = REPORTES[codigo]
    return {
        "codigo": r.codigo,
        "nombre": r.nombre,
        "descripcion": r.descripcion,
        "filtros": r.filtros_dict(),
    }


@app.post("/api/reportes/{codigo}/generar", status_code=202)
def generar_reporte(
    codigo: str,
    body: GenerarReporteRequest,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
    queue: Queue = Depends(get_queue),
) -> dict:
    if codigo not in REPORTES:
        raise HTTPException(status_code=404, detail=f"Reporte '{codigo}' no encontrado.")

    if body.formato not in ("xlsx", "csv"):
        raise HTTPException(status_code=400, detail="Formato debe ser 'xlsx' o 'csv'.")

    reporte = REPORTES[codigo]

    solicitud = Solicitud(
        reporte_codigo=codigo,
        reporte_nombre=reporte.nombre,
        usuario_email=current_user,
        usuario_id=body.usuario_id,
        filtros=body.filtros,
        estado="PENDIENTE",
        formato=body.formato,
        fecha_solicitud=datetime.utcnow(),
    )
    db.add(solicitud)
    db.commit()
    db.refresh(solicitud)

    queue.enqueue(
        process_report_job,
        solicitud.id,
        job_timeout=3600,
        result_ttl=86400,
    )

    logger.info("Solicitud %d encolada para reporte '%s'.", solicitud.id, codigo)

    return {
        "message": "Su reporte está siendo procesado. Cuando finalice podrá descargarlo desde esta pantalla.",
        "solicitud_id": solicitud.id,
        "estado": "PENDIENTE",
    }


@app.post("/api/reportes/{codigo}/preview")
def preview_reporte(
    codigo: str,
    body: GenerarReporteRequest,
    current_user: CurrentUser,
) -> dict:
    """Run query with LIMIT 50 and return rows as JSON for preview."""
    if codigo not in REPORTES:
        raise HTTPException(status_code=404, detail=f"Reporte '{codigo}' no encontrado.")

    reporte = get_reporte(codigo)
    sql = reporte.load_sql()
    params = _build_params(body.filtros or {}, codigo)

    preview_sql = f"SELECT * FROM ({sql}) AS _preview LIMIT 50"

    from datetime import datetime as _dt, date as _date
    from decimal import Decimal

    def _safe(v):
        if isinstance(v, (_dt, _date)):
            return v.isoformat()
        if isinstance(v, Decimal):
            return float(v)
        return v

    try:
        with get_moodle_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(preview_sql, params)
                columns = [desc[0] for desc in cur.description]
                raw_rows = cur.fetchall()
    except Exception as exc:
        logger.error("Error en preview de '%s': %s", codigo, exc)
        raise HTTPException(status_code=500, detail=f"Error ejecutando la consulta: {exc}")

    rows = [{col: _safe(row.get(col)) for col in columns} for row in raw_rows]
    return {"columns": columns, "rows": rows, "count": len(rows)}


@app.get("/api/solicitudes")
def list_solicitudes(
    current_user: CurrentUser,
    limit: int = Query(default=settings.max_files_per_user, le=settings.max_files_per_user),
    db: Session = Depends(get_db),
) -> list[dict]:
    q = (
        db.query(Solicitud)
        .filter(Solicitud.usuario_email == current_user)
        .order_by(Solicitud.fecha_solicitud.desc())
    )
    return [s.to_dict() for s in q.limit(limit).all()]


@app.get("/api/solicitudes/{solicitud_id}")
def get_solicitud(
    solicitud_id: int,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
) -> dict:
    s = db.get(Solicitud, solicitud_id)
    if s is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada.")
    if s.usuario_email != current_user:
        raise HTTPException(status_code=403, detail="No tienes permiso para ver esta solicitud.")
    return s.to_dict()


@app.get("/api/solicitudes/{solicitud_id}/descargar-email")
def descargar_por_email(
    solicitud_id: int,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
) -> FileResponse:
    s = db.get(Solicitud, solicitud_id)
    if s is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada.")
    if s.estado != "FINALIZADO":
        raise HTTPException(status_code=409, detail=f"El reporte está en estado '{s.estado}'.")
    if s.usuario_email != current_user:
        raise HTTPException(status_code=403, detail="No tienes permiso para descargar esta solicitud.")
    if not s.archivo_ruta or not Path(s.archivo_ruta).exists():
        raise HTTPException(status_code=410, detail="El archivo ya no está disponible.")
    return FileResponse(path=s.archivo_ruta, filename=s.archivo_nombre, media_type=_media_type(s))


@app.get("/api/solicitudes/{solicitud_id}/descargar")
def descargar_reporte(
    solicitud_id: int,
    token: str = Query(...),
    db: Session = Depends(get_db),
) -> FileResponse:
    """Token-based download — kept for compatibility."""
    s = db.get(Solicitud, solicitud_id)
    if s is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada.")
    if s.estado != "FINALIZADO":
        raise HTTPException(status_code=409, detail=f"El reporte está en estado '{s.estado}'.")
    if s.token_descarga != token:
        raise HTTPException(status_code=403, detail="Token de descarga inválido.")
    if not s.archivo_ruta or not Path(s.archivo_ruta).exists():
        raise HTTPException(status_code=410, detail="El archivo ya no está disponible.")
    return FileResponse(
        path=s.archivo_ruta,
        filename=s.archivo_nombre,
        media_type=_media_type(s),
    )


# ── Admin: User Management ───────────────────────────────────────────────────

class CreateUserRequest(BaseModel):
    email: str
    username: str
    password: str
    is_admin: bool = False


class UpdateUserRequest(BaseModel):
    password: str | None = None
    is_admin: bool | None = None
    is_active: bool | None = None


@app.get("/api/admin/users")
def list_users(db: Session = Depends(get_db), _: str = Depends(get_current_admin)) -> list[dict]:
    users = db.query(ReporteUser).order_by(ReporteUser.id).all()
    return [
        {
            "id": u.id,
            "email": u.email,
            "username": u.username,
            "is_admin": u.is_admin,
            "is_active": u.is_active,
            "created_at": u.created_at.isoformat() if u.created_at else None,
        }
        for u in users
    ]


@app.post("/api/admin/users", status_code=201)
def create_user(
    body: CreateUserRequest,
    db: Session = Depends(get_db),
    _: str = Depends(get_current_admin),
) -> dict:
    from api.auth import hash_password
    if db.query(ReporteUser).filter(ReporteUser.email == body.email).first():
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese correo.")
    if db.query(ReporteUser).filter(ReporteUser.username == body.username).first():
        raise HTTPException(status_code=409, detail="Ya existe un usuario con ese nombre de usuario.")
    user = ReporteUser(
        email=body.email,
        username=body.username,
        hashed_password=hash_password(body.password),
        is_admin=body.is_admin,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return {"id": user.id, "email": user.email, "username": user.username, "is_admin": user.is_admin}


@app.put("/api/admin/users/{user_id}")
def update_user(
    user_id: int,
    body: UpdateUserRequest,
    db: Session = Depends(get_db),
    _: str = Depends(get_current_admin),
) -> dict:
    from api.auth import hash_password
    user = db.get(ReporteUser, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    if body.password is not None:
        user.hashed_password = hash_password(body.password)
    if body.is_admin is not None:
        user.is_admin = body.is_admin
    if body.is_active is not None:
        user.is_active = body.is_active
    db.commit()
    return {
        "id": user.id,
        "email": user.email,
        "username": user.username,
        "is_admin": user.is_admin,
        "is_active": user.is_active,
    }


@app.delete("/api/admin/users/{user_id}", status_code=200)
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(get_current_admin),
) -> dict:
    user = db.get(ReporteUser, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    db.delete(user)
    db.commit()
    return {"ok": True}


# ── Frontend (SPA served at /) ────────────────────────────────────────────────

FRONTEND_DIR = Path(__file__).parent.parent / "frontend"


@app.get("/", response_class=HTMLResponse)
@app.get("/{path:path}", response_class=HTMLResponse, include_in_schema=False)
def serve_spa(path: str = "") -> HTMLResponse:
    index = FRONTEND_DIR / "index.html"
    if not index.exists():
        return HTMLResponse("<h1>Frontend no encontrado</h1>", status_code=404)
    return HTMLResponse(index.read_text(encoding="utf-8"))
