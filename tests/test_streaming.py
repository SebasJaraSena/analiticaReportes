"""
Tests for streaming multi-part export.
All tests use mock cursors — no real database required.
"""
from __future__ import annotations

import csv
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from api.jobs import _pack_zip, _stream_csv_parts, _stream_xlsx_parts


COLUMNS = ("id", "nombre", "valor")


class MockCursor:
    """Simulates a psycopg2 RealDictCursor without a real database."""

    def __init__(self, n_rows: int, columns: tuple[str, ...] = COLUMNS) -> None:
        self._rows = [
            {"id": i, "nombre": f"fila_{i}", "valor": i * 1.5}
            for i in range(1, n_rows + 1)
        ]
        self._pos = 0
        self.description = tuple((col,) + (None,) * 6 for col in columns)

    def fetchmany(self, size: int) -> list[dict]:
        batch = self._rows[self._pos : self._pos + size]
        self._pos += len(batch)
        return list(batch)


def _read_csv_rows(path: Path) -> list[dict]:
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def _read_xlsx_rows(path: Path) -> list[tuple]:
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True)
    ws = wb.active
    rows = list(ws.values)
    wb.close()
    return rows[1:]  # skip header row


# ── CSV tests ─────────────────────────────────────────────────────────────────

def test_csv_zero_rows(tmp_path: Path) -> None:
    parts = _stream_csv_parts(MockCursor(0), tmp_path, "rep", rows_per_file=5)
    assert len(parts) == 1
    path, count = parts[0]
    assert count == 0
    assert _read_csv_rows(path) == []


def test_csv_exact_limit(tmp_path: Path) -> None:
    parts = _stream_csv_parts(MockCursor(5), tmp_path, "rep", rows_per_file=5)
    assert len(parts) == 1
    path, count = parts[0]
    assert count == 5
    rows = _read_csv_rows(path)
    assert len(rows) == 5
    assert rows[0]["id"] == "1"
    assert rows[-1]["id"] == "5"


def test_csv_limit_plus_one(tmp_path: Path) -> None:
    parts = _stream_csv_parts(MockCursor(6), tmp_path, "rep", rows_per_file=5)
    assert len(parts) == 2
    assert parts[0][1] == 5
    assert parts[1][1] == 1
    all_rows = _read_csv_rows(parts[0][0]) + _read_csv_rows(parts[1][0])
    assert len(all_rows) == 6
    ids = [int(r["id"]) for r in all_rows]
    assert ids == list(range(1, 7))


def test_csv_multiple_parts(tmp_path: Path) -> None:
    parts = _stream_csv_parts(MockCursor(15), tmp_path, "rep", rows_per_file=5)
    assert len(parts) == 3
    assert all(count == 5 for _, count in parts)
    all_rows: list[dict] = []
    for p, _ in parts:
        all_rows.extend(_read_csv_rows(p))
    assert len(all_rows) == 15
    assert [int(r["id"]) for r in all_rows] == list(range(1, 16))


def test_csv_headers_in_every_part(tmp_path: Path) -> None:
    parts = _stream_csv_parts(MockCursor(7), tmp_path, "rep", rows_per_file=3)
    assert len(parts) == 3
    for p, _ in parts:
        with open(p, newline="", encoding="utf-8-sig") as f:
            header = f.readline().strip()
        assert "id" in header
        assert "nombre" in header


def test_csv_part_filenames(tmp_path: Path) -> None:
    parts = _stream_csv_parts(MockCursor(11), tmp_path, "rep", rows_per_file=5)
    names = [p.name for p, _ in parts]
    assert names == ["rep_parte_001.csv", "rep_parte_002.csv", "rep_parte_003.csv"]


# ── XLSX tests ────────────────────────────────────────────────────────────────

