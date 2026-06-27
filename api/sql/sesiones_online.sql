-- Reporte: Sesiones en Línea / VideoConferencia — basado en mdl_bigbluebuttonbn.
-- Muestra las sesiones en línea programadas en los grupos/fichas
-- dentro de las fechas seleccionadas en los filtros.

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
        c.timecreated AS curso_timecreated,

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
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_[A-Za-z]+_([0-9]+)') AS version_extraida

    FROM public.mdl_course c
    WHERE c.id <> 1
),

sesion_stats AS (
    SELECT
        bl.bigbluebuttonbnid,

        COUNT(*) FILTER (
            WHERE bl.userid > 0
              AND (
                    bl.log ILIKE '%%Join%%'
                 OR bl.log ILIKE '%%joined%%'
                 OR bl.log ILIKE '%%Attended%%'
              )
        ) AS total_ingresos,

        COUNT(DISTINCT CASE
            WHEN bl.userid > 0
             AND (
                    bl.log ILIKE '%%Join%%'
                 OR bl.log ILIKE '%%joined%%'
                 OR bl.log ILIKE '%%Attended%%'
             )
            THEN bl.userid
        END) AS total_usuarios,

        BOOL_OR(
            bl.log ILIKE '%%Create%%'
            OR bl.log ILIKE '%%created%%'
            OR bl.log ILIKE '%%Start%%'
            OR bl.log ILIKE '%%started%%'
        ) AS sesion_iniciada

    FROM public.mdl_bigbluebuttonbn_logs bl
    GROUP BY
        bl.bigbluebuttonbnid
)

SELECT
    COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, 'No definido') AS "Regional",

    COALESCE(cp.codigo_centro, 'No definido') AS "Código del centro",

    COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, 'No definido') AS "Nombre del centro",

    COALESCE(cp.codigo_programa, 'No definido') AS "Código del programa",

    COALESCE(cp.version_extraida, 'No definido') AS "Versión programa",

    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname) AS "Nombre del programa de formación",

    CASE
        WHEN cp.letra_modalidad IN ('V', 'A', 'P', 'PI') THEN 'Formación titulada'
        ELSE 'No definido'
    END AS "Nivel de formación",

    'No disponible (SOFIA Plus)' AS "Estado del Programa",

    cp.idnumber AS "Código de grupo/ficha",

    CASE
        WHEN cp.startdate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha de inicio del grupo/ficha",

    CASE
        WHEN cp.enddate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(cp.enddate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha fin del grupo",

    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado grupo",

    COALESCE(ss.total_ingresos, 0) AS "Cantidad de ingresos a la sesión",

    b.meetingid AS "Código de la sesión",

    b.name AS "Nombre de la Sesión",

    CASE
        WHEN b.openingtime > 0 THEN
            TO_CHAR(
                TO_TIMESTAMP(b.openingtime) AT TIME ZONE 'America/Bogota',
                'YYYY/MM/DD HH24:MI:SS'
            )
        ELSE 'No definida'
    END AS "Fecha de inicio de la sesión",

    CASE
        WHEN b.closingtime > 0 THEN
            TO_CHAR(
                TO_TIMESTAMP(b.closingtime) AT TIME ZONE 'America/Bogota',
                'YYYY/MM/DD HH24:MI:SS'
            )
        ELSE 'No definida'
    END AS "Fecha Fin de la Sesión",

    CASE
        WHEN COALESCE(ss.sesion_iniciada, false) THEN 'Sí'
        ELSE 'No'
    END AS "Sesión Iniciada Sí / No",

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.mdl_bigbluebuttonbn_recordings r
            WHERE r.bigbluebuttonbnid = b.id
              AND COALESCE(r.status, 0) >= 0
        )
        THEN 'Sí'
        ELSE 'No'
    END AS "Grabación Sí / No"

FROM public.mdl_bigbluebuttonbn b

JOIN curso_parseado cp
    ON cp.courseid = b.course

LEFT JOIN midb.regionales reg
    ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint

LEFT JOIN midb.centros cen
    ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint

LEFT JOIN sesion_stats ss
    ON ss.bigbluebuttonbnid = b.id

