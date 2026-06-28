-- Reporte 1.7: Herramientas LMS.
-- Una fila por grupo/ficha con conteos pivotados por herramienta.
-- Programa/código desde fullname, modalidad desde shortname, regional/centro desde midb.
-- Si el usuario no diligencia filtros, se muestra la totalidad de la información.

WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber,
        c.shortname,
        c.fullname,
        c.category,
        c.visible,
        c.startdate,
        c.enddate,

        SUBSTRING(
            c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$'
        ) AS codigo_programa,

        TRIM(
            REGEXP_REPLACE(
                c.fullname,
                '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$',
                ''
            )
        ) AS programa_formacion,

        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS codigo_centro,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_([A-Za-z]+)_') AS letra_modalidad,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_[A-Za-z]+_([0-9]+)') AS version_extraida,

        -- Tipo de programa según la categoría raíz del curso
        CASE
            WHEN rc.name ILIKE '%%complementaria%%' THEN 'Complementaria'
            WHEN rc.name ILIKE '%%titulada%%' OR rc.name ILIKE '%%presencial%%' THEN 'Titulada'
            ELSE 'No definido'
        END AS tipo_programa

    FROM public.mdl_course c
    LEFT JOIN public.mdl_course_categories cc ON cc.id = c.category
    LEFT JOIN public.mdl_course_categories rc
           ON rc.id = NULLIF(split_part(cc.path, '/', 2), '')::int
    WHERE c.id <> 1
),

actividad AS (
    SELECT
        cp.courseid,

        CASE
            WHEN m.name = 'wiki' THEN 'wiki'
            WHEN m.name IN ('feedback', 'survey') THEN 'encuesta'
            WHEN m.name = 'quiz' THEN 'evaluacion'
            WHEN m.name = 'assign' THEN 'evidencia'
            WHEN m.name = 'forum' AND f.type = 'blog' THEN 'blog'
            WHEN m.name = 'forum' AND f.type = 'news' THEN 'anuncio'
            WHEN m.name = 'forum' THEN 'foro'
            WHEN m.name = 'scorm' THEN 'scorm'
            WHEN m.name = 'bigbluebuttonbn' THEN 'sesion'
            WHEN m.name = 'chat' THEN 'chat'
            ELSE m.name
        END AS herramienta,

        cm.id AS coursemoduleid,

        CASE
            WHEN u.id IS NOT NULL
             AND EXISTS (
                    SELECT 1
                    FROM public.mdl_enrol en
                    JOIN public.mdl_user_enrolments ue
                        ON ue.enrolid = en.id
                    WHERE en.courseid = cp.courseid
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
            THEN l.userid
            ELSE NULL
        END AS userid_valido

    FROM curso_parseado cp

    JOIN public.mdl_course_modules cm
        ON cm.course = cp.courseid

    JOIN public.mdl_modules m
        ON m.id = cm.module

    LEFT JOIN public.mdl_forum f
        ON f.id = cm.instance
       AND m.name = 'forum'

    LEFT JOIN public.mdl_logstore_standard_log l
        ON l.courseid = cp.courseid
       AND l.contextinstanceid = cm.id
       AND l.contextlevel = 70
       AND l.userid > 0
       AND (
            %(fecha_desde)s IS NULL
            OR l.timecreated >= EXTRACT(
                EPOCH FROM (
                    %(fecha_desde)s::date::timestamp
                    AT TIME ZONE 'America/Bogota'
                )
            )::bigint
       )
       AND (
            %(fecha_hasta)s IS NULL
            OR l.timecreated < EXTRACT(
                EPOCH FROM (
                    (%(fecha_hasta)s::date + INTERVAL '1 day')::timestamp
                    AT TIME ZONE 'America/Bogota'
                )
            )::bigint
       )
       AND (
            %(hora_consulta)s IS NULL
            OR TO_CHAR(
                TO_TIMESTAMP(l.timecreated) AT TIME ZONE 'America/Bogota',
                'HH24'
            ) = LPAD(SPLIT_PART(%(hora_consulta)s::text, ':', 1), 2, '0')
       )

    LEFT JOIN public.mdl_user u
        ON u.id = l.userid
       AND u.deleted = 0
       AND COALESCE(u.suspended, 0) = 0

    WHERE COALESCE(cm.deletioninprogress, 0) = 0
)

SELECT
    COALESCE(cp.codigo_programa, 'No definido') AS "Código del programa",

    COALESCE(cp.version_extraida, 'No definido') AS "Versión programa",

    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname) AS "Nombre del programa de formación",

    cp.tipo_programa AS "Tipo de programa",

    CASE
        WHEN cp.letra_modalidad = 'V' THEN 'Virtual'
        WHEN cp.letra_modalidad = 'A' THEN 'A distancia'
        WHEN cp.letra_modalidad IN ('P', 'PI') THEN 'Presencial'
        ELSE 'No definido'
    END AS "Modalidad",

    cp.idnumber AS "Código de grupo/ficha",

    cp.fullname AS "Nombre grupo/ficha",

    CASE
        WHEN cp.startdate IS NULL OR cp.startdate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha de inicio del grupo/ficha",

    CASE
        WHEN cp.enddate IS NULL OR cp.enddate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(cp.enddate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha fin del grupo/ficha",

    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0
             AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado grupo/ficha",

    CASE
        WHEN (
            cp.shortname ~ '^P_[0-9]+_'
            OR cp.shortname ~ '^[0-9]+P_[0-9]+_'
        )
        THEN 'Integración'
        ELSE 'Manual'
    END AS "Origen de Datos",

    COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, 'No definido') AS "Regional",

    COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, 'No definido') AS "Centro de Formación",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'wiki'
    ) AS "Número usuarios con participación en wikis",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'wiki'
    ) AS "Cantidad de wikis",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'encuesta'
    ) AS "Número usuarios con participación en encuestas",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'encuesta'
    ) AS "Cantidad de encuestas",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'evaluacion'
    ) AS "Número usuarios con participación en Evaluaciones",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'evaluacion'
    ) AS "Cantidad de Evaluaciones",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'evidencia'
    ) AS "Número usuarios con participación en evidencias",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'evidencia'
    ) AS "Cantidad de evidencias",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'blog'
    ) AS "Número usuarios con participación en blogs",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'blog'
    ) AS "Cantidad de blogs",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'anuncio'
    ) AS "Número usuarios con participación en anuncios",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'anuncio'
    ) AS "Cantidad de anuncios",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'foro'
    ) AS "Número usuarios con participación en foros temáticos",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'foro'
    ) AS "Cantidad de foros temáticos",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'scorm'
    ) AS "Número usuarios con participación en scorm",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'scorm'
    ) AS "Cantidad de scorm",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'sesion'
    ) AS "Número de usuarios con participación sesiones en línea",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'sesion'
    ) AS "Cantidad de sesiones en línea",

    COUNT(DISTINCT a.userid_valido) FILTER (
        WHERE a.herramienta = 'chat'
    ) AS "Número de usuarios con participación en chats",

    COUNT(DISTINCT a.coursemoduleid) FILTER (
        WHERE a.herramienta = 'chat'
    ) AS "Cantidad de chats",

    0 AS "Número de usuarios con participación en notificaciones",

    0 AS "Cantidad de notificaciones"

