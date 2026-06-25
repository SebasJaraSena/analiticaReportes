from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

registrar(
    ReporteDefinicion(
        codigo="usuarios_ambiente",
        nombre="Usuarios por Ambiente",
        descripcion=(
            "Detalle por usuario: rol, tipo documento, estado, origen, "
            "fecha de creación y último acceso."
        ),
        filtros=[
            FiltroDefinicion("identificacion",   "Identificación",       "text", placeholder="Número de documento"),
            FiltroDefinicion("nombres_apellidos","Nombres y Apellidos",  "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("estado", "Estado", "select", opciones=[
                {"value": "Activo",     "label": "Activo"},
                {"value": "Suspendido", "label": "Suspendido"},
                {"value": "Eliminado",  "label": "Eliminado"},
            ]),
            FiltroDefinicion("fecha_desde", "Fecha Creación Desde", "date"),
            FiltroDefinicion("fecha_hasta", "Fecha Creación Hasta", "date"),
        ],
    )
)
