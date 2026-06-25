from api.reportes.registry import FiltroDefinicion, ReporteDefinicion, registrar

registrar(
    ReporteDefinicion(
        codigo="registro_usuarios",
        nombre="Registro de Usuarios",
        descripcion=(
            "Listado completo de usuarios matriculados en grupos/fichas del LMS, "
            "con información de rol, fechas de acceso y días de ingreso."
        ),
        filtros=[
            FiltroDefinicion("codigo_ficha", "Código de Ficha/Grupo", "text",
                             placeholder="Ej: 2750123"),
            FiltroDefinicion("nombre_ficha", "Nombre de Ficha/Grupo", "text",
                             placeholder="Búsqueda parcial"),
            FiltroDefinicion("identificacion", "Número de Identificación", "text"),
            FiltroDefinicion("nombres_apellidos", "Nombres y Apellidos", "text",
                             placeholder="Búsqueda parcial"),
            FiltroDefinicion("nivel", "Nivel", "select", opciones=[
                {"value": "", "label": "Todos"},
                {"value": "Formación titulada", "label": "Formación titulada"},
                {"value": "No definido", "label": "No definido"},
            ]),
            FiltroDefinicion("modalidad", "Modalidad", "select", opciones=[
                {"value": "", "label": "Todas"},
                {"value": "presencial", "label": "Presencial"},
                {"value": "virtual", "label": "Virtual"},
                {"value": "distancia", "label": "A Distancia"},
            ]),
            FiltroDefinicion("regional", "Regional", "text"),
            FiltroDefinicion("centro_formacion", "Centro de Formación", "text"),
            FiltroDefinicion("estado_grupo", "Estado del Grupo", "select", opciones=[
                {"value": "En ejecución", "label": "En ejecución"},
                {"value": "Finalizado",   "label": "Finalizado"},
                {"value": "No iniciado",  "label": "No iniciado"},
                {"value": "Oculto",       "label": "Oculto"},
            ]),
            FiltroDefinicion("rol_usuario", "Rol del Usuario", "text",
                             placeholder="Ej: student, teacher"),
            FiltroDefinicion("fecha_inicio_desde", "Inicio Grupo Desde", "date"),
            FiltroDefinicion("fecha_inicio_hasta", "Inicio Grupo Hasta", "date"),
            FiltroDefinicion("fecha_fin_desde",   "Fin Grupo Desde",    "date"),
            FiltroDefinicion("fecha_fin_hasta",   "Fin Grupo Hasta",    "date"),
            FiltroDefinicion("fecha_consulta_desde", "Ingresos Desde", "date"),
            FiltroDefinicion("fecha_consulta_hasta", "Ingresos Hasta", "date"),
        ],
    )
)
