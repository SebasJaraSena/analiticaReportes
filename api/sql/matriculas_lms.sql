-- Reporte 1.3: Matrículas LMS
-- Presenta aprendices, instructores y demás roles que estuvieron enrolados
-- en un grupo/ficha durante el periodo seleccionado.

WITH parametros AS (
    SELECT
        %(fecha_desde)s::date AS fecha_desde,
        %(fecha_hasta)s::date AS fecha_hasta,

        CASE
            WHEN %(fecha_desde)s IS NULL THEN NULL
            ELSE EXTRACT(EPOCH FROM %(fecha_desde)s::date)::bigint
        END AS fecha_desde_epoch,

        CASE
            WHEN %(fecha_hasta)s IS NULL THEN NULL
            ELSE EXTRACT(EPOCH FROM (%(fecha_hasta)s::date + INTERVAL '1 day'))::bigint - 1
        END AS fecha_hasta_epoch,

        EXTRACT(EPOCH FROM NOW())::bigint AS ahora_epoch
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

matriculas_usuario_curso AS (
    SELECT
        ue.userid,
        e.courseid,

        MIN(COALESCE(NULLIF(ue.timestart, 0), ue.timecreated)) AS fecha_enrolamiento_epoch,

        CASE
            WHEN BOOL_OR(ue.timeend = 0 OR ue.timeend IS NULL) THEN 0
            ELSE MAX(ue.timeend)
        END AS fecha_desenrolamiento_epoch,

        CASE
            WHEN BOOL_OR(ue.status = 0 AND e.status = 0) THEN 'Activo'
            ELSE 'Suspendido'
        END AS estado_matricula_lms,

        CASE
            WHEN BOOL_OR(e.status = 0) THEN 'Activo'
            ELSE 'Inactivo'
        END AS estado_metodo_matricula

    FROM public.mdl_user_enrolments ue
    JOIN public.mdl_enrol e
        ON e.id = ue.enrolid
    CROSS JOIN parametros p

    WHERE (
            p.fecha_hasta_epoch IS NULL
            OR COALESCE(NULLIF(ue.timestart, 0), ue.timecreated) <= p.fecha_hasta_epoch
          )

      AND (
            p.fecha_desde_epoch IS NULL
            OR ue.timeend = 0
            OR ue.timeend IS NULL
            OR ue.timeend >= p.fecha_desde_epoch
          )

    GROUP BY
        ue.userid,
        e.courseid
),

roles_usuario_curso AS (
    SELECT
        ra.userid,
        ctx.instanceid AS courseid,

        STRING_AGG(
            DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname),
            ', '
        ) AS rol_usuario,

        STRING_AGG(
            DISTINCT r.shortname,
            ', '
        ) AS rol_shortnames

    FROM public.mdl_role_assignments ra
    JOIN public.mdl_context ctx
        ON ctx.id = ra.contextid
       AND ctx.contextlevel = 50
    JOIN public.mdl_role r
        ON r.id = ra.roleid
    GROUP BY
        ra.userid,
        ctx.instanceid
)

