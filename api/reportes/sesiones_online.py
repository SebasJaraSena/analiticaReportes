from api.reportes.registry import (
    FiltroDefinicion, ReporteDefinicion, registrar,
    OPC_ESTADO_GRUPO, OPC_NIVELES, OPC_MODALIDADES, OPC_ROLES, OPC_ORIGEN_DATOS,
)

registrar(
    ReporteDefinicion(
        codigo="sesiones_online",
        nombre="Sesiones en Línea / VideoConferencia",
        descripcion=(
            "Sesiones BigBlueButton por grupo/ficha: ingresos, fechas, "
            "estado de inicio y grabación."
        ),
        filtros=[
            FiltroDefinicion("nivel",                     "Nivel de Formación",                          "select", opciones=OPC_NIVELES),
            FiltroDefinicion("modalidad",                  "Modalidad",                                   "select", opciones=OPC_MODALIDADES),
            FiltroDefinicion("regional",                   "Regional",                                    "text",   placeholder="Todas"),
            FiltroDefinicion("centro_formacion",           "Centro de Formación",                         "text",   placeholder="Todas"),
            FiltroDefinicion("estado_grupo",               "Estado del grupo/ficha",                      "select", opciones=OPC_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario",                "Rol de usuario",                              "select", opciones=OPC_ROLES),
            FiltroDefinicion("origen_datos",               "Origen de datos",                             "select", opciones=OPC_ORIGEN_DATOS),
            FiltroDefinicion("fecha_desde",                "Rango Fecha inicio de Sesión desde",          "date"),
            FiltroDefinicion("fecha_hasta",                "Rango Fecha inicio de Sesión hasta",          "date"),
            FiltroDefinicion("codigo_programa",            "Código programa",                             "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_programa",            "Nombre de programa",                          "text",   placeholder="Todas"),
            FiltroDefinicion("codigo_ficha",               "Código grupo",                                "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_ficha",               "Nombre grupo en el LMS",                     "text",   placeholder="Todas"),
            FiltroDefinicion("identificacion",             "Identificación",                              "text",   placeholder="Todas"),
            FiltroDefinicion("nombres_apellidos",          "Nombres y apellidos",                         "text",   placeholder="Todas"),
            FiltroDefinicion("fecha_inicio_grupo_desde",   "Rango Fecha inicio de grupo/ficha desde",     "date"),
            FiltroDefinicion("fecha_inicio_grupo_hasta",   "Rango Fecha inicio de grupo/ficha hasta",     "date"),
            FiltroDefinicion("fecha_creacion_grupo_desde", "Rango Fecha creación de grupo/ficha desde",   "date"),
            FiltroDefinicion("fecha_creacion_grupo_hasta", "Rango Fecha creación de grupo/ficha hasta",   "date"),
        ],
    )
)
