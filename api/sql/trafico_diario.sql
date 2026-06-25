-- Reporte 1.6: Tráfico diario de usuarios.
-- Origen se detecta por patrón del shortname del curso (Integración vs Manual).
SELECT
    'Producción'                                                            AS "Ambiente",
    EXTRACT(YEAR FROM TO_TIMESTAMP(l.timecreated))::int                     AS "Año",
    EXTRACT(MONTH FROM TO_TIMESTAMP(l.timecreated))::int                    AS "Mes",
    EXTRACT(DAY FROM TO_TIMESTAMP(l.timecreated))::int                      AS "Día",
    TO_CHAR(TO_TIMESTAMP(l.timecreated), 'HH24:00') || ' - ' ||
        TO_CHAR(TO_TIMESTAMP(l.timecreated) + INTERVAL '59 minutes', 'HH24:59')
                                                                              AS "Rango de Hora (60 minutos)",
    COUNT(DISTINCT l.userid)                                                AS "Cantidad de Usuarios Únicos"
FROM mdl_logstore_standard_log l
JOIN mdl_user u    ON u.id = l.userid
JOIN mdl_course c  ON c.id = l.courseid
WHERE l.userid > 0
  AND u.deleted = 0
  AND l.action = 'viewed'
  AND l.courseid IS NOT NULL
  AND c.id <> 1
  AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_hasta)s::date)
  AND (%(origen_datos)s IS NULL OR
       CASE WHEN (c.shortname ~ '^P_[0-9]+_' OR c.shortname ~ '^[0-9]+P_[0-9]+_')
            THEN 'Integración' ELSE 'Manual' END = %(origen_datos)s)
  AND (%(rango_consulta)s IS NULL OR %(rango_consulta)s IN ('Día', 'Mes', 'Año'))
GROUP BY
    EXTRACT(YEAR FROM TO_TIMESTAMP(l.timecreated)),
    EXTRACT(MONTH FROM TO_TIMESTAMP(l.timecreated)),
    EXTRACT(DAY FROM TO_TIMESTAMP(l.timecreated)),
    TO_CHAR(TO_TIMESTAMP(l.timecreated), 'HH24:00'),
    TO_CHAR(TO_TIMESTAMP(l.timecreated) + INTERVAL '59 minutes', 'HH24:59')
ORDER BY "Año" DESC, "Mes" DESC, "Día" DESC, "Rango de Hora (60 minutos)" DESC
