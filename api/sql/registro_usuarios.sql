-- Reporte 1.1: Registro de usuarios
-- Usuarios matriculados en grupos/fichas del LMS, sin importar rol.
-- Los ingresos se calculan por usuario + grupo/ficha en el periodo seleccionado.
-- Usuarios sin ingresos aparecen con 0 en "Total días que Ingresó".

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

        -- Código de programa: número entre paréntesis al final de fullname
        -- Ejemplo: Nombre Programa (123456)
        -- Ejemplo proyecto: Nombre Programa (123456_PRY_789)
        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$') AS codigo_programa,

        -- Nombre de programa: fullname sin el código final entre paréntesis
        TRIM(
            REGEXP_REPLACE(
                c.fullname,
                '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$',
                ''
            )
        ) AS programa_formacion,

        -- Regional y centro desde shortname
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS codigo_centro,

        -- Modalidad y versión desde shortname
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
        ue.userid,
        e.courseid,

        -- Si el usuario tiene al menos una matrícula activa en el curso,
        -- se considera activa para el reporte.
        CASE
            WHEN BOOL_OR(ue.status = 0) THEN 'Activa'
            ELSE 'Suspendida'
        END AS estado_matricula_lms

    FROM public.mdl_user_enrolments ue
    JOIN public.mdl_enrol e ON e.id = ue.enrolid
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
),

ingresos_curso AS (
    SELECT
        l.userid,
        l.courseid,

        -- Días únicos en los que ingresó al grupo/ficha
        COUNT(DISTINCT DATE(TO_TIMESTAMP(l.timecreated))) AS total_dias_ingreso,

        -- Total de ingresos al grupo/ficha
        COUNT(*) AS total_ingresos,

        MIN(l.timecreated) AS fecha_primer_acceso_grupo,
        MAX(l.timecreated) AS fecha_ultimo_acceso_grupo

    FROM public.mdl_logstore_standard_log l
    WHERE l.userid > 0
      AND l.courseid IS NOT NULL

      -- Acceso/vista del curso, no cualquier evento interno
      AND l.action = 'viewed'
      AND l.target = 'course'

      -- Filtro por hora del ingreso
      AND (
            %(hora)s IS NULL
            OR TO_CHAR(TO_TIMESTAMP(l.timecreated), 'HH24') =
               LPAD(SPLIT_PART(%(hora)s::text, ':', 1), 2, '0')
          )

      -- Periodo de ingresos
      AND (
            %(fecha_inicio)s IS NULL
            OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_inicio)s::date
          )

      AND (
            %(fecha_fin)s IS NULL
            OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_fin)s::date
          )

    GROUP BY
        l.userid,
        l.courseid
)

SELECT
    cp.idnumber AS "Código de grupo/ficha",

    cp.fullname AS "Nombre grupo/ficha en el LMS",

    cp.tipo_programa AS "Tipo de programa",

    CASE
        WHEN cp.letra_modalidad = 'V' THEN 'Virtual'
        WHEN cp.letra_modalidad = 'A' THEN 'A distancia'
        WHEN cp.letra_modalidad IN ('P', 'PI') THEN 'Presencial'
        ELSE 'No definido'
    END AS "Modalidad",

    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0
             AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado del grupo/ficha",

    COALESCE(cp.codigo_programa, 'No definido') AS "Código Programa de Formación",

    COALESCE(cp.version_extraida, 'No definido') AS "Versión Programa de Formación",

    COALESCE(
        NULLIF(cp.programa_formacion, ''),
        cp.fullname
    ) AS "Programa de formación",

    CASE
        WHEN cp.startdate IS NULL OR cp.startdate = 0 THEN 'No definida'
        ELSE TO_CHAR(TO_TIMESTAMP(cp.startdate), 'YYYY/MM/DD HH24:MI:SS')
    END AS "Fecha de inicio de grupo/ficha",

    CASE
        WHEN cp.enddate IS NULL OR cp.enddate = 0 THEN 'No definida'
        ELSE TO_CHAR(TO_TIMESTAMP(cp.enddate), 'YYYY/MM/DD HH24:MI:SS')
    END AS "Fecha fin de grupo/ficha",

    COALESCE(
        reg.nombre,
        'Regional ' || cp.codigo_regional,
        'No definido'
    ) AS "Regional",

    COALESCE(
        cen.nombre,
        'Centro ' || cp.codigo_centro,
        'No definido'
    ) AS "Centro de Formación",

    COALESCE(
        ru.rol_usuario,
        'Sin rol asignado'
    ) AS "Rol de usuario",

    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti|te)$'
        THEN UPPER(SUBSTRING(LOWER(u.username) FROM '(cc|dni|ce|ppt|ti|te)$'))
        ELSE 'No definido'
    END AS "Tipo de Documento",

    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti|te)$'
        THEN REGEXP_REPLACE(u.username, '(cc|dni|ce|ppt|ti|te)$', '', 'i')
        ELSE u.username
    END AS "Documento",

    CONCAT(u.firstname, ' ', u.lastname) AS "Nombres y apellidos",

    CASE
        WHEN ic.fecha_primer_acceso_grupo IS NULL THEN 'Sin acceso'
        ELSE TO_CHAR(
            TO_TIMESTAMP(ic.fecha_primer_acceso_grupo),
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha de acceso al grupo/ficha",

    CASE
        WHEN u.lastaccess IS NULL OR u.lastaccess = 0 THEN 'Sin acceso'
        ELSE TO_CHAR(
            TO_TIMESTAMP(u.lastaccess),
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha de último acceso al LMS",

    COALESCE(ic.total_dias_ingreso, 0) AS "Total días que Ingresó",

    COALESCE(ic.total_ingresos, 0) AS "Total ingresos al grupo/ficha",

    mu.estado_matricula_lms AS "Estado matrícula LMS"

FROM matriculas_usuario_curso mu
JOIN curso_parseado cp
    ON cp.courseid = mu.courseid
JOIN public.mdl_user u
    ON u.id = mu.userid

LEFT JOIN midb.regionales reg
    ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint

LEFT JOIN midb.centros cen
    ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint

LEFT JOIN roles_usuario_curso ru
    ON ru.userid = u.id
   AND ru.courseid = cp.courseid

LEFT JOIN ingresos_curso ic
    ON ic.userid = u.id
   AND ic.courseid = cp.courseid

WHERE u.deleted = 0

  AND (
        %(codigo_ficha)s IS NULL
        OR cp.idnumber ILIKE %(codigo_ficha)s
      )

  AND (
        %(nombre_ficha)s IS NULL
        OR cp.fullname ILIKE '%%' || %(nombre_ficha)s || '%%'
      )

  AND (
        %(identificacion)s IS NULL
        OR u.username ILIKE '%%' || %(identificacion)s || '%%'
      )

  AND (
        %(nombres_apellidos)s IS NULL
        OR CONCAT(u.firstname, ' ', u.lastname) ILIKE '%%' || %(nombres_apellidos)s || '%%'
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
        OR EXISTS (SELECT 1 FROM unnest(string_to_array(ru.rol_shortnames, ',')) AS _r(role)
                   WHERE trim(_r.role) = ANY(%(rol_usuario)s::text[]))
      )

  AND (
        %(estado_aprendiz)s IS NULL
        OR mu.estado_matricula_lms = %(estado_aprendiz)s
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

ORDER BY
    cp.fullname,
    "Rol de usuario",
    "Nombres y apellidos"