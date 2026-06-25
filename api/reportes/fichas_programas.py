from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "", "label": "Todas"},
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]

_NIVELES = [
    {"value": "", "label": "Todas"},
    {"value": "Formación titulada", "label": "Formación titulada"},
    {"value": "No definido", "label": "No definido"},
]

_MODALIDADES = [
    {"value": "", "label": "Todas"},
    {"value": "virtual", "label": "Virtual"},
    {"value": "presencial", "label": "Presencial"},
    {"value": "distancia", "label": "A distancia"},
]

_ROLES = [
    {"value": "", "label": "Todas"},
    {"value": "student", "label": "Aprendiz"},
    {"value": "teacher", "label": "Instructor"},
    {"value": "editingteacher", "label": "Instructor editor"},
]

_ESTADO_APRENDIZ = [
    {"value": "", "label": "Todas"},
    {"value": "Activo", "label": "Activo"},
    {"value": "Inactivo", "label": "Inactivo"},
]

_ORIGEN_DATOS = [
    {"value": "", "label": "Todas"},
    {"value": "Integración", "label": "Integración"},
    {"value": "Manual", "label": "Manual"},
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
            FiltroDefinicion("nivel", "Nivel del programa", "select", opciones=_NIVELES),
            FiltroDefinicion("modalidad", "Modalidad", "select", opciones=_MODALIDADES),
            FiltroDefinicion("regional", "Regional", "text", placeholder="Todas"),
            FiltroDefinicion("centro_formacion", "Centro de Formación", "text", placeholder="Todas"),
            FiltroDefinicion("estado_grupo_sofia", "Estado del grupo/ficha SOFIA Plus", "select", opciones=[
                {"value": "", "label": "Todas"},
                {"value": "No disponible (SOFIA Plus)", "label": "No disponible (SOFIA Plus)"},
            ]),
            FiltroDefinicion("rol_usuario", "Rol de usuario", "select", opciones=_ROLES),
            FiltroDefinicion("estado_aprendiz", "Estado del aprendiz (SOFIA Plus)", "select", opciones=_ESTADO_APRENDIZ),
            FiltroDefinicion("origen_datos", "Origen de datos", "select", opciones=_ORIGEN_DATOS),
            FiltroDefinicion("codigo_programa", "Código programa", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_programa", "Nombre de programa", "text", placeholder="Todas"),
            FiltroDefinicion("hora_creacion", "Hora creación curso LMS", "text", placeholder="HH o HH:MM"),
            FiltroDefinicion("fecha_desde", "Rango de fecha creación curso LMS desde", "date"),
            FiltroDefinicion("fecha_hasta", "Rango de fecha creación curso LMS hasta", "date"),
            FiltroDefinicion("codigo_ficha", "Código grupo", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_ficha", "Nombre grupo en el LMS", "text", placeholder="Todas"),
            FiltroDefinicion("hora_grupo", "Hora grupo/ficha", "text", placeholder="HH o HH:MM"),
            FiltroDefinicion("fecha_inicio", "Fecha de inicio grupo/ficha", "date"),
            FiltroDefinicion("fecha_fin", "Fecha fin grupo/ficha", "date"),
        ],
    )
)