WHERE b.openingtime > 0

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
        %(estado_grupo)s IS NULL
        OR CASE
            WHEN cp.visible = 0 THEN 'Oculto'
            WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
            WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
            ELSE 'En ejecución'
           END = %(estado_grupo)s
      )

  AND (
        %(nivel)s IS NULL
        OR CASE
            WHEN cp.letra_modalidad IN ('V', 'A', 'P', 'PI') THEN 'Formación titulada'
            ELSE 'No definido'
           END = ANY(%(nivel)s::text[])
      )

  AND (
        %(modalidad)s IS NULL
        OR CASE
            WHEN cp.letra_modalidad = 'V' THEN 'Titulada virtual'
            WHEN cp.letra_modalidad = 'A' THEN 'Titulada a distancia'
            WHEN cp.letra_modalidad IN ('P', 'PI') THEN 'Titulada presencial'
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
        %(origen_datos)s IS NULL
        OR CASE
            WHEN cp.shortname ~ '^P_[0-9]+_'
              OR cp.shortname ~ '^[0-9]+P_[0-9]+_'
            THEN 'Integración'
            ELSE 'Manual'
           END = %(origen_datos)s
      )

  AND (
        %(rol_usuario)s IS NULL
        OR EXISTS (
            SELECT 1
            FROM public.mdl_bigbluebuttonbn_logs blr
            JOIN public.mdl_context ctx
                ON ctx.instanceid = cp.courseid
               AND ctx.contextlevel = 50
            JOIN public.mdl_role_assignments ra
                ON ra.userid = blr.userid
               AND ra.contextid = ctx.id
            JOIN public.mdl_role r
                ON r.id = ra.roleid
            WHERE blr.bigbluebuttonbnid = b.id
              AND (
                    string_to_array(r.shortname, ',') && %(rol_usuario)s::text[]
                 OR COALESCE(NULLIF(r.name, ''), r.shortname) ILIKE '%%' || %(rol_usuario)s || '%%'
              )
        )
      )

  AND (
        %(identificacion)s IS NULL
        OR EXISTS (
            SELECT 1
            FROM public.mdl_bigbluebuttonbn_logs bl2
            JOIN public.mdl_user u2
                ON u2.id = bl2.userid
            WHERE bl2.bigbluebuttonbnid = b.id
              AND (


                    COALESCE(NULLIF(u2.idnumber, ''), u2.username) ILIKE '%%' || %(identificacion)s || '%%'
                 OR u2.username ILIKE '%%' || %(identificacion)s || '%%'
              )
        )
      )

  AND (
        %(nombres_apellidos)s IS NULL
        OR EXISTS (
            SELECT 1
            FROM public.mdl_bigbluebuttonbn_logs bl3
            JOIN public.mdl_user u3
                ON u3.id = bl3.userid
            WHERE bl3.bigbluebuttonbnid = b.id
              AND CONCAT(u3.firstname, ' ', u3.lastname) ILIKE '%%' || %(nombres_apellidos)s || '%%'
        )
      )

  AND (
        %(fecha_desde)s IS NULL
        OR (TO_TIMESTAMP(b.openingtime) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
      )

  AND (
        %(fecha_hasta)s IS NULL
        OR (TO_TIMESTAMP(b.openingtime) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
      )

  AND (
        %(fecha_inicio_grupo_desde)s IS NULL
        OR (TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota')::date >= %(fecha_inicio_grupo_desde)s::date
      )

  AND (
        %(fecha_inicio_grupo_hasta)s IS NULL
        OR (TO_TIMESTAMP(cp.startdate) AT TIME ZONE 'America/Bogota')::date <= %(fecha_inicio_grupo_hasta)s::date
      )

  AND (
        %(fecha_creacion_grupo_desde)s IS NULL
        OR (TO_TIMESTAMP(cp.curso_timecreated) AT TIME ZONE 'America/Bogota')::date >= %(fecha_creacion_grupo_desde)s::date
      )

  AND (
        %(fecha_creacion_grupo_hasta)s IS NULL
        OR (TO_TIMESTAMP(cp.curso_timecreated) AT TIME ZONE 'America/Bogota')::date <= %(fecha_creacion_grupo_hasta)s::date
      )

ORDER BY
    cp.idnumber,
    b.openingtime DESC,
    b.name