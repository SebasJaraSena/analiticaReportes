WITH ingresos AS (
    SELECT
        u.id AS userid,
        COALESCE(NULLIF(TRIM(u.country), ''), 'No definido') AS pais_perfil,
        COALESCE(NULLIF(TRIM(u.city), ''), 'No definido')    AS ciudad_perfil,
        TO_TIMESTAMP(l.timecreated) AT TIME ZONE 'America/Bogota' AS fecha_ingreso
    FROM mdl_logstore_standard_log l
    JOIN mdl_user u ON u.id = l.userid
    WHERE l.eventname = E'\\core\\event\\user_loggedin'
      AND l.userid > 0
      AND u.deleted = 0
),
roles_usuario AS (
    SELECT
        ra.userid,
        STRING_AGG(DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname), ', ') AS rol_usuario
    FROM mdl_role_assignments ra
    JOIN mdl_role r ON r.id = ra.roleid
    GROUP BY ra.userid
)
SELECT
    COALESCE(ru.rol_usuario, 'Sin rol')                AS "Rol de usuario",
    'No disponible en Moodle estándar'                 AS "Sistema operativo",
    'No disponible en Moodle estándar'                 AS "Navegador web",
    i.pais_perfil                                      AS "País",
    i.ciudad_perfil                                    AS "Ciudad",
    COUNT(*)                                           AS "Total de ingresos",
    COUNT(DISTINCT i.userid)                           AS "Usuarios únicos"
FROM ingresos i
LEFT JOIN roles_usuario ru ON ru.userid = i.userid
WHERE (%(fecha_desde)s IS NULL OR i.fecha_ingreso::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL OR i.fecha_ingreso::date <= %(fecha_hasta)s::date)
  AND (%(mes)s IS NULL OR EXTRACT(MONTH FROM i.fecha_ingreso)::int = %(mes)s::int)
  AND (%(semana)s IS NULL OR EXTRACT(WEEK FROM i.fecha_ingreso)::int = %(semana)s::int)
  AND (%(hora)s IS NULL OR TO_CHAR(i.fecha_ingreso, 'HH24') = LPAD(SPLIT_PART(%(hora)s::text, ':', 1), 2, '0'))
  AND (%(pais)s IS NULL OR i.pais_perfil ILIKE '%%' || %(pais)s || '%%')
  AND (%(ciudad)s IS NULL OR i.ciudad_perfil ILIKE '%%' || %(ciudad)s || '%%')
GROUP BY
    COALESCE(ru.rol_usuario, 'Sin rol'),
    i.pais_perfil,
    i.ciudad_perfil
ORDER BY
    "Total de ingresos" DESC,
    "Usuarios únicos" DESC,
    "Rol de usuario",
    "País",
    "Ciudad"