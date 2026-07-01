-- Reporte 1.5: Grupos y programas de formación.
-- Permite visualizar los grupos/fichas creados en el LMS para programas de formación.
-- Si el usuario no diligencia filtros, se muestran todos los grupos/fichas disponibles.
-- La fecha de consulta del reporte corresponde al momento de ejecución de la consulta.
-- SOFIA Plus no está integrado en esta base; sus estados se reportan como no disponibles.

WITH parametros AS (
    SELECT
        EXTRACT(EPOCH FROM NOW())::bigint AS fecha_consulta_epoch
),

curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber,
        c.shortname,
        c.fullname,
        c.category,
        c.visible,
        c.startdate,
        c.enddate,
        c.timecreated,

        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$') AS codigo_programa,

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
            WHEN rc.name ILIKE '%%semilla%%' THEN 'Otros'
            WHEN rc.name ILIKE '%%complementaria%%' THEN 'Complementaria'
            WHEN rc.name ILIKE '%%titulada%%' OR rc.name ILIKE '%%presencial%%' THEN 'Titulada'
            ELSE 'Otros'
        END AS tipo_programa

    FROM public.mdl_course c
    LEFT JOIN public.mdl_course_categories cc ON cc.id = c.category
    LEFT JOIN public.mdl_course_categories rc
           ON rc.id = NULLIF(split_part(cc.path, '/', 2), '')::int
    WHERE c.id <> 1
),

matriculas_usuario_curso AS (
    SELECT
        en.courseid,
        ue.userid,

        CASE
            WHEN BOOL_OR(
                ue.status = 0
                AND en.status = 0
                AND u.deleted = 0
                AND u.suspended = 0
                AND (
                    ue.timestart IS NULL
                    OR ue.timestart = 0
                    OR ue.timestart <= p.fecha_consulta_epoch
                )
                AND (
                    ue.timeend IS NULL
                    OR ue.timeend = 0
                    OR ue.timeend >= p.fecha_consulta_epoch
                )
            )
            THEN 'Activo'
            ELSE 'Inactivo'
        END AS estado_matricula_usuario_curso

    FROM public.mdl_user_enrolments ue
    JOIN public.mdl_enrol en
        ON en.id = ue.enrolid
    JOIN public.mdl_user u
        ON u.id = ue.userid
    CROSS JOIN parametros p
    WHERE u.deleted = 0
    GROUP BY
        en.courseid,
        ue.userid
),

roles_por_curso AS (
    SELECT
        ctx.instanceid AS courseid,

        COUNT(DISTINCT mu.userid) FILTER (
            WHERE r.shortname IN ('teacher', 'editingteacher')
              AND mu.estado_matricula_usuario_curso = 'Activo'
        ) AS instructores_activos,

        COUNT(DISTINCT mu.userid) FILTER (
            WHERE r.shortname = 'student'
              AND mu.estado_matricula_usuario_curso = 'Activo'
        ) AS aprendices_activos,

        COUNT(DISTINCT mu.userid) FILTER (
            WHERE r.shortname IN ('teacher', 'editingteacher')
              AND mu.estado_matricula_usuario_curso = 'Inactivo'
        ) AS instructores_inactivos,

        COUNT(DISTINCT mu.userid) FILTER (
            WHERE r.shortname = 'student'
              AND mu.estado_matricula_usuario_curso = 'Inactivo'
        ) AS aprendices_inactivos

    FROM public.mdl_role_assignments ra
    JOIN public.mdl_context ctx
        ON ctx.id = ra.contextid
       AND ctx.contextlevel = 50
    JOIN public.mdl_role r
        ON r.id = ra.roleid
    JOIN matriculas_usuario_curso mu
        ON mu.userid = ra.userid
       AND mu.courseid = ctx.instanceid
    GROUP BY
        ctx.instanceid
)

