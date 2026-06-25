from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]

registrar(
    ReporteDefinicion(
        codigo="fichas_programas",
        nombre="Grupos y Programas de Formación",
        descripcion=(
            "Listado de grupos/fichas con programa, nivel, modalidad, regional, "
            "centro y conteo de instructores/aprendices activos e inactivos."
        ),
        filtros=[
            FiltroDefinicion("codigo_ficha",       "Código Ficha",           "text", placeholder="Ej: 2850022"),
            FiltroDefinicion("nombre_ficha",       "Nombre Ficha",           "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("codigo_programa",    "Código Programa",        "text", placeholder="Ej: 228106"),
            FiltroDefinicion("nombre_programa",    "Nombre Programa",        "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("nivel",              "Nivel",                  "text", placeholder="Ej: Formación titulada"),
            FiltroDefinicion("modalidad",          "Modalidad",              "text", placeholder="Ej: Virtual, Presencial, Distancia"),
            FiltroDefinicion("regional",           "Regional",               "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("centro_formacion",   "Centro de Formación",    "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("estado",             "Estado Grupo/Ficha",     "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("fecha_desde",        "Fecha Creación Desde",   "date"),
            FiltroDefinicion("fecha_hasta",        "Fecha Creación Hasta",   "date"),
            FiltroDefinicion("fecha_inicio_desde", "Inicio Grupo Desde",     "date"),
            FiltroDefinicion("fecha_inicio_hasta", "Inicio Grupo Hasta",     "date"),
            FiltroDefinicion("fecha_fin_desde",    "Fin Grupo Desde",        "date"),
            FiltroDefinicion("fecha_fin_hasta",    "Fin Grupo Hasta",        "date"),
        ],
    )
)
