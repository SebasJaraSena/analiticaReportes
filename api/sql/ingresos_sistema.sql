WITH ingresos AS (
    SELECT
        u.id AS userid,
        COALESCE(NULLIF(TRIM(u.country), ''), 'No definido') AS pais_perfil,
        COALESCE(NULLIF(TRIM(u.city), ''), 'No definido')    AS ciudad_perfil,
        COALESCE(NULLIF(TRIM(l.ip), ''), 'No disponible')    AS ip_ingreso,
        TO_TIMESTAMP(l.timecreated) AT TIME ZONE 'America/Bogota' AS fecha_ingreso
    FROM public.mdl_logstore_standard_log l
    JOIN public.mdl_user u ON u.id = l.userid
    WHERE l.eventname = E'\\core\\event\\user_loggedin'
      AND l.userid > 0
      AND u.deleted = 0
      AND (
            %(fecha_desde)s IS NULL
            OR l.timecreated >= EXTRACT(
                EPOCH FROM (%(fecha_desde)s::date AT TIME ZONE 'America/Bogota')
            )::bigint
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR l.timecreated < EXTRACT(
                EPOCH FROM ((%(fecha_hasta)s::date + 1) AT TIME ZONE 'America/Bogota')
            )::bigint
          )
),

roles_usuario AS (
    SELECT
        ra.userid,
        STRING_AGG(
            DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname),
            ', '
        ) AS rol_usuario
    FROM public.mdl_role_assignments ra
    JOIN public.mdl_role r ON r.id = ra.roleid
    GROUP BY ra.userid
)

SELECT
    COALESCE(ru.rol_usuario, 'Sin rol') AS "Rol de usuario",

    'No disponible, consultar en ADI' AS "Sistema operativo",

    'No disponible, consultar en ADI' AS "Navegador web",

    i.pais_perfil AS "País registrado en perfil",

    i.ciudad_perfil AS "Ciudad registrada en perfil",

    i.ip_ingreso AS "IP de ingreso",

    COUNT(*) AS "Total de ingresos",

    COUNT(DISTINCT i.userid) AS "Usuarios únicos"

FROM ingresos i

LEFT JOIN roles_usuario ru
    ON ru.userid = i.userid

WHERE (
        %(fecha_desde)s IS NULL
        OR i.fecha_ingreso::date >= %(fecha_desde)s::date
      )

  AND (
        %(fecha_hasta)s IS NULL
        OR i.fecha_ingreso::date <= %(fecha_hasta)s::date
      )

  AND (
        %(mes)s IS NULL
        OR EXTRACT(MONTH FROM i.fecha_ingreso)::int = %(mes)s::int
      )

  AND (
        %(semana)s IS NULL
        OR EXTRACT(WEEK FROM i.fecha_ingreso)::int = %(semana)s::int
      )

  AND (
        %(hora)s IS NULL
        OR TO_CHAR(i.fecha_ingreso, 'HH24') =
           LPAD(SPLIT_PART(%(hora)s::text, ':', 1), 2, '0')
      )

  AND (
        %(pais)s IS NULL
        OR i.pais_perfil ILIKE '%%' || %(pais)s || '%%'
      )

  AND (
        %(ciudad)s IS NULL
        OR i.ciudad_perfil ILIKE '%%' || %(ciudad)s || '%%'
      )

  -- SO/Navegador no provienen del log estándar de Moodle (ver columnas);
  -- el filtro compara contra el valor mostrado ('... consultar en ADI').
  AND (
        %(sistema_operativo)s IS NULL
        OR 'No disponible, consultar en ADI' ILIKE '%%' || %(sistema_operativo)s || '%%'
      )

  AND (
        %(navegador_web)s IS NULL
        OR 'No disponible, consultar en ADI' ILIKE '%%' || %(navegador_web)s || '%%'
      )

GROUP BY
    COALESCE(ru.rol_usuario, 'Sin rol'),
    i.pais_perfil,
    i.ciudad_perfil,
    i.ip_ingreso

ORDER BY
    "Total de ingresos" DESC,
    "Usuarios únicos" DESC,
    "Rol de usuario",
    "País registrado en perfil",
    "Ciudad registrada en perfil",
    "IP de ingreso"