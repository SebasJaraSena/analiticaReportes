from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ORIGEN_DATOS = [
    {"value": "",                      "label": "Todas"},
    {"value": "Manual",                "label": "Manual"},
    {"value": "Integración / Externo", "label": "Integración / Externo"},
]

registrar(
    ReporteDefinicion(
        codigo="usuarios_ambiente",
        nombre="Usuarios por Ambiente",
        descripcion=(
            "Detalle por usuario: rol, tipo documento, estado, origen, "
            "fecha de creación y último acceso."
        ),
        filtros=[
            FiltroDefinicion("mes",          "Mes",                          "text", placeholder="Todas"),
            FiltroDefinicion("anio",         "Año",                          "text", placeholder="Todas"),
            FiltroDefinicion("origen_datos", "Origen de datos",              "select", opciones=_ORIGEN_DATOS),
            FiltroDefinicion("fecha_desde",  "Rango de fecha desde",         "date"),
            FiltroDefinicion("fecha_hasta",  "Rango de fecha hasta",         "date"),
        ],
    )
)