def test_xlsx_exact_limit(tmp_path: Path) -> None:
    parts = _stream_xlsx_parts(MockCursor(5), tmp_path, "rep", rows_per_file=5)
    assert len(parts) == 1
    path, count = parts[0]
    assert count == 5
    data = _read_xlsx_rows(path)
    assert len(data) == 5


def test_xlsx_limit_plus_one(tmp_path: Path) -> None:
    parts = _stream_xlsx_parts(MockCursor(6), tmp_path, "rep", rows_per_file=5)
    assert len(parts) == 2
    assert parts[0][1] == 5
    assert parts[1][1] == 1
    all_rows = _read_xlsx_rows(parts[0][0]) + _read_xlsx_rows(parts[1][0])
    assert len(all_rows) == 6
    ids = [row[0] for row in all_rows]
    assert ids == list(range(1, 7))


def test_xlsx_multiple_parts(tmp_path: Path) -> None:
    parts = _stream_xlsx_parts(MockCursor(15), tmp_path, "rep", rows_per_file=5)
    assert len(parts) == 3
    all_rows = []
    for p, _ in parts:
        all_rows.extend(_read_xlsx_rows(p))
    assert len(all_rows) == 15
    assert [row[0] for row in all_rows] == list(range(1, 16))


def test_xlsx_headers_in_every_part(tmp_path: Path) -> None:
    import openpyxl
    parts = _stream_xlsx_parts(MockCursor(7), tmp_path, "rep", rows_per_file=3)
    for p, _ in parts:
        wb = openpyxl.load_workbook(p, read_only=True)
        first_row = next(wb.active.rows)
        header_values = [c.value for c in first_row]
        wb.close()
        assert header_values == list(COLUMNS)


# ── ZIP / manifest tests ──────────────────────────────────────────────────────

def test_pack_zip_structure(tmp_path: Path) -> None:
    p1 = tmp_path / "rep_parte_001.csv"
    p2 = tmp_path / "rep_parte_002.csv"
    p1.write_text("id\n1\n2\n")
    p2.write_text("id\n3\n")
    parts = [(p1, 2), (p2, 1)]
    manifest = {
        "reporte": "test",
        "formato": "csv",
        "total_filas": 3,
        "total_partes": 2,
        "filas_por_parte": [{"parte": 1, "filas": 2}, {"parte": 2, "filas": 1}],
        "generado_en": "2026-01-01T00:00:00",
    }
    zip_path = tmp_path / "output.zip"
    _pack_zip(parts, zip_path, manifest)

    assert zip_path.exists()
    with zipfile.ZipFile(str(zip_path)) as zf:
        names = zf.namelist()
        assert "rep_parte_001.csv" in names
        assert "rep_parte_002.csv" in names
        assert "manifest.json" in names
        loaded = json.loads(zf.read("manifest.json"))
        assert loaded["total_filas"] == 3
        assert loaded["total_partes"] == 2


def test_pack_zip64_flag(tmp_path: Path) -> None:
    p1 = tmp_path / "part.csv"
    p1.write_text("x\n1\n")
    zip_path = tmp_path / "out.zip"
    _pack_zip([(p1, 1)], zip_path, {"test": True})
    with zipfile.ZipFile(str(zip_path)) as zf:
        assert len(zf.namelist()) == 2  # part + manifest


def test_csv_and_xlsx_row_counts_match(tmp_path: Path) -> None:
    n = 13
    rows_per_file = 5

    csv_dir = tmp_path / "csv"
    xlsx_dir = tmp_path / "xlsx"
    csv_dir.mkdir()
    xlsx_dir.mkdir()

    csv_parts = _stream_csv_parts(MockCursor(n), csv_dir, "rep", rows_per_file)
    xlsx_parts = _stream_xlsx_parts(MockCursor(n), xlsx_dir, "rep", rows_per_file)

    assert sum(c for _, c in csv_parts) == n
    assert sum(c for _, c in xlsx_parts) == n
    assert len(csv_parts) == len(xlsx_parts)
