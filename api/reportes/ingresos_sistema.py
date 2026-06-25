from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

registrar(
    ReporteDefinicion(
        codigo="ingresos_sistema",
        nombre="Ingresos por Navegador, Ubicación y Sistema",
        descripcion=(
            "Análisis de accesos al LMS agrupados por ubicación geográfica "
            "aproximada, extraída del log estándar de Moodle."
        ),
        filtros=[
            FiltroDefinicion("mes",         "Mes",                          "text", placeholder="1 a 12"),
            FiltroDefinicion("semana",       "Semana del año",               "text", placeholder="1 a 53"),
            FiltroDefinicion("hora",         "Hora",                         "text", placeholder="HH o HH:MM"),
            FiltroDefinicion("fecha_desde",  "Rango de fecha desde",         "date"),
            FiltroDefinicion("fecha_hasta",  "Rango de fecha hasta",         "date"),
            FiltroDefinicion("pais",         "País",                         "text", placeholder="Todas"),
            FiltroDefinicion("ciudad",       "Ciudad",                       "text", placeholder="Todas"),
        ],
    )
)
