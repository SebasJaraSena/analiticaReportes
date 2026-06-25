from api.reportes.registry import (
    FiltroDefinicion, ReporteDefinicion, registrar,
    OPC_ORIGEN_DATOS,
)

_RANGO_CONSULTA = [
    {"value": "",    "label": "Todas"},
    {"value": "Año", "label": "Año"},
    {"value": "Mes", "label": "Mes"},
    {"value": "Día", "label": "Día"},
]

registrar(
    ReporteDefinicion(
        codigo="trafico_diario",
        nombre="Tráfico Diario de Usuarios",
        descripcion=(
            "Eventos diarios del LMS: total eventos, usuarios únicos y grupos/fichas "
            "con actividad por día."
        ),
        filtros=[
            FiltroDefinicion("fecha_desde",     "Rango de fecha desde",  "date"),
            FiltroDefinicion("fecha_hasta",     "Rango de fecha hasta",  "date"),
            FiltroDefinicion("origen_datos",    "Origen de datos",       "select", opciones=OPC_ORIGEN_DATOS),
            FiltroDefinicion("rango_consulta",  "Rango de Consulta",     "select", opciones=_RANGO_CONSULTA),
        ],
    )
)
