from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]

registrar(
    ReporteDefinicion(
        codigo="uso_herramientas",
        nombre="Herramientas LMS",
        descripcion=(
            "Por grupo/ficha: número de usuarios y cantidad por herramienta "
            "(wikis, encuestas, evaluaciones, evidencias, blogs, foros, SCORM, BBB)."
        ),
        filtros=[
            FiltroDefinicion("codigo_ficha",    "Código Ficha",        "text", placeholder="Ej: 2850022"),
            FiltroDefinicion("nombre_ficha",    "Nombre Ficha",        "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("codigo_programa", "Código Programa",     "text", placeholder="Ej: 228106"),
            FiltroDefinicion("nivel",           "Nivel",               "text", placeholder="Ej: Formación titulada"),
            FiltroDefinicion("modalidad",       "Modalidad",           "text", placeholder="Ej: Virtual, Presencial, Distancia"),
            FiltroDefinicion("regional",        "Regional",            "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("centro_formacion","Centro de Formación", "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("estado_grupo",    "Estado Grupo/Ficha",  "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("fecha_desde",     "Fecha Inicio Desde",  "date"),
            FiltroDefinicion("fecha_hasta",     "Fecha Inicio Hasta",  "date"),
        ],
    )
)