FROM curso_parseado cp

LEFT JOIN midb.regionales reg
    ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint

LEFT JOIN midb.centros cen
    ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint

LEFT JOIN actividad a
    ON a.courseid = cp.courseid

WHERE (
        %(codigo_ficha)s IS NULL
        OR cp.idnumber ILIKE '%%' || %(codigo_ficha)s || '%%'
      )

  AND (
        %(nombre_ficha)s IS NULL
        OR cp.fullname ILIKE '%%' || %(nombre_ficha)s || '%%'
      )

  AND (
        %(codigo_programa)s IS NULL
        OR COALESCE(cp.codigo_programa, '') ILIKE '%%' || %(codigo_programa)s || '%%'
      )

  AND (
        %(nombre_programa)s IS NULL
        OR COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname) ILIKE '%%' || %(nombre_programa)s || '%%'
      )

  AND (
        %(nivel)s IS NULL
        OR cp.tipo_programa = ANY(%(nivel)s::text[])
      )

  AND (
        %(modalidad)s IS NULL
        OR CASE
               WHEN cp.letra_modalidad = 'V' THEN 'Virtual'
               WHEN cp.letra_modalidad = 'A' THEN 'A distancia'
               WHEN cp.letra_modalidad IN ('P', 'PI') THEN 'Presencial'
               ELSE 'No definido'
           END = ANY(%(modalidad)s::text[])
      )

  AND (
        %(regional)s IS NULL
        OR COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, '') ILIKE '%%' || %(regional)s || '%%'
      )

  AND (
        %(centro_formacion)s IS NULL
        OR COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, '') ILIKE '%%' || %(centro_formacion)s || '%%'
      )

  AND (
        %(estado_grupo)s IS NULL
        OR CASE
               WHEN cp.visible = 0 THEN 'Oculto'
               WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
               WHEN cp.enddate > 0
                    AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
               ELSE 'En ejecución'
           END = %(estado_grupo)s
      )

  AND (
        %(rol_usuario)s IS NULL
        OR EXISTS (
            SELECT 1
            FROM public.mdl_role_assignments ra
            JOIN public.mdl_context ctx
                ON ctx.id = ra.contextid
               AND ctx.contextlevel = 50
            JOIN public.mdl_role r
                ON r.id = ra.roleid
            WHERE ctx.instanceid = cp.courseid
              AND r.shortname = ANY(%(rol_usuario)s::text[])
        )
      )

  AND (
        %(origen_datos)s IS NULL
        OR LOWER(%(origen_datos)s::text) IN ('todas', 'todos')
        OR CASE
               WHEN (
                    cp.shortname ~ '^P_[0-9]+_'
                    OR cp.shortname ~ '^[0-9]+P_[0-9]+_'
               )
               THEN 'Integración'
               ELSE 'Manual'
           END = %(origen_datos)s
      )

  AND (
        %(hora_grupo)s IS NULL
        OR (
            cp.startdate > 0
            AND TO_CHAR(
                TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota',
                'HH24'
            ) = LPAD(SPLIT_PART(%(hora_grupo)s::text, ':', 1), 2, '0')
        )
      )

  AND (
        %(fecha_inicio)s IS NULL
        OR (
            cp.startdate > 0
            AND (TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota')::date >= %(fecha_inicio)s::date
        )
      )

  AND (
        %(fecha_fin)s IS NULL
        OR (
            cp.enddate > 0
            AND (TO_TIMESTAMP(cp.enddate) AT TIME ZONE 'America/Bogota')::date <= %(fecha_fin)s::date
        )
      )

GROUP BY
    cp.courseid,
    cp.idnumber,
    cp.shortname,
    cp.fullname,
    cp.letra_modalidad,
    cp.codigo_programa,
    cp.version_extraida,
    cp.programa_formacion,
    cp.tipo_programa,
    cp.visible,
    cp.startdate,
    cp.enddate,
    reg.nombre,
    cen.nombre,
    cp.codigo_regional,
    cp.codigo_centro

ORDER BY
    cp.fullname