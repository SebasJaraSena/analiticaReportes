-- Reporte 1.4: Usuarios por ambiente — detalle por usuario
-- ZAJUNA = base de producción. tipo_documento desde mdl_user_info_data.
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
    COALESCE(
        (SELECT uid.data FROM mdl_user_info_data uid
         JOIN mdl_user_info_field uif ON uif.id = uid.fieldid
         WHERE uif.shortname IN ('tipo_documento','tipodocumento','tipo_doc','tipoidentificacion','tipo_identificacion')
           AND uid.userid = u.id LIMIT 1),
        'No definido'
    )                                                                       AS "Tipo de Identificación",
    COALESCE(NULLIF(u.idnumber,''), u.username)                            AS "Identificación",
    CONCAT(u.firstname, ' ', u.lastname)                                   AS "Nombres y apellidos",
    u.email                                                                 AS "Correo electrónico",
    CASE
        WHEN u.deleted = 1  THEN 'Eliminado'
        WHEN u.suspended = 1 THEN 'Suspendido'
        ELSE 'Activo'
    END                                                                     AS "Estado del Usuario LMS",
    CASE
        WHEN u.auth = 'manual' THEN 'Manual'
        ELSE 'Integración / Externo'
    END                                                                     AS "Origen de Creación del Usuario",
    TO_CHAR(TO_TIMESTAMP(u.timecreated), 'YYYY/MM/DD HH24:MI:SS')         AS "Fecha Creación del Usuario en el ambiente",
    CASE WHEN u.lastaccess > 0
         THEN TO_CHAR(TO_TIMESTAMP(u.lastaccess), 'YYYY/MM/DD HH24:MI:SS')
         ELSE 'Sin acceso'
    END                                                                     AS "Fecha del último acceso"
FROM mdl_user u
WHERE u.id > 2
  AND (%(identificacion)s    IS NULL OR COALESCE(NULLIF(u.idnumber,''), u.username) ILIKE %(identificacion)s)
  AND (%(nombres_apellidos)s IS NULL OR CONCAT(u.firstname,' ',u.lastname) ILIKE '%%' || %(nombres_apellidos)s || '%%')
  AND (%(estado)s IS NULL OR
       CASE WHEN u.deleted = 1 THEN 'Eliminado'
            WHEN u.suspended = 1 THEN 'Suspendido'
            ELSE 'Activo' END = %(estado)s)
  AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(u.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(u.timecreated)::date <= %(fecha_hasta)s::date)
ORDER BY u.lastname, u.firstname
