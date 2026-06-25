"""
Registry of available reports.
Each report definition includes: code, name, description, filters, and SQL loader.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

SQL_DIR = Path(__file__).parent.parent / "sql"


@dataclass
class FiltroDefinicion:
    nombre: str
    etiqueta: str
    tipo: str  # text | date | select
    requerido: bool = False
    opciones: list[dict] | None = None  # for select type
    placeholder: str = ""


@dataclass
class ReporteDefinicion:
    codigo: str
    nombre: str
    descripcion: str
    filtros: list[FiltroDefinicion] = field(default_factory=list)
    _sql_cache: str | None = field(default=None, repr=False, compare=False)

    def load_sql(self) -> str:
        if self._sql_cache is None:
            sql_file = SQL_DIR / f"{self.codigo}.sql"
            if not sql_file.exists():
                raise FileNotFoundError(f"SQL no encontrado: {sql_file}")
            self._sql_cache = sql_file.read_text(encoding="utf-8")
        return self._sql_cache

    def filtros_dict(self) -> list[dict[str, Any]]:
        return [
            {
                "nombre": f.nombre,
                "etiqueta": f.etiqueta,
                "tipo": f.tipo,
                "requerido": f.requerido,
                "opciones": f.opciones,
                "placeholder": f.placeholder,
            }
            for f in self.filtros
        ]


# ── Shared filter option lists (reused across multiple reports) ───────────────

OPC_TODAS: list[dict] = [{"value": "", "label": "Todas"}]

OPC_ESTADO_GRUPO: list[dict] = [
    {"value": "",             "label": "Todas"},
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]

OPC_NIVELES: list[dict] = [
    {"value": "",                   "label": "Todas"},
    {"value": "Formación titulada", "label": "Formación titulada"},
    {"value": "No definido",        "label": "No definido"},
]

OPC_MODALIDADES: list[dict] = [
    {"value": "",                    "label": "Todas"},
    {"value": "Titulada virtual",    "label": "Titulada virtual"},
    {"value": "Titulada presencial", "label": "Titulada presencial"},
    {"value": "Titulada a distancia","label": "Titulada a distancia"},
]

OPC_ROLES: list[dict] = [
    {"value": "",               "label": "Todas"},
    {"value": "student",        "label": "Aprendiz"},
    {"value": "teacher",        "label": "Instructor"},
    {"value": "editingteacher", "label": "Instructor editor"},
]

OPC_ORIGEN_DATOS: list[dict] = [
    {"value": "",             "label": "Todas"},
    {"value": "Integración",  "label": "Integración"},
    {"value": "Manual",       "label": "Manual"},
]

OPC_ESTADO_USUARIO: list[dict] = [
    {"value": "",           "label": "Todas"},
    {"value": "Activo",     "label": "Activo"},
    {"value": "Suspendido", "label": "Suspendido"},
    {"value": "Eliminado",  "label": "Eliminado"},
]


# ── Report definitions ───────────────────────────────────────────────────────

REPORTES: dict[str, ReporteDefinicion] = {}


def registrar(reporte: ReporteDefinicion) -> None:
    REPORTES[reporte.codigo] = reporte


def get_reporte(codigo: str) -> ReporteDefinicion:
    if codigo not in REPORTES:
        raise KeyError(f"Reporte '{codigo}' no encontrado.")
    return REPORTES[codigo]


# ── Load all report definitions ──────────────────────────────────────────────

from api.reportes import registro_usuarios        # noqa: E402, F401
from api.reportes import ingresos_sistema         # noqa: E402, F401
from api.reportes import matriculas_lms           # noqa: E402, F401
from api.reportes import usuarios_ambiente        # noqa: E402, F401
from api.reportes import fichas_programas         # noqa: E402, F401
from api.reportes import trafico_diario           # noqa: E402, F401
from api.reportes import uso_herramientas         # noqa: E402, F401
from api.reportes import participacion_herramientas  # noqa: E402, F401
from api.reportes import tiempo_permanencia       # noqa: E402, F401
from api.reportes import sesiones_online          # noqa: E402, F401
