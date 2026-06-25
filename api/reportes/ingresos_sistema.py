from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_TODAS = [{"value": "", "label": "Todas"}]

registrar(
    ReporteDefinicion(
        codigo="ingresos_sistema",
        nombre="Ingresos por Navegador, Ubicación y Sistema",
        descripcion=(
            "Análisis de accesos al LMS agrupados por navegador, sistema operativo "
            "y ubicación geográfica aproximada, extraída del log estándar de Moodle."
        ),
        filtros=[
            FiltroDefinicion("mes", "Mes", "text", placeholder="1 a 12"),
            FiltroDefinicion("semana", "Semana del año", "text", placeholder="1 a 53"),
            FiltroDefinicion("hora", "Hora", "text", placeholder="HH o HH:MM"),
            FiltroDefinicion("fecha_desde", "Rango de fecha de consulta desde", "date"),
            FiltroDefinicion("fecha_hasta", "Rango de fecha de consulta hasta", "date"),
            FiltroDefinicion("pais", "País", "text", placeholder="Todas"),
            FiltroDefinicion("ciudad", "Ciudad", "text", placeholder="Todas"),
        ],
    )
)
