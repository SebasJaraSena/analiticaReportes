from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "", "label": "Todas"},
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado",   "label": "Finalizado"},
    {"value": "No iniciado",  "label": "No iniciado"},
    {"value": "Oculto",       "label": "Oculto"},
]
_ROLES = [
    {"value": "", "label": "Todas"},
    {"value": "student",        "label": "Aprendiz"},
    {"value": "teacher",        "label": "Instructor"},
    {"value": "editingteacher", "label": "Instructor Editor"},
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

_ORIGEN_DATOS = [
    {"value": "", "label": "Todas"},
    {"value": "Integración", "label": "Integración"},
    {"value": "Manual", "label": "Manual"},
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
            FiltroDefinicion("nivel", "Nivel del programa", "select", opciones=_NIVELES),
            FiltroDefinicion("modalidad", "Modalidad", "select", opciones=_MODALIDADES),
            FiltroDefinicion("regional", "Regional", "text", placeholder="Todas"),
            FiltroDefinicion("origen_datos", "Origen de datos", "select", opciones=_ORIGEN_DATOS),
            FiltroDefinicion("estado_grupo", "Estado del grupo/ficha", "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario", "Rol de usuario", "select", opciones=_ROLES),
            FiltroDefinicion("centro_formacion", "Centro de Formación", "text", placeholder="Todas"),
            FiltroDefinicion("fecha_desde", "Rango de fecha de consulta desde", "date"),
            FiltroDefinicion("fecha_hasta", "Rango de fecha de consulta hasta", "date"),
            FiltroDefinicion("codigo_ficha", "Código grupo/ficha", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_ficha", "Nombre grupo/ficha en el LMS", "text", placeholder="Todas"),
            FiltroDefinicion("fecha_inicio", "Fecha de inicio grupo/ficha", "date"),
            FiltroDefinicion("fecha_fin", "Fecha fin grupo/ficha", "date"),
        ],
    )
)
