from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]
_ROLES = [
    {"value": "student",        "label": "Aprendiz"},
    {"value": "teacher",        "label": "Instructor"},
    {"value": "editingteacher", "label": "Instructor Editor"},
]

registrar(
    ReporteDefinicion(
        codigo="matriculas_lms",
        nombre="Matrículas LMS",
        descripcion=(
            "Matrículas con nivel, modalidad, programa, regional, centro, "
            "tipo de documento, estado y fechas de enrolamiento."
        ),
        filtros=[
            FiltroDefinicion("codigo_ficha",       "Código Ficha",           "text", placeholder="Ej: 2850022"),
            FiltroDefinicion("nombre_ficha",       "Nombre Ficha",           "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("codigo_programa",    "Código Programa",        "text", placeholder="Ej: 228106"),
            FiltroDefinicion("nivel",              "Nivel",                  "text", placeholder="Ej: Formación titulada"),
            FiltroDefinicion("modalidad",          "Modalidad",              "text", placeholder="Ej: Virtual, Presencial, Distancia"),
            FiltroDefinicion("regional",           "Regional",               "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("centro_formacion",   "Centro de Formación",    "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("estado_grupo",       "Estado Grupo/Ficha",     "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario",        "Rol de Usuario",         "select", opciones=_ROLES),
            FiltroDefinicion("identificacion",     "Identificación",         "text", placeholder="Número de documento"),
            FiltroDefinicion("nombres_apellidos",  "Nombres y Apellidos",    "text", placeholder="Búsqueda parcial"),
            FiltroDefinicion("fecha_desde",        "Fecha Matrícula Desde",  "date"),
            FiltroDefinicion("fecha_hasta",        "Fecha Matrícula Hasta",  "date"),
            FiltroDefinicion("fecha_inicio_desde", "Inicio Grupo Desde",     "date"),
            FiltroDefinicion("fecha_inicio_hasta", "Inicio Grupo Hasta",     "date"),
            FiltroDefinicion("fecha_fin_desde",    "Fin Grupo Desde",        "date"),
            FiltroDefinicion("fecha_fin_hasta",    "Fin Grupo Hasta",        "date"),
        ],
    )
)
