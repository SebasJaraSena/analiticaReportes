from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

registrar(
    ReporteDefinicion(
        codigo="ingresos_sistema",
        nombre="Ingresos por Navegador, Ubicación y Sistema",
        descripcion=(
            "Análisis de accesos al LMS agrupados por navegador, sistema operativo "
            "y ubicación geográfica aproximada, extraída del log estándar de Moodle."
        ),
        filtros=[
            FiltroDefinicion("fecha_desde", "Fecha Desde", "date", requerido=True),
            FiltroDefinicion("fecha_hasta", "Fecha Hasta", "date", requerido=True),
            FiltroDefinicion("usuario_email", "Email de Usuario", "text"),
        ],
    )
)
