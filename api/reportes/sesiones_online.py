from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]

registrar(
    ReporteDefinicion(
        codigo="sesiones_online",
        nombre="Sesiones en Línea (BBB)",
        descripcion=(
            "Sesiones BigBlueButton por grupo/ficha: nombre, fechas, "
            "usuarios participantes, estado de inicio y grabación."
        ),
        filtros=[
            FiltroDefinicion("codigo_ficha",               "Código Ficha",              "text", placeholder="Ej: 2850022"),
            FiltroDefinicion("nombre_ficha",               "Nombre Ficha",              "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("codigo_programa",            "Código Programa",           "text", placeholder="Ej: 228106"),
            FiltroDefinicion("nombre_programa",            "Nombre Programa",           "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("nivel",                      "Nivel",                     "text", placeholder="Ej: Formación titulada"),
            FiltroDefinicion("modalidad",                  "Modalidad",                 "text", placeholder="Ej: Virtual, Presencial, Distancia"),
            FiltroDefinicion("regional",                   "Regional",                  "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("centro_formacion",           "Centro de Formación",       "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("estado_grupo",               "Estado Grupo/Ficha",        "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("identificacion",             "Identificación",            "text", placeholder="Número de documento"),
            FiltroDefinicion("nombres_apellidos",          "Nombres y Apellidos",       "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("fecha_desde",                "Fecha Sesión Desde",        "date"),
            FiltroDefinicion("fecha_hasta",                "Fecha Sesión Hasta",        "date"),
            FiltroDefinicion("fecha_inicio_grupo_desde",   "Inicio Grupo Desde",        "date"),
            FiltroDefinicion("fecha_inicio_grupo_hasta",   "Inicio Grupo Hasta",        "date"),
            FiltroDefinicion("fecha_creacion_grupo_desde", "Creación Grupo Desde",      "date"),
            FiltroDefinicion("fecha_creacion_grupo_hasta", "Creación Grupo Hasta",      "date"),
        ],
    )
)
