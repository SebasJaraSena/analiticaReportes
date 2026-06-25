-- Reporte 1.6: Tráfico diario de usuarios.
-- Contiene la información de usuarios registrados y vinculados a grupos.
-- El origen del grupo se identifica como Integración/SOFIA Plus o Manual.
-- Permite filtrar por fecha, origen de datos y rango de consulta: Día, Mes o Año.
-- El conteo corresponde a la suma de ingresos únicos por usuario por día.
-- Fecha mínima de consulta: inicio de ZAJUNA, abril de 2024.

WITH parametros_entrada AS (
    SELECT
        NULLIF(%(fecha_desde)s::text, '')::date AS fecha_desde,
        NULLIF(%(fecha_hasta)s::text, '')::date AS fecha_hasta,
        NULLIF(%(origen_datos)s::text, '')      AS origen_raw,
        NULLIF(%(rango_consulta)s::text, '')    AS rango_raw
),

parametros AS (
    SELECT
        pe.fecha_desde,
        pe.fecha_hasta,

        CASE
            WHEN pe.origen_raw IS NULL
              OR LOWER(pe.origen_raw) IN ('todas', 'todos')
            THEN NULL

            WHEN LOWER(pe.origen_raw) IN (
                'integración',
                'integracion',
                'sofia plus',
                'sofía plus'
            )
            THEN 'Integración'

            WHEN LOWER(pe.origen_raw) = 'manual'
            THEN 'Manual'

            ELSE pe.origen_raw
        END AS origen_datos,

        CASE
            WHEN LOWER(COALESCE(pe.rango_raw, 'Día')) IN ('día', 'dia')
            THEN 'Día'

            WHEN LOWER(COALESCE(pe.rango_raw, 'Día')) = 'mes'
            THEN 'Mes'

            WHEN LOWER(COALESCE(pe.rango_raw, 'Día')) IN ('año', 'ano')
            THEN 'Año'

            ELSE 'Día'
        END AS rango_consulta,

        EXTRACT(
            EPOCH FROM (
                TIMESTAMP '2024-04-01 00:00:00'
                AT TIME ZONE 'America/Bogota'
            )
        )::bigint AS inicio_zajuna_epoch

    FROM parametros_entrada pe
),

cursos_origen AS (
    SELECT
        c.id AS courseid,
        c.shortname,

        CASE
            WHEN (
                c.shortname ~ '^P_[0-9]+_'
                OR c.shortname ~ '^[0-9]+P_[0-9]+_'
            )
            THEN 'Integración'
            ELSE 'Manual'
        END AS origen_datos

    FROM public.mdl_course c
    WHERE c.id <> 1
),

logs_base AS (
    SELECT
        'Producción' AS ambiente,

        co.origen_datos,

        (
            TO_TIMESTAMP(l.timecreated)
            AT TIME ZONE 'America/Bogota'
        )::date AS fecha_evento,

        l.userid,
        l.courseid,
        l.timecreated

    FROM public.mdl_logstore_standard_log l

    JOIN public.mdl_user u
        ON u.id = l.userid

    JOIN cursos_origen co
        ON co.courseid = l.courseid

    CROSS JOIN parametros p

    WHERE l.userid > 0
      AND u.deleted = 0
      AND COALESCE(u.suspended, 0) = 0

      -- Accesos/visualizaciones asociados al grupo en el LMS
      AND l.action = 'viewed'

      -- Desde inicio de ZAJUNA: abril de 2024
      AND l.timecreated >= p.inicio_zajuna_epoch

      -- Filtro fecha desde
      AND (
            p.fecha_desde IS NULL
            OR l.timecreated >= EXTRACT(
                EPOCH FROM (
                    p.fecha_desde::timestamp
                    AT TIME ZONE 'America/Bogota'
                )
            )::bigint
          )

      -- Filtro fecha hasta, incluye todo el día seleccionado
      AND (
            p.fecha_hasta IS NULL
            OR l.timecreated < EXTRACT(
                EPOCH FROM (
                    (p.fecha_hasta + INTERVAL '1 day')::timestamp
                    AT TIME ZONE 'America/Bogota'
                )
            )::bigint
          )

      -- Filtro origen de datos: Todas, Integración/SOFIA Plus o Manual
      AND (
            p.origen_datos IS NULL
            OR co.origen_datos = p.origen_datos
          )

      -- Usuario vinculado al grupo en el momento del acceso
      AND EXISTS (
            SELECT 1
            FROM public.mdl_enrol en
            JOIN public.mdl_user_enrolments ue
                ON ue.enrolid = en.id
            WHERE en.courseid = l.courseid
              AND ue.userid = l.userid
              AND en.status = 0
              AND ue.status = 0
              AND (
                    ue.timestart IS NULL
                    OR ue.timestart = 0
                    OR ue.timestart <= l.timecreated
                  )
              AND (
                    ue.timeend IS NULL
                    OR ue.timeend = 0
                    OR ue.timeend >= l.timecreated
                  )
          )
),

usuarios_unicos_dia AS (
    SELECT DISTINCT
        ambiente,
        origen_datos,
        fecha_evento,
        userid
    FROM logs_base
),

periodizado AS (
    SELECT
        uud.ambiente,
        uud.origen_datos,
        p.rango_consulta,

        CASE
            WHEN p.rango_consulta = 'Año'
            THEN DATE_TRUNC('year', uud.fecha_evento)::date

            WHEN p.rango_consulta = 'Mes'
            THEN DATE_TRUNC('month', uud.fecha_evento)::date

            ELSE uud.fecha_evento
        END AS periodo,

        uud.fecha_evento,
        uud.userid

    FROM usuarios_unicos_dia uud
    CROSS JOIN parametros p
)

SELECT
    ambiente AS "Ambiente",

    origen_datos AS "Origen de Datos",

    rango_consulta AS "Rango de Consulta",

    EXTRACT(YEAR FROM periodo)::int AS "Año",

    CASE
        WHEN rango_consulta IN ('Mes', 'Día')
        THEN EXTRACT(MONTH FROM periodo)::int
        ELSE NULL
    END AS "Mes",

    CASE
        WHEN rango_consulta = 'Día'
        THEN EXTRACT(DAY FROM periodo)::int
        ELSE NULL
    END AS "Día",

    CASE
        WHEN rango_consulta = 'Día'
        THEN TO_CHAR(periodo, 'YYYY/MM/DD')

        WHEN rango_consulta = 'Mes'
        THEN TO_CHAR(periodo, 'YYYY/MM')

        WHEN rango_consulta = 'Año'
        THEN TO_CHAR(periodo, 'YYYY')
    END AS "Periodo",

    COUNT(*) AS "Cantidad de Usuarios Únicos"

FROM periodizado

GROUP BY
    ambiente,
    origen_datos,
    rango_consulta,
    periodo

ORDER BY
    periodo DESC,
    ambiente,
    origen_datos