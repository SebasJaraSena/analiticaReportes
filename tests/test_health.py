"""Minimal smoke tests — run with: pytest reportes_zajuna/tests/"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


def test_registry_loaded() -> None:
    from api.reportes.registry import REPORTES
    assert "registro_usuarios" in REPORTES
    assert "ingresos_sistema" in REPORTES
    assert "matriculas_lms" in REPORTES


def test_registro_usuarios_filtros() -> None:
    from api.reportes.registry import get_reporte
    r = get_reporte("registro_usuarios")
    nombres = [f.nombre for f in r.filtros]
    assert "codigo_ficha" in nombres
    assert "rol_usuario" in nombres
    assert "fecha_inicio_desde" in nombres


def test_sql_file_exists() -> None:
    from pathlib import Path
    sql_dir = Path(__file__).parent.parent / "api" / "sql"
    for codigo in ("registro_usuarios", "ingresos_sistema", "matriculas_lms"):
        assert (sql_dir / f"{codigo}.sql").exists(), f"Missing SQL: {codigo}.sql"


def test_null_if_empty() -> None:
    from api.jobs import _null_if_empty
    assert _null_if_empty("") is None
    assert _null_if_empty("  ") is None
    assert _null_if_empty("hola") == "hola"
    assert _null_if_empty(None) is None
    assert _null_if_empty(0) == 0


def test_xlsx_splits_into_parts(tmp_path) -> None:
    import openpyxl

    from api import jobs

    class FakeCursor:
        description = [("id",), ("nombre",)]

        def __init__(self) -> None:
            self._rows = [
                {"id": index, "nombre": f"Usuario {index}"}
                for index in range(1, 6)
            ]

        def fetchmany(self, _size: int):
            rows, self._rows = self._rows, []
            return rows

    parts = jobs._stream_xlsx_parts(FakeCursor(), tmp_path, "rep", rows_per_file=4)
    assert len(parts) == 2
    assert parts[0][1] == 4
    assert parts[1][1] == 1

    wb1 = openpyxl.load_workbook(parts[0][0], read_only=True)
    rows1 = list(wb1.active.values)
    wb1.close()
    assert rows1[0] == ("id", "nombre")
    assert rows1[1] == (1, "Usuario 1")
    assert rows1[4] == (4, "Usuario 4")
    assert len(rows1) == 5  # 1 header + 4 data

    wb2 = openpyxl.load_workbook(parts[1][0], read_only=True)
    rows2 = list(wb2.active.values)
    wb2.close()
    assert rows2[0] == ("id", "nombre")
    assert rows2[1] == (5, "Usuario 5")
    assert len(rows2) == 2  # 1 header + 1 data
