-- Reporte 1.4: Usuarios por ambiente — detalle por usuario.
WITH creadores AS (
    SELECT DISTINCT ON (l.objectid)
        l.objectid AS userid_creado,
        CONCAT(uc.firstname, ' ', uc.lastname) AS usuario_creador
    FROM mdl_logstore_standard_log l
    LEFT JOIN mdl_user uc ON uc.id = l.userid
    WHERE l.eventname = E'\\core\\event\\user_created'
      AND l.objectid IS NOT NULL
    ORDER BY l.objectid, l.timecreated ASC
)
SELECT
    'ZAJUNA'                                                                AS "Ambiente",
    COALESCE(
        (SELECT STRING_AGG(DISTINCT COALESCE(NULLIF(r2.name,''), r2.shortname), ', ')
         FROM mdl_role_assignments ra2
         JOIN mdl_role r2 ON r2.id = ra2.roleid
         JOIN mdl_context ctx2 ON ctx2.id = ra2.contextid
         WHERE ra2.userid = u.id AND ctx2.contextlevel = 50),
        'Sin rol'
    )                                                                       AS "Rol de usuario",
    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti)$'
        THEN UPPER(SUBSTRING(LOWER(u.username) FROM '(cc|dni|ce|ppt|ti)$'))
        ELSE 'No definido'
    END                                                                     AS "Tipo de Identificación",
    CASE
        WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti)$'
        THEN REGEXP_REPLACE(u.username, '(cc|dni|ce|ppt|ti)$', '', 'i')
        ELSE u.username
    END                                                                     AS "Identificación",
    CONCAT(u.firstname, ' ', u.lastname)                                    AS "Nombres y apellidos",
    CASE
        WHEN u.deleted = 1  THEN 'Eliminado'
        WHEN u.suspended = 1 THEN 'Suspendido'
        ELSE 'Activo'
    END                                                                     AS "Estado del Usuario LMS",
    CASE
        WHEN u.auth = 'manual' THEN 'Manual'
        ELSE 'Integración / Externo'
    END                                                                     AS "Origen de Creación del Usuario",
    TO_CHAR(TO_TIMESTAMP(u.timecreated), 'YYYY/MM/DD HH24:MI:SS')           AS "Fecha Creación del Usuario en el ambiente",
    CASE WHEN u.lastaccess > 0
         THEN TO_CHAR(TO_TIMESTAMP(u.lastaccess), 'YYYY/MM/DD HH24:MI:SS')
         ELSE 'Sin acceso'
    END                                                                     AS "Fecha del último acceso",
    COALESCE(c.usuario_creador, 'No disponible')                            AS "Usuario Creador"
FROM mdl_user u
LEFT JOIN creadores c ON c.userid_creado = u.id
WHERE u.id > 2
  AND (%(mes)s IS NULL OR EXTRACT(MONTH FROM TO_TIMESTAMP(u.timecreated))::int = %(mes)s::int)
  AND (%(anio)s IS NULL OR EXTRACT(YEAR FROM TO_TIMESTAMP(u.timecreated))::int = %(anio)s::int)
  AND (%(origen_datos)s IS NULL OR
       CASE WHEN u.auth = 'manual' THEN 'Manual' ELSE 'Integración / Externo' END = %(origen_datos)s)
  AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(u.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(u.timecreated)::date <= %(fecha_hasta)s::date)
ORDER BY u.lastname, u.firstname
