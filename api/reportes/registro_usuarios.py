from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

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

_ESTADO_GRUPO = [
    {"value": "", "label": "Todas"},
    {"value": "En ejecución", "label": "En ejecución"},
    {"value": "Finalizado", "label": "Finalizado"},
    {"value": "No iniciado", "label": "No iniciado"},
    {"value": "Oculto", "label": "Oculto"},
]

_ROLES = [
    {"value": "", "label": "Todas"},
    {"value": "student", "label": "Aprendiz"},
    {"value": "teacher", "label": "Instructor"},
    {"value": "editingteacher", "label": "Instructor editor"},
]

_ESTADO_APRENDIZ = [
    {"value": "", "label": "Todas"},
    {"value": "Activa", "label": "Activo"},
    {"value": "Suspendida", "label": "Suspendido"},
]

_ORIGEN_DATOS = [
    {"value": "", "label": "Todas"},
    {"value": "Integración", "label": "Integración"},
    {"value": "Manual", "label": "Manual"},
]

registrar(
    ReporteDefinicion(
        codigo="registro_usuarios",
        nombre="Registro de Usuarios",
        descripcion=(
            "Listado completo de usuarios matriculados en grupos/fichas del LMS, "
            "con información de rol, fechas de acceso y días de ingreso."
        ),
        filtros=[
            FiltroDefinicion("nivel", "Nivel del programa", "select", opciones=_NIVELES),
            FiltroDefinicion("modalidad", "Modalidad", "select", opciones=_MODALIDADES),
            FiltroDefinicion("regional", "Regional", "text", placeholder="Todas"),
            FiltroDefinicion("centro_formacion", "Centro de Formación", "text", placeholder="Todas"),
            FiltroDefinicion("estado_grupo", "Estado del grupo/ficha", "select", opciones=_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario", "Rol de usuario", "select", opciones=_ROLES),
            FiltroDefinicion("estado_aprendiz", "Estado del aprendiz (SOFIA Plus)", "select", opciones=_ESTADO_APRENDIZ),
            FiltroDefinicion("origen_datos", "Origen de datos", "select", opciones=_ORIGEN_DATOS),
            FiltroDefinicion("codigo_ficha", "Código grupo/ficha", "text", placeholder="Todas"),
            FiltroDefinicion("nombre_ficha", "Nombre grupo/ficha en el LMS", "text", placeholder="Todas"),
            FiltroDefinicion("identificacion", "Identificación", "text", placeholder="Todas"),
            FiltroDefinicion("nombres_apellidos", "Nombres y apellidos", "text", placeholder="Todas"),
            FiltroDefinicion("fecha_inicio", "Fecha de inicio grupo/ficha", "date"),
            FiltroDefinicion("fecha_fin", "Fecha fin grupo/ficha", "date"),
            FiltroDefinicion("hora", "Hora", "text", placeholder="HH o HH:MM"),
        ],
    )
)
