from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

_ESTADO_GRUPO = [
    {"value": "", "label": "Todas"},
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado", "label": "Finalizado"},
    {"value": "No iniciado", "label": "No iniciado"},
    {"value": "Oculto", "label": "Oculto"},
]

_NIVELES = [
    {"value": "", "label": "Todas"},
    {"value": "Formación titulada", "label": "Formación titulada"},
    {"value": "No definido", "label": "No definido"},
]

_MODALIDADES = [
    {"value": "", "label": "Todas"},
    {"value": "Titulada virtual", "label": "Titulada virtual"},
    {"value": "Titulada presencial", "label": "Titulada presencial"},
    {"value": "Titulada a distancia", "label": "Titulada a distancia"},
]

_ROLES = [
    {"value": "", "label": "Todas"},
    {"value": "student", "label": "Aprendiz"},
    {"value": "teacher", "label": "Instructor"},
    {"value": "editingteacher", "label": "Instructor editor"},
]

_ORIGEN_DATOS = [
    {"value": "", "label": "Todas"},
    {"value": "Integración", "label": "Integración"},
    {"value": "Manual", "label": "Manual"},
]

registrar(
    ReporteDefinicion(
        codigo="sesiones_online",
        nombre="Sesiones en Línea / VideoConferencia",
        descripcion=(
            "Sesiones BigBlueButton por grupo/ficha: ingresos, fechas, "
            "estado de inicio y grabación."
        ),
        filtros=[
            FiltroDefinicion("nivel", "Nivel de Formación", "select", opciones=_NIVELES),
            FiltroDefinicion("modalidad", "Modalidad", "select", opciones=_MODALIDADES),
            FiltroDefinicion("regional", "Regional", "text", placeholder="Todas"),
            FiltroDefinicion("centro_formacion", "Centro de Formación", "text", placeholder="Todas"),
            FiltroDefinicion("estado_grupo", "Estado del grupo/ficha", "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario", "Rol de usuario", "select", opciones=_ROLES),
            FiltroDefinicion("origen_datos", "Origen de datos", "select", opciones=_ORIGEN_DATOS),
            FiltroDefinicion("fecha_desde", "Rango Fecha de inicio de Sesión desde", "date"),
            FiltroDefinicion("fecha_hasta", "Rango Fecha de inicio de Sesión hasta", "date"),
            FiltroDefinicion("codigo_programa", "Código programa", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_programa", "Nombre de programa", "text", placeholder="Todas"),
            FiltroDefinicion("codigo_ficha", "Código grupo", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_ficha", "Nombre grupo en el LMS", "text", placeholder="Todas"),
            FiltroDefinicion("identificacion", "Identificación", "text", placeholder="Todas"),
            FiltroDefinicion("nombres_apellidos", "Nombres y apellidos", "text", placeholder="Todas"),
            FiltroDefinicion("fecha_inicio_grupo_desde", "Rango Fecha de inicio de grupo/ficha desde", "date"),
            FiltroDefinicion("fecha_inicio_grupo_hasta", "Rango Fecha de inicio de grupo/ficha hasta", "date"),
            FiltroDefinicion("fecha_creacion_grupo_desde", "Rango Fecha de creación de grupo/ficha desde", "date"),
            FiltroDefinicion("fecha_creacion_grupo_hasta", "Rango Fecha de creación de grupo/ficha hasta", "date"),
        ],
    )
)
