from api.reportes.registry import (
    FiltroDefinicion, ReporteDefinicion, registrar,
    OPC_ESTADO_GRUPO, OPC_NIVELES, OPC_MODALIDADES, OPC_ROLES, OPC_ORIGEN_DATOS,
)

registrar(
    ReporteDefinicion(
        codigo="matriculas_lms",
        nombre="Matrículas LMS",
        descripcion=(
            "Matrículas con nivel, modalidad, programa, regional, centro, "
            "tipo de documento, estado y fechas de enrolamiento."
        ),
        filtros=[
            FiltroDefinicion("nivel",           "Tipo de programa",           "select", opciones=OPC_NIVELES),
            FiltroDefinicion("modalidad",        "Modalidad",                    "select", opciones=OPC_MODALIDADES),
            FiltroDefinicion("regional",         "Regional",                     "text",   placeholder="Todas"),
            FiltroDefinicion("origen_datos",     "Origen de datos",              "select", opciones=OPC_ORIGEN_DATOS),
            FiltroDefinicion("estado_grupo",     "Estado del grupo/ficha",       "select", opciones=OPC_ESTADO_GRUPO),
            FiltroDefinicion("rol_usuario",      "Rol de usuario",               "select", opciones=OPC_ROLES),
            FiltroDefinicion("centro_formacion", "Centro de Formación",          "text",   placeholder="Todas"),
            FiltroDefinicion("fecha_desde",      "Rango de fecha desde",         "date"),
            FiltroDefinicion("fecha_hasta",      "Rango de fecha hasta",         "date"),
            FiltroDefinicion("codigo_ficha",     "Código grupo/ficha",           "text",   placeholder="Todas"),
            FiltroDefinicion("nombre_ficha",     "Nombre grupo/ficha en el LMS", "text",   placeholder="Todas"),
            FiltroDefinicion("fecha_inicio",     "Fecha de inicio grupo/ficha",  "date"),
            FiltroDefinicion("fecha_fin",        "Fecha fin grupo/ficha",        "date"),
        ],
    )
)
