"""
Scheduled report executor — runs as background daemon thread inside the RQ worker.
Checks every 60 s for due programados and enqueues them.
"""
from __future__ import annotations

import calendar
import logging
import time
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

DIAS_SEMANA = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]


def calc_next(
    frecuencia: str,
    dia_semana: int | None,
    dia_mes: int | None,
    hora: int,
    minuto: int,
    from_dt: datetime | None = None,
) -> datetime:
    now = from_dt or datetime.now()

    if frecuencia == "diario":
        candidate = now.replace(hour=hora, minute=minuto, second=0, microsecond=0)
        if candidate <= now:
            candidate += timedelta(days=1)
        return candidate

    if frecuencia == "semanal":
        target = dia_semana or 0
        days_ahead = target - now.weekday()
        if days_ahead < 0:
            days_ahead += 7
        candidate = (now + timedelta(days=days_ahead)).replace(
            hour=hora, minute=minuto, second=0, microsecond=0
        )
        if candidate <= now:
            candidate += timedelta(weeks=1)
        return candidate

    if frecuencia == "mensual":
        year, month = now.year, now.month
        day = min(dia_mes or 1, calendar.monthrange(year, month)[1])
        candidate = now.replace(day=day, hour=hora, minute=minuto, second=0, microsecond=0)
        if candidate <= now:
            month += 1
            if month > 12:
                month = 1
                year += 1
            day = min(dia_mes or 1, calendar.monthrange(year, month)[1])
            candidate = candidate.replace(year=year, month=month, day=day)
        return candidate

    raise ValueError(f"Frecuencia desconocida: {frecuencia}")


def scheduler_loop(redis_conn) -> None:
    from rq import Queue

    from api.database import ControlSessionLocal
    from api.jobs import process_report_job
    from api.models import ReporteProgramado, Solicitud

    q = Queue("reportes", connection=redis_conn)
    logger.info("Scheduler iniciado — chequeo cada 60 s")

    while True:
        try:
            now = datetime.now()
            with ControlSessionLocal() as db:
                due = (
                    db.query(ReporteProgramado)
                    .filter(
                        ReporteProgramado.activo == True,
                        ReporteProgramado.proxima_ejecucion <= now,
                    )
                    .with_for_update(skip_locked=True)
                    .all()
                )
                for prog in due:
                    sol = Solicitud(
                        reporte_codigo=prog.reporte_codigo,
                        reporte_nombre=prog.reporte_nombre,
                        usuario_email=prog.usuario_email,
                        filtros=prog.filtros,
                        formato=prog.formato,
                        estado="PENDIENTE",
                    )
                    db.add(sol)
                    db.flush()
                    q.enqueue(process_report_job, sol.id, job_timeout=3600)
                    prog.ultima_ejecucion = now
                    prog.proxima_ejecucion = calc_next(
                        prog.frecuencia, prog.dia_semana, prog.dia_mes, prog.hora, prog.minuto
                    )
                    logger.info(
                        "Programado ejecutado: %s | %s | próx: %s",
                        prog.reporte_codigo,
                        prog.usuario_email,
                        prog.proxima_ejecucion,
                    )
                if due:
                    db.commit()
        except Exception as exc:
            logger.error("Scheduler error: %s", exc)

        time.sleep(60)
