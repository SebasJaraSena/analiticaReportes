from api.reportes.registry import (
    FiltroDefinicion, ReporteDefinicion, registrar,
    OPC_ESTADO_GRUPO, OPC_NIVELES, OPC_MODALIDADES, OPC_ROLES, OPC_ORIGEN_DATOS,
)

_ESTADO_APRENDIZ = [
    {"value": "",         "label": "Todas"},
    {"value": "Activo",   "label": "Activo"},
    {"value": "Inactivo", "label": "Inactivo"},
]

registrar(
    ReporteDefinicion(
        codigo="fichas_programas",
        nombre="Fichas y Programas de Formación",
        descripcion=(
            "Listado de grupos/fichas con programa, nivel, modalidad, regional, "
            "centro y conteo de instructores/aprendices activos e inactivos."
        ),
        filtros=[
            FiltroDefinicion("nivel",              "Tipo de programa",               "select", opciones=OPC_NIVELES),
            FiltroDefinicion("modalidad",           "Modalidad",                        "select", opciones=OPC_MODALIDADES),
            FiltroDefinicion("regional",            "Regional",                         "text",   placeholder="Todas"),
            FiltroDefinicion("centro_formacion",    "Centro de Formación",              "text",   placeholder="Todas"),
            FiltroDefinicion("estado_grupo_sofia",  "Estado grupo/ficha SOFIA Plus",    "select", opciones=[
                {"value": "",                          "label": "Todas"},
                {"value": "No disponible (SOFIA Plus)","label": "No disponible (SOFIA Plus)"},
            ]),
            FiltroDefinicion("rol_usuario",         "Rol de usuario",                   "select", opciones=OPC_ROLES),
            FiltroDefinicion("estado_aprendiz",     "Estado del aprendiz (SOFIA Plus)", "select", opciones=_ESTADO_APRENDIZ),
            FiltroDefinicion("origen_datos",        "Origen de datos",                  "select", opciones=OPC_ORIGEN_DATOS),
            FiltroDefinicion("codigo_programa",     "Código programa",                  "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_programa",     "Nombre de programa",               "text",   placeholder="Todas"),
            FiltroDefinicion("hora_creacion",       "Hora creación curso LMS",          "text",   placeholder="HH o HH:MM"),
            FiltroDefinicion("fecha_desde",         "Rango fecha creación curso desde", "date"),
            FiltroDefinicion("fecha_hasta",         "Rango fecha creación curso hasta", "date"),
            FiltroDefinicion("codigo_ficha",        "Código grupo",                     "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_ficha",        "Nombre grupo en el LMS",           "text",   placeholder="Todas"),
            FiltroDefinicion("hora_grupo",          "Hora grupo/ficha",                 "text",   placeholder="HH o HH:MM"),
            FiltroDefinicion("fecha_inicio",        "Fecha de inicio grupo/ficha",      "date"),
            FiltroDefinicion("fecha_fin",           "Fecha fin grupo/ficha",            "date"),
        ],
    )
)