SELECT
    cp.idnumber AS "Código de grupo/ficha",

    cp.fullname AS "Nombre grupo/ficha en el LMS",

    CASE
        WHEN cp.letra_modalidad IN ('V', 'A', 'P', 'PI') THEN 'Formación titulada'
        ELSE 'No definido'
    END AS "Nivel del grupo/ficha",

    CASE
        WHEN cp.letra_modalidad = 'V' THEN 'Titulada virtual'
        WHEN cp.letra_modalidad = 'A' THEN 'Titulada a distancia'
        WHEN cp.letra_modalidad IN ('P', 'PI') THEN 'Titulada presencial'
        ELSE 'No definido'
    END AS "Modalidad",

    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > p.ahora_epoch THEN 'No iniciado'
        WHEN cp.enddate > 0 AND cp.enddate < p.ahora_epoch THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado del grupo/ficha",

    COALESCE(cp.codigo_programa, 'No definido') AS "Código del Programa",

    COALESCE(cp.version_extraida, 'No definido') AS "Versión del Programa",

    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname) AS "Programa de formación",

    COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, 'No definido') AS "Regional",

    COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, 'No definido') AS "Centro de Formación",

    COALESCE(ru.rol_usuario, 'Sin rol asignado') AS "Rol de usuario",

    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt)$'
        THEN UPPER(SUBSTRING(LOWER(u.username) FROM '(cc|dni|ce|ppt)$'))
        ELSE 'No definido'
    END AS "Tipo de Documento",

    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt)$'
        THEN REGEXP_REPLACE(u.username, '(cc|dni|ce|ppt)$', '', 'i')
        ELSE u.username
    END AS "Documento",

    CONCAT(u.firstname, ' ', u.lastname) AS "Nombres y apellidos",

    mu.estado_matricula_lms AS "Estado matrícula LMS",

    mu.estado_metodo_matricula AS "Estado método de matrícula",

    CASE
        WHEN u.deleted = 1 THEN 'Eliminado'
        WHEN u.suspended = 1 THEN 'Suspendido'
        ELSE 'Activo'
    END AS "Estado del Usuario LMS",

    CASE
        WHEN cp.startdate IS NULL OR cp.startdate = 0 THEN 'No definida'
        ELSE TO_CHAR(TO_TIMESTAMP(cp.startdate), 'YYYY/MM/DD HH24:MI:SS')
    END AS "Fecha inicio grupo/ficha",

    CASE
        WHEN cp.enddate IS NULL OR cp.enddate = 0 THEN 'No definida'
        ELSE TO_CHAR(TO_TIMESTAMP(cp.enddate), 'YYYY/MM/DD HH24:MI:SS')
    END AS "Fecha fin grupo/ficha",

    CASE
        WHEN mu.fecha_enrolamiento_epoch IS NULL OR mu.fecha_enrolamiento_epoch = 0 THEN 'No definida'
        ELSE TO_CHAR(TO_TIMESTAMP(mu.fecha_enrolamiento_epoch), 'YYYY/MM/DD HH24:MI:SS')
    END AS "Fecha Enrolamiento",

    CASE
        WHEN mu.fecha_desenrolamiento_epoch IS NULL OR mu.fecha_desenrolamiento_epoch = 0 THEN 'No definida'
        ELSE TO_CHAR(TO_TIMESTAMP(mu.fecha_desenrolamiento_epoch), 'YYYY/MM/DD HH24:MI:SS')
    END AS "Fecha Desenrolamiento"

FROM matriculas_usuario_curso mu

JOIN curso_parseado cp
    ON cp.courseid = mu.courseid

JOIN public.mdl_user u
    ON u.id = mu.userid

CROSS JOIN parametros p

LEFT JOIN midb.regionales reg
    ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint

LEFT JOIN midb.centros cen
    ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint

LEFT JOIN roles_usuario_curso ru
    ON ru.userid = u.id
   AND ru.courseid = cp.courseid

WHERE u.deleted = 0

  AND (
        %(codigo_ficha)s IS NULL
        OR cp.idnumber ILIKE '%%' || %(codigo_ficha)s || '%%'
      )

  AND (
        %(nombre_ficha)s IS NULL
        OR cp.fullname ILIKE '%%' || %(nombre_ficha)s || '%%'
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
        %(nivel)s IS NULL
        OR CASE
               WHEN cp.letra_modalidad IN ('V', 'A', 'P', 'PI')
               THEN 'Formación titulada'
               ELSE 'No definido'
           END ILIKE '%%' || %(nivel)s || '%%'
      )

  AND (
        %(modalidad)s IS NULL
        OR CASE
               WHEN cp.letra_modalidad = 'V' THEN 'Titulada virtual'
               WHEN cp.letra_modalidad = 'A' THEN 'Titulada a distancia'
               WHEN cp.letra_modalidad IN ('P', 'PI') THEN 'Titulada presencial'
               ELSE 'No definido'
           END ILIKE '%%' || %(modalidad)s || '%%'
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
               WHEN cp.startdate > p.ahora_epoch THEN 'No iniciado'
               WHEN cp.enddate > 0 AND cp.enddate < p.ahora_epoch THEN 'Finalizado'
               ELSE 'En ejecución'
           END = %(estado_grupo)s
      )

  AND (
        %(rol_usuario)s IS NULL
        OR ru.rol_shortnames ILIKE '%%' || %(rol_usuario)s || '%%'
      )

  AND (
        %(fecha_inicio)s IS NULL
        OR TO_TIMESTAMP(cp.startdate)::date = %(fecha_inicio)s::date
      )

  AND (
        %(fecha_fin)s IS NULL
        OR (
            cp.enddate > 0
            AND TO_TIMESTAMP(cp.enddate)::date = %(fecha_fin)s::date
        )
      )

ORDER BY
    cp.fullname,
    "Rol de usuario",
    "Nombres y apellidos"