SELECT
    COALESCE(cp.codigo_programa, 'No definido') AS "Código programa",

    COALESCE(cp.version_extraida, 'No definido') AS "Versión del programa",

    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname) AS "Nombre de programa",

    'No disponible (SOFIA Plus)' AS "Estado del Programa",

    cp.idnumber AS "Código grupo/ficha",

    cp.fullname AS "Nombre grupo/ficha en el LMS",

    CASE
        WHEN cp.timecreated IS NULL OR cp.timecreated = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(cp.timecreated) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha de creación del grupo",

    cp.tipo_programa AS "Tipo de programa",

    CASE
        WHEN cp.letra_modalidad = 'V' THEN 'Virtual'
        WHEN cp.letra_modalidad = 'A' THEN 'A distancia'
        WHEN cp.letra_modalidad IN ('P', 'PI') THEN 'Presencial'
        ELSE 'No definido'
    END AS "Modalidad",

    CASE
        WHEN cp.startdate IS NULL OR cp.startdate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha de inicio de grupo",

    CASE
        WHEN cp.enddate IS NULL OR cp.enddate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(cp.enddate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha fin de grupo",

    'No disponible (SOFIA Plus)' AS "Estado Grupo/ficha SOFIA Plus",

    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > p.fecha_consulta_epoch THEN 'No iniciado'
        WHEN cp.enddate > 0
             AND cp.enddate < p.fecha_consulta_epoch THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado Grupo/ficha LMS",

    COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, 'No definido') AS "Regional",

    COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, 'No definido') AS "Centro de Formación",

    COALESCE(rpc.instructores_activos, 0) AS "Cantidad de Instructores Activos",

    COALESCE(rpc.aprendices_activos, 0) AS "Cantidad de Aprendices Activos",

    COALESCE(rpc.instructores_inactivos, 0) AS "Cantidad de Instructores Inactivos",

    COALESCE(rpc.aprendices_inactivos, 0) AS "Cantidad de Aprendices Inactivos"

FROM curso_parseado cp

CROSS JOIN parametros p

LEFT JOIN midb.regionales reg
    ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint

LEFT JOIN midb.centros cen
    ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint

LEFT JOIN roles_por_curso rpc
    ON rpc.courseid = cp.courseid

WHERE
    -- Grupos creados hasta la fecha de consulta del reporte
    cp.timecreated <= p.fecha_consulta_epoch

  AND (
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
        OR COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, '') = ANY(%(regional)s::text[])
      )

  AND (
        %(centro_formacion)s IS NULL
        OR COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, '') = ANY(%(centro_formacion)s::text[])
      )

  AND (
        %(estado_grupo_sofia)s IS NULL
        OR 'No disponible (SOFIA Plus)' = %(estado_grupo_sofia)s
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
        %(estado_aprendiz)s IS NULL
        OR EXISTS (
            SELECT 1
            FROM public.mdl_role_assignments ra
            JOIN public.mdl_context ctx
                ON ctx.id = ra.contextid
               AND ctx.contextlevel = 50
            JOIN public.mdl_role r
                ON r.id = ra.roleid
            JOIN matriculas_usuario_curso mu
                ON mu.userid = ra.userid
               AND mu.courseid = ctx.instanceid
            WHERE ctx.instanceid = cp.courseid
              AND r.shortname = 'student'
              AND mu.estado_matricula_usuario_curso = %(estado_aprendiz)s
        )
      )

  AND (
        %(origen_datos)s IS NULL
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
        %(hora_creacion)s IS NULL
        OR TO_CHAR(
            TO_TIMESTAMP(cp.timecreated) AT TIME ZONE 'America/Bogota',
            'HH24'
        ) = LPAD(SPLIT_PART(%(hora_creacion)s::text, ':', 1), 2, '0')
      )

  AND (
        %(fecha_desde)s IS NULL
        OR (TO_TIMESTAMP(cp.timecreated) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
      )

  AND (
        %(fecha_hasta)s IS NULL
        OR (TO_TIMESTAMP(cp.timecreated) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
      )

  AND (
        %(hora_grupo)s IS NULL
        OR TO_CHAR(
            TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota',
            'HH24'
        ) = LPAD(SPLIT_PART(%(hora_grupo)s::text, ':', 1), 2, '0')
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

ORDER BY
    cp.timecreated DESC,
    cp.fullname