-- Reporte 1.6: Tráfico diario de usuarios
-- Origen se detecta por patrón del shortname del curso (Integración vs Manual).
SELECT
    DATE(TO_TIMESTAMP(l.timecreated))                                       AS "Fecha",
    CASE
        WHEN (c.shortname ~ '^P_[0-9]+_' OR c.shortname ~ '^[0-9]+P_[0-9]+_')
        THEN 'Integración'
        ELSE 'Manual'
    END                                                                      AS "Origen de datos",
    COUNT(*)                                                                AS "Total eventos",
    COUNT(DISTINCT l.userid)                                                AS "Usuarios únicos",
    COUNT(DISTINCT l.courseid)                                              AS "Grupos/fichas con actividad"
FROM mdl_logstore_standard_log l
JOIN mdl_user u    ON u.id = l.userid
JOIN mdl_course c  ON c.id = l.courseid
WHERE l.userid > 0
  AND u.deleted = 0
  AND l.action = 'viewed'
  AND l.courseid IS NOT NULL
  AND c.id <> 1
  AND (%(fecha_desde)s IS NULL
       OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL
       OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_hasta)s::date)
GROUP BY
    DATE(TO_TIMESTAMP(l.timecreated)),
    CASE WHEN (c.shortname ~ '^P_[0-9]+_' OR c.shortname ~ '^[0-9]+P_[0-9]+_') THEN 'Integración' ELSE 'Manual' END
ORDER BY "Fecha" DESC, "Origen de datos"
