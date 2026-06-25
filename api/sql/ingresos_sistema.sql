-- Reporte 1.2: Ingresos por navegador, ubicación y sistema
-- Moodle estándar no guarda user-agent, SO, navegador, país ni ciudad en mdl_logstore_standard_log.
SELECT
    EXTRACT(YEAR  FROM TO_TIMESTAMP(l.timecreated))::int                    AS "Año",
    EXTRACT(MONTH FROM TO_TIMESTAMP(l.timecreated))::int                    AS "Mes",
    EXTRACT(WEEK  FROM TO_TIMESTAMP(l.timecreated))::int                    AS "Semana del año",
    TO_CHAR(TO_TIMESTAMP(l.timecreated), 'HH24:00:00')                     AS "Hora",
    'No disponible en Moodle estándar'                                      AS "Sistema operativo",
    'No disponible en Moodle estándar'                                      AS "Navegador web",
    'No disponible en Moodle estándar'                                      AS "País",
    'No disponible en Moodle estándar'                                      AS "Ciudad",
    COALESCE(l.ip, 'Sin IP')                                                AS "IP",
    COALESCE(l.origin, 'Sin origen')                                        AS "Origen acceso",
    COUNT(*)                                                                AS "Total ingresos",
    COUNT(DISTINCT l.userid)                                                AS "Usuarios únicos"
FROM mdl_logstore_standard_log l
JOIN mdl_user u ON u.id = l.userid
WHERE l.userid > 0
  AND u.deleted = 0
  AND l.action = 'viewed'
  AND (%(fecha_desde)s IS NULL
       OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL
       OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_hasta)s::date)
  AND (%(usuario_email)s IS NULL OR u.email ILIKE '%%' || %(usuario_email)s || '%%')
GROUP BY
    EXTRACT(YEAR  FROM TO_TIMESTAMP(l.timecreated)),
    EXTRACT(MONTH FROM TO_TIMESTAMP(l.timecreated)),
    EXTRACT(WEEK  FROM TO_TIMESTAMP(l.timecreated)),
    TO_CHAR(TO_TIMESTAMP(l.timecreated), 'HH24:00:00'),
    COALESCE(l.ip, 'Sin IP'),
    COALESCE(l.origin, 'Sin origen')
ORDER BY "Año" DESC, "Mes" DESC, "Semana del año" DESC, "Hora" DESC
