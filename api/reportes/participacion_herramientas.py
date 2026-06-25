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

_ESTADO_USUARIO = [
    {"value": "", "label": "Todas"},
    {"value": "Activo", "label": "Activo"},
    {"value": "Suspendido", "label": "Suspendido"},
    {"value": "Eliminado", "label": "Eliminado"},
]

_ESTADO_APRENDIZ = [
    {"value": "", "label": "Todas"},
    {"value": "No disponible (SOFIA Plus)", "label": "No disponible (SOFIA Plus)"},
]

_ORIGEN_DATOS = [
    {"value": "", "label": "Todas"},
    {"value": "Integración", "label": "Integración"},
    {"value": "Manual", "label": "Manual"},
]

registrar(
    ReporteDefinicion(
        codigo="participacion_herramientas",
        nombre="Participación por Herramientas",
        descripcion=(
            "Por usuario/grupo: ingresos y participaciones en wikis, encuestas, "
            "foros, evaluaciones, blogs, evidencias, SCORM, sesiones, chats y anuncios."
        ),
        filtros=[
            FiltroDefinicion("nivel", "Nivel de Formación", "select", opciones=_NIVELES),
            FiltroDefinicion("modalidad", "Modalidad", "select", opciones=_MODALIDADES),
            FiltroDefinicion("regional", "Regional", "text", placeholder="Todas"),
            FiltroDefinicion("centro_formacion", "Centro de Formación", "text", placeholder="Todas"),
            FiltroDefinicion("estado_grupo", "Estado del grupo/ficha", "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario", "Rol de usuario", "select", opciones=_ROLES),
            FiltroDefinicion("estado_usuario", "Estado del usuario", "select", opciones=_ESTADO_USUARIO),
            FiltroDefinicion("estado_aprendiz", "Estado del aprendiz (SOFIA Plus)", "select", opciones=_ESTADO_APRENDIZ),
            FiltroDefinicion("codigo_programa", "Código programa", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_programa", "Nombre de programa", "text", placeholder="Todas"),
            FiltroDefinicion("origen_datos", "Origen de datos", "select", opciones=_ORIGEN_DATOS),
            FiltroDefinicion("identificacion", "Identificación", "text", placeholder="Todas"),
            FiltroDefinicion("nombres_apellidos", "Nombres y apellidos", "text", placeholder="Todas"),
            FiltroDefinicion("fecha_desde", "Rango de fecha de consulta desde", "date"),
            FiltroDefinicion("fecha_hasta", "Rango de fecha de consulta hasta", "date"),
            FiltroDefinicion("codigo_ficha", "Código grupo", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_ficha", "Nombre grupo en el LMS", "text", placeholder="Todas"),
            FiltroDefinicion("fecha_inicio", "Fecha de inicio de grupo", "date"),
            FiltroDefinicion("fecha_fin", "Fecha fin de grupo", "date"),
        ],
    )
)
