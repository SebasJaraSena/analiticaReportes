"""
Background job: executes a report query and writes the output file.
Run by the RQ worker.
"""
from __future__ import annotations

import csv
import json
import logging
import os
import secrets
import shutil
import time
import zipfile
from datetime import datetime

from api.scheduler import now_bogota
from pathlib import Path
from typing import Any

import psycopg2.extras

from api.config import settings
from api.database import ControlSessionLocal, get_moodle_conn
from api.models import Solicitud
from api.reportes.registry import get_reporte

logger = logging.getLogger(__name__)

FETCH_SIZE = 20_000  # rows per PostgreSQL FETCH batch
PROGRESS_UPDATE_ROWS = 50_000
PROGRESS_UPDATE_SECONDS = 5


class ReportCancelled(Exception):
    """Raised when a report request is cancelled while streaming."""


def _null_if_empty(value: Any) -> Any:
    """Convert empty string / empty list filter values to None (= no filter)."""
    if isinstance(value, str) and value.strip() == "":
        return None
    if isinstance(value, list):
        cleaned = [v for v in value if isinstance(v, str) and v.strip()]
        return cleaned if cleaned else None
    return value


def _coerce_text_array(value: Any) -> Any:
    """Normaliza string o lista a lista para parámetros SQL ::text[].
    Soporta filtros guardados como string (programados viejos) o lista (UI nueva)."""
    if value is None:
        return None
    if isinstance(value, list):
        cleaned = [v.strip() for v in value if isinstance(v, str) and v.strip()]
        return cleaned if cleaned else None
    if isinstance(value, str):
        v = value.strip()
        return [v] if v else None
    return value


_ARRAY_FILTER_PARAMS = frozenset({
    "rol_usuario", "nivel", "modalidad", "regional", "centro_formacion",
})


def _format_meta_value(val: Any) -> str:
    if val is None or val == "" or val == []:
        return "Todos"
    if isinstance(val, list):
        return ", ".join(str(v) for v in val)
    return str(val)


def _build_params(filtros: dict[str, Any], reporte_codigo: str) -> dict[str, Any]:
    reporte = get_reporte(reporte_codigo)
    expected = {f.nombre for f in reporte.filtros}
    params = {k: _null_if_empty(filtros.get(k)) for k in expected}
    for key in _ARRAY_FILTER_PARAMS:
        if key in params:
            params[key] = _coerce_text_array(params[key])
    # Params that use = (not ANY): flatten list → first element to avoid text = text[] error
    for key, val in list(params.items()):
        if key not in _ARRAY_FILTER_PARAMS and isinstance(val, list):
            params[key] = val[0] if val else None
    return params


