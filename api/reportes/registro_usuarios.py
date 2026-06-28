from api.reportes.registry import (
    FiltroDefinicion, ReporteDefinicion, registrar,
    OPC_ESTADO_GRUPO, OPC_NIVELES, OPC_MODALIDADES, OPC_ROLES, OPC_ORIGEN_DATOS,
)

_ESTADO_APRENDIZ = [
    {"value": "",           "label": "Todas"},
    {"value": "Activa",     "label": "Activo"},
    {"value": "Suspendida", "label": "Suspendido"},
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
            FiltroDefinicion("nivel",           "Tipo de programa",               "select", opciones=OPC_NIVELES),
            FiltroDefinicion("modalidad",        "Modalidad",                        "select", opciones=OPC_MODALIDADES),
            FiltroDefinicion("regional",         "Regional",                         "text",   placeholder="Todas"),
            FiltroDefinicion("centro_formacion", "Centro de Formación",              "text",   placeholder="Todas"),
            FiltroDefinicion("estado_grupo",     "Estado del grupo/ficha",           "select", opciones=OPC_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario",      "Rol de usuario",                   "select", opciones=OPC_ROLES),
            FiltroDefinicion("estado_aprendiz",  "Estado del aprendiz (SOFIA Plus)", "select", opciones=_ESTADO_APRENDIZ),
            FiltroDefinicion("origen_datos",     "Origen de datos",                  "select", opciones=OPC_ORIGEN_DATOS),
            FiltroDefinicion("codigo_ficha",     "Código grupo/ficha",               "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_ficha",     "Nombre grupo/ficha en el LMS",     "text",   placeholder="Todas"),
            FiltroDefinicion("identificacion",   "Identificación",                   "text",   placeholder="Todas"),
            FiltroDefinicion("nombres_apellidos","Nombres y apellidos",              "text",   placeholder="Todas"),
            FiltroDefinicion("fecha_inicio",     "Fecha de inicio grupo/ficha",      "date"),
            FiltroDefinicion("fecha_fin",        "Fecha fin grupo/ficha",            "date"),
            FiltroDefinicion("hora",             "Hora",                             "text",   placeholder="HH o HH:MM"),
        ],
    )
)
