from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]

registrar(
    ReporteDefinicion(
        codigo="participacion_herramientas",
        nombre="Participación por Herramientas",
        descripcion=(
            "Por aprendiz/ficha: ingresos, blogs, evaluaciones, evidencias, "
            "foros, comentarios, sondeos, wikis, SCORM y sesiones en línea."
        ),
        filtros=[
            FiltroDefinicion("codigo_ficha",     "Código Ficha",        "text", placeholder="Ej: 2850022"),
            FiltroDefinicion("nombre_ficha",     "Nombre Ficha",        "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("codigo_programa",  "Código Programa",     "text", placeholder="Ej: 228106"),
            FiltroDefinicion("nombre_programa",  "Nombre Programa",     "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("nivel",            "Nivel",               "text", placeholder="Ej: Formación titulada"),
            FiltroDefinicion("modalidad",        "Modalidad",           "text", placeholder="Ej: Virtual, Presencial, Distancia"),
            FiltroDefinicion("regional",         "Regional",            "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("centro_formacion", "Centro de Formación", "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("estado_grupo",     "Estado Grupo/Ficha",  "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("identificacion",   "Identificación",      "text", placeholder="Número de documento"),
            FiltroDefinicion("nombres_apellidos","Nombres y Apellidos", "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("id_categoria",       "ID Categoría Moodle",  "text", placeholder="Ej: 3 (CEET)"),
            FiltroDefinicion("fecha_inicio_desde", "Inicio Grupo Desde",   "date"),
            FiltroDefinicion("fecha_inicio_hasta", "Inicio Grupo Hasta",   "date"),
            FiltroDefinicion("fecha_fin_desde",    "Fin Grupo Desde",      "date"),
            FiltroDefinicion("fecha_fin_hasta",    "Fin Grupo Hasta",      "date"),
            FiltroDefinicion("fecha_desde",        "Fecha Consulta Desde", "date"),
            FiltroDefinicion("fecha_hasta",        "Fecha Consulta Hasta", "date"),
        ],
    )
)
