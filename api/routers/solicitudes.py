from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from redis import Redis
from rq import Queue
from rq.registry import StartedJobRegistry
from sqlalchemy.orm import Session

from api.auth import CurrentUser
from api.config import settings
from api.database import ControlSessionLocal
from api.models import Solicitud

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/solicitudes", tags=["solicitudes"])


def get_db():
    db = ControlSessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_queue() -> Queue:
    conn = Redis.from_url(settings.redis_url)
    return Queue("reportes", connection=conn)


def _media_type(solicitud: Solicitud) -> str:
    if solicitud.archivo_ruta and solicitud.archivo_ruta.endswith(".zip"):
        return "application/zip"
    if solicitud.formato == "xlsx":
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    return "text/csv"


@router.get("")
def list_solicitudes(
    current_user: CurrentUser,
    limit: int = Query(default=settings.max_files_per_user, le=settings.max_files_per_user),
    db: Session = Depends(get_db),
) -> list[dict]:
    rows = (
        db.query(Solicitud)
        .filter(Solicitud.usuario_email == current_user)
        .order_by(Solicitud.id.desc())
        .limit(limit)
        .all()
    )
    return [s.to_dict() for s in rows]


@router.get("/{solicitud_id}")
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


@router.post("/{solicitud_id}/cancelar")
def cancelar_solicitud(
    solicitud_id: int,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
    queue: Queue = Depends(get_queue),
) -> dict:
    s = db.get(Solicitud, solicitud_id)
    if s is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada.")
    if s.usuario_email != current_user:
        raise HTTPException(status_code=403, detail="No tienes permiso para cancelar esta solicitud.")
    if s.estado not in ("PENDIENTE", "PROCESANDO"):
        raise HTTPException(status_code=409, detail=f"No se puede cancelar una solicitud en estado '{s.estado}'.")

    removed = False
    for job_id in list(queue.job_ids):
        job = queue.fetch_job(job_id)
        if job and job.args and job.args[0] == solicitud_id:
            job.cancel()
            job.delete()
            removed = True

    StartedJobRegistry(queue.name, connection=queue.connection).cleanup()

    s.estado = "CANCELADO"
    s.fecha_fin = datetime.now()
    s.mensaje_error = "Solicitud cancelada por el usuario."
    db.commit()

    return {
        "ok": True,
        "solicitud_id": solicitud_id,
        "estado": s.estado,
        "job_en_cola_cancelado": removed,
        "message": "Solicitud cancelada.",
    }


@router.get("/{solicitud_id}/descargar-email")
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


@router.get("/{solicitud_id}/descargar")
def descargar_reporte(
    solicitud_id: int,
    token: str = Query(...),
    db: Session = Depends(get_db),
) -> FileResponse:
    s = db.get(Solicitud, solicitud_id)
    if s is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada.")
    if s.estado != "FINALIZADO":
        raise HTTPException(status_code=409, detail=f"El reporte está en estado '{s.estado}'.")
    if s.token_descarga != token:
        raise HTTPException(status_code=403, detail="Token de descarga inválido.")
    if not s.archivo_ruta or not Path(s.archivo_ruta).exists():
        raise HTTPException(status_code=410, detail="El archivo ya no está disponible.")
    return FileResponse(path=s.archivo_ruta, filename=s.archivo_nombre, media_type=_media_type(s))
