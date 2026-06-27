from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import CurrentUser
from api.database import ControlSessionLocal
from api.models import ReporteProgramado
from api.scheduler import calc_next

router = APIRouter(prefix="/api/programados", tags=["programados"])


def get_db():
    db = ControlSessionLocal()
    try:
        yield db
    finally:
        db.close()


def _to_dict(p: ReporteProgramado) -> dict:
    return {
        "id": p.id,
        "nombre": p.nombre,
        "reporte_codigo": p.reporte_codigo,
        "reporte_nombre": p.reporte_nombre,
        "filtros": p.filtros,
        "formato": p.formato,
        "frecuencia": p.frecuencia,
        "dia_semana": p.dia_semana,
        "dia_mes": p.dia_mes,
        "hora": p.hora,
        "minuto": p.minuto,
        "activo": p.activo,
        "ultima_ejecucion": p.ultima_ejecucion.isoformat() if p.ultima_ejecucion else None,
        "proxima_ejecucion": p.proxima_ejecucion.isoformat() if p.proxima_ejecucion else None,
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


class CreateRequest(BaseModel):
    nombre: str | None = None
    reporte_codigo: str
    reporte_nombre: str
    filtros: dict | None = None
    formato: str = "xlsx"
    frecuencia: str
    dia_semana: int | None = None
    dia_mes: int | None = None
    hora: int = 8
    minuto: int = 0


@router.get("")
def list_programados(current_user: CurrentUser, db: Session = Depends(get_db)) -> list[dict]:
    rows = (
        db.query(ReporteProgramado)
        .filter(ReporteProgramado.usuario_email == current_user)
        .order_by(ReporteProgramado.created_at.desc())
        .all()
    )
    return [_to_dict(r) for r in rows]


@router.post("", status_code=201)
def create_programado(
    body: CreateRequest,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
) -> dict:
    if body.frecuencia not in ("diario", "semanal", "mensual"):
        raise HTTPException(status_code=422, detail="frecuencia debe ser diario/semanal/mensual")
    if body.frecuencia == "semanal" and body.dia_semana is None:
        raise HTTPException(status_code=422, detail="dia_semana requerido para semanal")
    if body.frecuencia == "mensual" and body.dia_mes is None:
        raise HTTPException(status_code=422, detail="dia_mes requerido para mensual")
    if not (0 <= body.hora <= 23):
        raise HTTPException(status_code=422, detail="hora debe ser 0–23")
    if not (0 <= body.minuto <= 59):
        raise HTTPException(status_code=422, detail="minuto debe ser 0–59")

    proxima = calc_next(body.frecuencia, body.dia_semana, body.dia_mes, body.hora, body.minuto)
    prog = ReporteProgramado(
        usuario_email=current_user,
        nombre=body.nombre,
        reporte_codigo=body.reporte_codigo,
        reporte_nombre=body.reporte_nombre,
        filtros=body.filtros,
        formato=body.formato,
        frecuencia=body.frecuencia,
        dia_semana=body.dia_semana,
        dia_mes=body.dia_mes,
        hora=body.hora,
        minuto=body.minuto,
        activo=True,
        proxima_ejecucion=proxima,
    )
    db.add(prog)
    db.commit()
    db.refresh(prog)
    return _to_dict(prog)


@router.put("/{prog_id}/toggle")
def toggle_programado(
    prog_id: int,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
) -> dict:
    prog = db.get(ReporteProgramado, prog_id)
    if prog is None or prog.usuario_email != current_user:
        raise HTTPException(status_code=404, detail="Programación no encontrada.")
    prog.activo = not prog.activo
    if prog.activo:
        prog.proxima_ejecucion = calc_next(
            prog.frecuencia, prog.dia_semana, prog.dia_mes, prog.hora, prog.minuto
        )
    db.commit()
    return _to_dict(prog)


@router.delete("/{prog_id}", status_code=204)
def delete_programado(
    prog_id: int,
    current_user: CurrentUser,
    db: Session = Depends(get_db),
):
    prog = db.get(ReporteProgramado, prog_id)
    if prog is None or prog.usuario_email != current_user:
        raise HTTPException(status_code=404, detail="Programación no encontrada.")
    db.delete(prog)
    db.commit()
