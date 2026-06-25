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
from pathlib import Path
from typing import Any

import psycopg2.extras

from api.config import settings
from api.database import ControlSessionLocal, get_moodle_conn
from api.models import Solicitud
from api.reportes.registry import get_reporte

logger = logging.getLogger(__name__)

FETCH_SIZE = 5_000  # rows per PostgreSQL FETCH batch


def _null_if_empty(value: Any) -> Any:
    """Convert empty string filter values to None (= no filter)."""
    if isinstance(value, str) and value.strip() == "":
        return None
    return value


def _build_params(filtros: dict[str, Any], reporte_codigo: str) -> dict[str, Any]:
    reporte = get_reporte(reporte_codigo)
    expected = {f.nombre for f in reporte.filtros}
    return {k: _null_if_empty(filtros.get(k)) for k in expected}


def _output_path(solicitud_id: int, usuario_email: str, extension: str) -> tuple[Path, str]:
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
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
        rows.append((f.etiqueta, str(val) if val not in (None, "", []) else "Todos"))
    return rows


def _stream_csv_parts(
    cursor: psycopg2.extras.RealDictCursor,
    tmp_dir: Path,
    base_name: str,
    rows_per_file: int,
    meta_rows: list[tuple[str, str]] | None = None,
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

    def _open_part() -> None:
        nonlocal part_num, current_file, current_writer, current_path, rows_in_part
        part_num += 1
        current_path = tmp_dir / f"{base_name}_parte_{part_num:03d}.csv"
        current_file = open(current_path, "w", newline="", encoding="utf-8-sig")
        current_writer = csv.DictWriter(current_file, fieldnames=columns)
        if meta_rows and part_num == 1:
            meta_writer = csv.writer(current_file)
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
        nonlocal rows_in_part
        for row in batch:
            if rows_in_part >= rows_per_file:
                _close_part()
                _open_part()
            current_writer.writerow(row)
            rows_in_part += 1

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
        nonlocal rows_in_part, row_idx
        for row in batch:
            if rows_in_part >= rows_per_file:
                _close_part()
                _open_part()
            for col_idx, col_name in enumerate(columns):
                value = row.get(col_name)
                current_ws.write(row_idx, col_idx, value if value is not None else "")
            row_idx += 1
            rows_in_part += 1

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

        solicitud.estado = "PROCESANDO"
        solicitud.fecha_inicio = datetime.utcnow()
        db.commit()
        logger.info("[%d] Iniciando reporte '%s'.", solicitud_id, solicitud.reporte_codigo)

        reporte = get_reporte(solicitud.reporte_codigo)
        sql = reporte.load_sql()
        params = _build_params(solicitud.filtros or {}, solicitud.reporte_codigo)
        gen_time = datetime.utcnow()
        meta_rows = _build_meta_rows(reporte, params, gen_time)

        out_dir = Path(settings.output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        tmp_dir = out_dir / f"_tmp_{solicitud_id}_{int(time.time())}"
        tmp_dir.mkdir(parents=True, exist_ok=True)

        base_name = f"reporte_{solicitud_id}"
        t0 = time.perf_counter()

        # Named (server-side) cursor — true streaming from PostgreSQL
        with get_moodle_conn() as conn:
            cursor_name = f"rpt_{solicitud_id}"
            with conn.cursor(cursor_name, cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(sql, params)
                if solicitud.formato == "csv":
                    parts = _stream_csv_parts(cur, tmp_dir, base_name, settings.rows_per_file, meta_rows)
                else:
                    parts = _stream_xlsx_parts(cur, tmp_dir, base_name, settings.rows_per_file, meta_rows)

        total_rows = sum(rc for _, rc in parts)
        elapsed = time.perf_counter() - t0

        if len(parts) == 1:
            final_path, filename = _output_path(
                solicitud_id, solicitud.usuario_email or "anonimo", solicitud.formato
            )
            shutil.move(str(parts[0][0]), str(final_path))
        else:
            final_path, filename = _output_path(
                solicitud_id, solicitud.usuario_email or "anonimo", "zip"
            )
            manifest = {
                "reporte": solicitud.reporte_codigo,
                "filtros": solicitud.filtros or {},
                "formato": solicitud.formato,
                "total_filas": total_rows,
                "total_partes": len(parts),
                "filas_por_parte": [
                    {"parte": i + 1, "filas": rc}
                    for i, (_, rc) in enumerate(parts)
                ],
                "generado_en": datetime.utcnow().isoformat(),
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
        solicitud.fecha_fin = datetime.utcnow()
        solicitud.archivo_nombre = filename
        solicitud.archivo_ruta = str(final_path)
        solicitud.archivo_tamano = file_size
        solicitud.token_descarga = token
        db.commit()

        try:
            cleanup_old_report_files(db, solicitud.usuario_email)
        except Exception:
            db.rollback()
            logger.exception("[%d] No fue posible limpiar archivos antiguos.", solicitud_id)

    except Exception as exc:
        logger.exception("[%d] Error en reporte.", solicitud_id)
        if tmp_dir is not None:
            shutil.rmtree(tmp_dir, ignore_errors=True)
        if solicitud is not None:
            try:
                solicitud.estado = "ERROR"
                solicitud.fecha_fin = datetime.utcnow()
                solicitud.mensaje_error = str(exc)[:2000]
                db.commit()
            except Exception:
                db.rollback()
    finally:
        db.close()
