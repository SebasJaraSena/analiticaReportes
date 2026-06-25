from api.reportes.registry import (
    FiltroDefinicion, ReporteDefinicion, registrar,
    OPC_ESTADO_GRUPO, OPC_NIVELES, OPC_MODALIDADES, OPC_ROLES, OPC_ORIGEN_DATOS,
    OPC_ESTADO_USUARIO,
)

_ESTADO_APRENDIZ = [
    {"value": "",                          "label": "Todas"},
    {"value": "No disponible (SOFIA Plus)","label": "No disponible (SOFIA Plus)"},
]

registrar(
    ReporteDefinicion(
        codigo="tiempo_permanencia",
        nombre="Tiempo de Permanencia por Herramientas",
        descripcion=(
            "Tiempo estimado y porcentaje por usuario, grupo/ficha y herramienta. "
            "Saltos superiores a 30 minutos se truncan a 30 minutos."
        ),
        filtros=[
            FiltroDefinicion("nivel",            "Nivel de Formación",               "select", opciones=OPC_NIVELES),
            FiltroDefinicion("modalidad",         "Modalidad",                        "select", opciones=OPC_MODALIDADES),
            FiltroDefinicion("regional",          "Regional",                         "text",   placeholder="Todas"),
            FiltroDefinicion("centro_formacion",  "Centro de Formación",              "text",   placeholder="Todas"),
            FiltroDefinicion("estado_grupo",      "Estado del grupo/ficha",           "select", opciones=OPC_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario",       "Rol de usuario",                   "select", opciones=OPC_ROLES),
            FiltroDefinicion("estado_usuario",    "Estado del usuario",               "select", opciones=OPC_ESTADO_USUARIO),
            FiltroDefinicion("estado_aprendiz",   "Estado del aprendiz (SOFIA Plus)", "select", opciones=_ESTADO_APRENDIZ),
            FiltroDefinicion("codigo_programa",   "Código programa",                  "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_programa",   "Nombre de programa",               "text",   placeholder="Todas"),
            FiltroDefinicion("origen_datos",      "Origen de datos",                  "select", opciones=OPC_ORIGEN_DATOS),
            FiltroDefinicion("identificacion",    "Identificación",                   "text",   placeholder="Todas"),
            FiltroDefinicion("nombres_apellidos", "Nombres y apellidos",              "text",   placeholder="Todas"),
            FiltroDefinicion("fecha_desde",       "Rango de fecha de consulta desde", "date"),
            FiltroDefinicion("fecha_hasta",       "Rango de fecha de consulta hasta", "date"),
            FiltroDefinicion("codigo_ficha",      "Código grupo",                     "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_ficha",      "Nombre grupo en el LMS",           "text",   placeholder="Todas"),
            FiltroDefinicion("fecha_inicio",      "Fecha de inicio de grupo",         "date"),
            FiltroDefinicion("fecha_fin",         "Fecha fin de grupo",               "date"),
        ],
    )
)