def _output_path(solicitud_id: int, usuario_email: str, extension: str) -> tuple[Path, str]:
    ts = now_bogota().strftime("%Y%m%d_%H%M%S")
    safe_email = (usuario_email or "anonimo").replace("@", "_").replace(".", "_")
    filename = f"reporte_{solicitud_id}_{safe_email}_{ts}.{extension}"
    out_dir = Path(settings.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir / filename, filename


def _build_meta_rows(reporte: Any, params: dict, gen_time: datetime) -> list[tuple[str, str]]:
    """Build header metadata rows: [(label, value), ...]."""
    rows: list[tuple[str, str]] = [
        ("Nombre del reporte", reporte.nombre),
        ("Fecha de generación", gen_time.strftime("%Y/%m/%d")),
        ("Hora de generación",  gen_time.strftime("%H:%M:%S")),
    ]
    for f in reporte.filtros:
        val = params.get(f.nombre)
        rows.append((f.etiqueta, _format_meta_value(val)))
    return rows


def _stream_csv_parts(
    cursor: psycopg2.extras.RealDictCursor,
    tmp_dir: Path,
    base_name: str,
    rows_per_file: int,
    meta_rows: list[tuple[str, str]] | None = None,
    progress_callback=None,
) -> list[tuple[Path, int]]:
    """Stream cursor rows into numbered CSV part files. Always returns ≥1 entry."""
    # Named (server-side) cursors only populate description after first FETCH.
    first_batch = cursor.fetchmany(FETCH_SIZE)
    columns = [desc[0] for desc in cursor.description]

    parts: list[tuple[Path, int]] = []
    part_num = 0
    current_file = None
    current_writer = None
    current_path: Path | None = None
    rows_in_part = 0
    total_rows = 0

    def _open_part() -> None:
        nonlocal part_num, current_file, current_writer, current_path, rows_in_part
        part_num += 1
        current_path = tmp_dir / f"{base_name}_parte_{part_num:03d}.csv"
        current_file = open(current_path, "w", newline="", encoding="utf-8-sig")
        current_writer = csv.DictWriter(current_file, fieldnames=columns, delimiter=';')
        if meta_rows and part_num == 1:
            meta_writer = csv.writer(current_file, delimiter=';')
            for label, value in meta_rows:
                meta_writer.writerow([label, value])
            meta_writer.writerow([])
        current_writer.writeheader()
        rows_in_part = 0

    def _close_part() -> None:
        nonlocal current_file
        if current_file is not None:
            current_file.close()
            current_file = None
            parts.append((current_path, rows_in_part))

    def _write_batch(batch: list) -> None:
        nonlocal rows_in_part, total_rows
        for row in batch:
            if rows_in_part >= rows_per_file:
                _close_part()
                _open_part()
            current_writer.writerow(row)
            rows_in_part += 1
            total_rows += 1
        if progress_callback is not None:
            progress_callback(total_rows, part_num)

    _open_part()
    try:
        _write_batch(first_batch)
        while True:
            batch = cursor.fetchmany(FETCH_SIZE)
            if not batch:
                break
            _write_batch(batch)
        _close_part()
    except Exception:
        if current_file is not None:
            try:
                current_file.close()
            except OSError:
                pass
        raise

    return parts


def _stream_xlsx_parts(
    cursor: psycopg2.extras.RealDictCursor,
    tmp_dir: Path,
    base_name: str,
    rows_per_file: int,
    meta_rows: list[tuple[str, str]] | None = None,
    progress_callback=None,
) -> list[tuple[Path, int]]:
    """Stream cursor rows into numbered XLSX part files (one sheet per file)."""
    import xlsxwriter

    # Named (server-side) cursors only populate description after first FETCH.
    first_batch = cursor.fetchmany(FETCH_SIZE)
    columns = [desc[0] for desc in cursor.description]

    parts: list[tuple[Path, int]] = []
    part_num = 0
    current_wb = None
    current_ws = None
    current_path: Path | None = None
    rows_in_part = 0
    total_rows = 0
    row_idx = 1

    def _open_part() -> None:
        nonlocal part_num, current_wb, current_ws, current_path, rows_in_part, row_idx
        part_num += 1
        current_path = tmp_dir / f"{base_name}_parte_{part_num:03d}.xlsx"
        current_wb = xlsxwriter.Workbook(str(current_path), {"constant_memory": True})
        hdr_fmt = current_wb.add_format(
            {"bold": True, "bg_color": "#004B87", "font_color": "#FFFFFF"}
        )
        meta_label_fmt = current_wb.add_format({"bold": True, "bg_color": "#D6E4F0"})
        meta_value_fmt = current_wb.add_format({"bg_color": "#EBF4FB"})
        current_ws = current_wb.add_worksheet("Reporte")
        start_row = 0
        if meta_rows and part_num == 1:
            for label, value in meta_rows:
                current_ws.write(start_row, 0, label, meta_label_fmt)
                current_ws.write(start_row, 1, value, meta_value_fmt)
                start_row += 1
            start_row += 1  # blank separator
        for col_idx, col_name in enumerate(columns):
            current_ws.write(start_row, col_idx, col_name, hdr_fmt)
        rows_in_part = 0
        row_idx = start_row + 1

    def _close_part() -> None:
        nonlocal current_wb
        if current_wb is not None:
            current_wb.close()
            current_wb = None
            parts.append((current_path, rows_in_part))

    def _write_batch(batch: list) -> None:
        nonlocal rows_in_part, total_rows, row_idx
        for row in batch:
            if rows_in_part >= rows_per_file:
                _close_part()
                _open_part()
            current_ws.write_row(
                row_idx,
                0,
                [row[c] if row[c] is not None else "" for c in columns],
            )
            row_idx += 1
            rows_in_part += 1
            total_rows += 1
        if progress_callback is not None:
            progress_callback(total_rows, part_num)

    _open_part()
    try:
        _write_batch(first_batch)
        while True:
            batch = cursor.fetchmany(FETCH_SIZE)
            if not batch:
                break
            _write_batch(batch)
        _close_part()
    except Exception:
        if current_wb is not None:
            try:
                current_wb.close()
            except Exception:
                pass
        raise

    return parts


def _pack_zip(
    parts: list[tuple[Path, int]],
    zip_path: Path,
    manifest: dict[str, Any],
) -> None:
    """Pack part files + manifest.json into a ZIP64 archive."""
    with zipfile.ZipFile(
        str(zip_path),
        "w",
        compression=zipfile.ZIP_DEFLATED,
        allowZip64=True,
    ) as zf:
        for part_path, _ in parts:
            zf.write(str(part_path), arcname=part_path.name)
        zf.writestr(
            "manifest.json",
            json.dumps(manifest, ensure_ascii=False, indent=2),
        )


def _estimate_rows(conn, sql: str, params: dict) -> int:
    """Estimate result row count via the PostgreSQL planner (no execution).

    Returns -1 if the estimate cannot be obtained.
    """
    try:
        with conn.cursor() as cur:
            cur.execute("EXPLAIN (FORMAT JSON) " + sql, params)
            row = cur.fetchone()
            # The connection uses RealDictCursor, so EXPLAIN returns
            # {"QUERY PLAN": [...]}; fall back to positional access otherwise.
            plan = row["QUERY PLAN"] if isinstance(row, dict) else row[0]
            return int(plan[0]["Plan"]["Plan Rows"])
    except Exception:
        logger.warning("No se pudo estimar filas con EXPLAIN.", exc_info=True)
        return -1


def cleanup_old_report_files(db, usuario_email: str | None = None) -> int:
    """Keep only the newest generated files for each user."""
    base_query = db.query(Solicitud).filter(
        Solicitud.estado == "FINALIZADO",
        Solicitud.archivo_ruta.isnot(None),
    )
    if usuario_email is None:
        users = [
            row[0]
            for row in db.query(Solicitud.usuario_email)
            .filter(Solicitud.archivo_ruta.isnot(None))
            .distinct()
            .all()
        ]
    else:
        users = [usuario_email]

    output_dir = Path(settings.output_dir).resolve()
    deleted = 0
    for email in users:
        expired = (
            base_query.filter(Solicitud.usuario_email == email)
            .order_by(Solicitud.fecha_fin.desc(), Solicitud.id.desc())
            .offset(settings.max_files_per_user)
            .all()
        )
        for solicitud in expired:
            filepath = Path(solicitud.archivo_ruta).resolve()
            try:
                filepath.relative_to(output_dir)
            except ValueError:
                logger.error(
                    "No se eliminó el archivo fuera del directorio permitido: %s", filepath
                )
                continue
            try:
                filepath.unlink(missing_ok=True)
            except OSError:
                logger.exception("No se pudo eliminar el archivo antiguo: %s", filepath)
                continue
            solicitud.estado = "EXPIRADO"
            solicitud.archivo_nombre = None
            solicitud.archivo_ruta = None
            solicitud.archivo_tamano = None
            solicitud.token_descarga = None
            deleted += 1

    db.commit()
    if deleted:
        logger.info("Limpieza de reportes: %d archivos antiguos eliminados.", deleted)
    return deleted


def process_report_job(solicitud_id: int) -> None:
    """RQ job entry point."""
    db = ControlSessionLocal()
    solicitud: Solicitud | None = None
    tmp_dir: Path | None = None

    try:
        solicitud = db.get(Solicitud, solicitud_id)
        if solicitud is None:
            logger.error("Solicitud %d no encontrada.", solicitud_id)
            return
        if solicitud.estado == "CANCELADO":
            logger.info("[%d] Solicitud cancelada antes de iniciar.", solicitud_id)
            return

        solicitud.estado = "PROCESANDO"
        solicitud.fecha_inicio = now_bogota()
        solicitud.filas_procesadas = 0
        solicitud.partes_generadas = 0
        solicitud.fecha_ultimo_progreso = now_bogota()
        solicitud.mensaje_progreso = "Iniciando generación del reporte."
        db.commit()
        logger.info("[%d] Iniciando reporte '%s'.", solicitud_id, solicitud.reporte_codigo)

        reporte = get_reporte(solicitud.reporte_codigo)
        sql = reporte.load_sql()
        params = _build_params(solicitud.filtros or {}, solicitud.reporte_codigo)
        gen_time = now_bogota()
        meta_rows = _build_meta_rows(reporte, params, gen_time)

        out_dir = Path(settings.output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        tmp_dir = out_dir / f"_tmp_{solicitud_id}_{int(time.time())}"
        tmp_dir.mkdir(parents=True, exist_ok=True)

        base_name = f"reporte_{solicitud_id}"
        t0 = time.perf_counter()
        last_progress_rows = 0
        last_progress_time = time.monotonic()

        def _update_progress(total_rows: int, part_count: int, force: bool = False) -> None:
            nonlocal last_progress_rows, last_progress_time
            now = time.monotonic()
            if (
                not force
                and total_rows - last_progress_rows < PROGRESS_UPDATE_ROWS
                and now - last_progress_time < PROGRESS_UPDATE_SECONDS
            ):
                return

            db.refresh(solicitud)
            if solicitud.estado == "CANCELADO":
                raise ReportCancelled()

            solicitud.filas_procesadas = total_rows
            solicitud.partes_generadas = max(part_count, 1)
            solicitud.fecha_ultimo_progreso = now_bogota()
            solicitud.mensaje_progreso = (
                f"{total_rows:,} filas exportadas en {max(part_count, 1)} parte(s)."
            )
            db.commit()
            last_progress_rows = total_rows
            last_progress_time = now

        _update_progress(0, 1, force=True)

        # Effective output format — may be downgraded to CSV for big reports.
        formato = solicitud.formato

        # Named (server-side) cursor — true streaming from PostgreSQL
        with get_moodle_conn() as conn:
            # Auto-switch XLSX → CSV when the planner estimates a large result:
            # XLSX is far slower/heavier and Excel cannot open huge files.
            if formato == "xlsx" and settings.auto_csv_row_threshold > 0:
                est_rows = _estimate_rows(conn, sql, params)
                if est_rows >= settings.auto_csv_row_threshold:
                    formato = "csv"
                    logger.info(
                        "[%d] Auto-cambio XLSX→CSV: ~%d filas estimadas (umbral %d).",
                        solicitud_id, est_rows, settings.auto_csv_row_threshold,
                    )
                    solicitud.mensaje_progreso = (
                        f"Reporte grande (~{est_rows:,} filas): se genera CSV "
                        f"para mayor velocidad y compatibilidad."
                    )
                    db.commit()

            cursor_name = f"rpt_{solicitud_id}"
            with conn.cursor(cursor_name, cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(sql, params)
                if formato == "csv":
                    parts = _stream_csv_parts(
                        cur,
                        tmp_dir,
                        base_name,
                        settings.csv_rows_per_file,
                        meta_rows,
                        _update_progress,
                    )
                else:
                    parts = _stream_xlsx_parts(
                        cur,
                        tmp_dir,
                        base_name,
                        settings.xlsx_rows_per_file,
                        meta_rows,
                        _update_progress,
                    )

        total_rows = sum(rc for _, rc in parts)
        elapsed = time.perf_counter() - t0
        _update_progress(total_rows, len(parts), force=True)

        db.refresh(solicitud)
        if solicitud.estado == "CANCELADO":
            logger.info("[%d] Solicitud cancelada durante la generación.", solicitud_id)
            shutil.rmtree(tmp_dir, ignore_errors=True)
            tmp_dir = None
            for part_path, _ in parts:
                try:
                    Path(part_path).unlink(missing_ok=True)
                except OSError:
                    logger.warning("[%d] No se pudo eliminar parte temporal: %s", solicitud_id, part_path)
            return

        # Sin filas: no se genera archivo descargable. Se informa al usuario
        # que los datos no corresponden (estado dedicado, sin descarga).
        if total_rows == 0:
            logger.info("[%d] Consulta sin resultados — no se genera archivo.", solicitud_id)
            for part_path, _ in parts:
                Path(part_path).unlink(missing_ok=True)
            shutil.rmtree(tmp_dir, ignore_errors=True)
            tmp_dir = None
            solicitud.estado = "SIN_RESULTADOS"
            solicitud.fecha_fin = now_bogota()
            solicitud.filas_procesadas = 0
            solicitud.archivo_ruta = None
            solicitud.archivo_nombre = None
            solicitud.mensaje_error = "Los datos ingresados no corresponden. Por favor validar."
            db.commit()
            return

        if len(parts) == 1:
            final_path, filename = _output_path(
                solicitud_id, solicitud.usuario_email or "anonimo", formato
            )
            shutil.move(str(parts[0][0]), str(final_path))
        else:
            final_path, filename = _output_path(
                solicitud_id, solicitud.usuario_email or "anonimo", "zip"
            )
            manifest = {
                "reporte": solicitud.reporte_codigo,
                "filtros": solicitud.filtros or {},
                "formato": formato,
                "total_filas": total_rows,
                "total_partes": len(parts),
                "filas_por_parte": [
                    {"parte": i + 1, "filas": rc}
                    for i, (_, rc) in enumerate(parts)
                ],
                "generado_en": now_bogota().isoformat(),
            }
            _pack_zip(parts, final_path, manifest)

        shutil.rmtree(tmp_dir, ignore_errors=True)
        tmp_dir = None

        file_size = os.path.getsize(final_path)
        token = secrets.token_hex(24)

        logger.info(
            "[%d] Finalizado: %d filas, %d parte(s), %.1f s, %.1f KB.",
            solicitud_id, total_rows, len(parts), elapsed, file_size / 1024,
        )

        solicitud.estado = "FINALIZADO"
        solicitud.fecha_fin = now_bogota()
        solicitud.formato = formato
        solicitud.archivo_nombre = filename
        solicitud.archivo_ruta = str(final_path)
        solicitud.archivo_tamano = file_size
        solicitud.filas_procesadas = total_rows
        solicitud.partes_generadas = len(parts)
        solicitud.fecha_ultimo_progreso = now_bogota()
        solicitud.mensaje_progreso = (
            f"Reporte finalizado: {total_rows:,} filas en {len(parts)} parte(s)."
        )
        solicitud.token_descarga = token
        db.commit()

        try:
            cleanup_old_report_files(db, solicitud.usuario_email)
        except Exception:
            db.rollback()
            logger.exception("[%d] No fue posible limpiar archivos antiguos.", solicitud_id)

    except ReportCancelled:
        logger.info("[%d] Generación cancelada por el usuario.", solicitud_id)
        if tmp_dir is not None:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        if solicitud is not None:
            try:
                solicitud.fecha_fin = now_bogota()
                solicitud.mensaje_error = "Solicitud cancelada por el usuario."
                solicitud.mensaje_progreso = "Generación cancelada."
                db.commit()
            except Exception:
                db.rollback()
    except Exception as exc:
        logger.exception("[%d] Error en reporte.", solicitud_id)
        if tmp_dir is not None:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        if solicitud is not None:
            try:
                db.refresh(solicitud)
                if solicitud.estado == "CANCELADO":
                    return
                solicitud.estado = "ERROR"
                solicitud.fecha_fin = now_bogota()
                solicitud.mensaje_error = str(exc)[:2000]
                db.commit()
            except Exception:
                db.rollback()
    finally:
        db.close()
