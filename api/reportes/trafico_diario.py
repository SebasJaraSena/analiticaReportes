from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

registrar(
    ReporteDefinicion(
        codigo="trafico_diario",
        nombre="Tráfico Diario de Usuarios",
        descripcion=(
            "Eventos diarios del LMS: total eventos, usuarios únicos y grupos/fichas "
            "con actividad por día."
        ),
        filtros=[
            FiltroDefinicion("fecha_desde", "Fecha Desde", "date", requerido=True),
            FiltroDefinicion("fecha_hasta", "Fecha Hasta", "date", requerido=True),
        ],
    )
)
