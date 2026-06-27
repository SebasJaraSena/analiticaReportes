-- Reporte 1.4: Usuarios por ambiente — detalle por usuario.
-- Reporte de usuarios registrados en el ambiente ZAJUNA.
-- Clasifica usuarios manuales vs integración/externo usando el método de autenticación.
-- Nota: para identificar SOFIA Plus con precisión se requiere una marca propia de integración.

WITH creadores AS (
    SELECT DISTINCT ON (l.objectid)
        l.objectid AS userid_creado,
        CONCAT(uc.firstname, ' ', uc.lastname) AS usuario_creador
    FROM public.mdl_logstore_standard_log l
    LEFT JOIN public.mdl_user uc
        ON uc.id = l.userid
    WHERE l.eventname = E'\\core\\event\\user_created'
      AND l.objectid IS NOT NULL
    ORDER BY
        l.objectid,
        l.timecreated ASC
),

roles_usuario AS (
    SELECT
        ra.userid,
        STRING_AGG(
            DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname),
            ', '
        ) AS rol_usuario,
        STRING_AGG(
            DISTINCT r.shortname,
            ', '
        ) AS rol_shortnames
    FROM public.mdl_role_assignments ra
    JOIN public.mdl_role r
        ON r.id = ra.roleid
    JOIN public.mdl_context ctx
        ON ctx.id = ra.contextid
       AND ctx.contextlevel IN (10, 40, 50)
       -- 10 = sistema
       -- 40 = categoría
       -- 50 = curso
    GROUP BY
        ra.userid
)

SELECT
    'ZAJUNA' AS "Ambiente",

    COALESCE(ru.rol_usuario, 'Sin rol') AS "Rol de usuario",

    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti|te)$'
        THEN UPPER(SUBSTRING(LOWER(u.username) FROM '(cc|dni|ce|ppt|ti|te)$'))
        ELSE 'No definido'
    END AS "Tipo de Identificación",

    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti|te)$'
        THEN REGEXP_REPLACE(u.username, '(cc|dni|ce|ppt|ti|te)$', '', 'i')
        ELSE u.username
    END AS "Identificación",

    CONCAT(u.firstname, ' ', u.lastname) AS "Nombres y apellidos",

    CASE
        WHEN u.deleted = 1 THEN 'Eliminado'
        WHEN u.suspended = 1 THEN 'Suspendido'
        ELSE 'Activo'
    END AS "Estado del Usuario LMS",

    u.auth AS "Método de autenticación",

    CASE
        WHEN u.auth = 'manual' THEN 'Manual'
        ELSE 'Integración / Externo'
    END AS "Origen de Creación del Usuario",

    CASE
        WHEN u.timecreated IS NULL OR u.timecreated = 0 THEN 'No disponible'
        ELSE TO_CHAR(
            TO_TIMESTAMP(u.timecreated) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha Creación del Usuario en el ambiente",

    CASE
        WHEN u.lastaccess > 0
        THEN TO_CHAR(
            TO_TIMESTAMP(u.lastaccess) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
        ELSE 'Sin acceso'
    END AS "Fecha del último acceso",

    COALESCE(c.usuario_creador, 'No disponible') AS "Usuario Creador"

FROM public.mdl_user u

LEFT JOIN creadores c
    ON c.userid_creado = u.id

LEFT JOIN roles_usuario ru
    ON ru.userid = u.id

WHERE u.id > 2

  AND (
        %(mes)s IS NULL
        OR EXTRACT(
            MONTH FROM TO_TIMESTAMP(u.timecreated) AT TIME ZONE 'America/Bogota'
        )::int = %(mes)s::int
      )

  AND (
        %(anio)s IS NULL
        OR EXTRACT(
            YEAR FROM TO_TIMESTAMP(u.timecreated) AT TIME ZONE 'America/Bogota'
        )::int = %(anio)s::int
      )

  AND (
        %(origen_datos)s IS NULL
        OR CASE
               WHEN u.auth = 'manual' THEN 'Manual'
               ELSE 'Integración / Externo'
           END = %(origen_datos)s
      )

  AND (
        %(fecha_desde)s IS NULL
        OR u.timecreated >= EXTRACT(
            EPOCH FROM (%(fecha_desde)s::date AT TIME ZONE 'America/Bogota')
        )::bigint
      )

  AND (
        %(fecha_hasta)s IS NULL
        OR u.timecreated < EXTRACT(
            EPOCH FROM ((%(fecha_hasta)s::date + 1) AT TIME ZONE 'America/Bogota')
        )::bigint
      )

ORDER BY
    u.lastname,
    u.firstname