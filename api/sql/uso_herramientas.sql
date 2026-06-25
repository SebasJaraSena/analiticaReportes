-- Reporte 1.7: Uso de herramientas LMS
-- Por grupo/ficha y módulo: actividades creadas, total usos, usuarios únicos, primer y último uso.
-- SIN INTEGRACION. Programa/código de fullname, modalidad de shortname, regional/centro de midb.
WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber, c.shortname, c.fullname, c.category,
        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$')          AS codigo_programa,
        TRIM(REGEXP_REPLACE(c.fullname, '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$', '')) AS programa_formacion,
        SUBSTRING(c.shortname FROM '_R_([0-9]+)')                              AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)')                              AS codigo_centro,
        SUBSTRING(c.shortname FROM '^P_[0-9]+_([A-Za-z]+)_')                   AS letra_modalidad
    FROM public.mdl_course c
    WHERE c.id <> 1
)
SELECT
    cp.idnumber                                                              AS "Código grupo/ficha",
    cp.fullname                                                              AS "Nombre grupo/ficha en el LMS",
    CASE
        WHEN cp.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada'
        ELSE 'No definido'
    END                                                                      AS "Nivel del programa",
    CASE
        WHEN cp.letra_modalidad = 'V'         THEN 'Titulada virtual'
        WHEN cp.letra_modalidad = 'A'         THEN 'Titulada a distancia'
        WHEN cp.letra_modalidad IN ('P','PI') THEN 'Formación presencial'
        ELSE 'No definido'
    END                                                                      AS "Modalidad",
    COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, 'No definido') AS "Regional",
    COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, 'No definido')     AS "Centro de Formación",
    COALESCE(cp.codigo_programa, 'No definido')                           AS "Código Programa de Formación",
    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname)              AS "Programa de formación",
    m.name                                                                  AS "Herramienta LMS",
    COUNT(DISTINCT cm.id)                                                   AS "Actividades creadas",
    COUNT(l.id)                                                             AS "Total usos",
    COUNT(DISTINCT l.userid)                                                AS "Usuarios únicos",
    CASE WHEN MIN(l.timecreated) IS NULL THEN 'Sin uso'
         ELSE TO_CHAR(TO_TIMESTAMP(MIN(l.timecreated)), 'YYYY/MM/DD HH24:MI:SS')
    END                                                                      AS "Primer uso",
    CASE WHEN MAX(l.timecreated) IS NULL THEN 'Sin uso'
         ELSE TO_CHAR(TO_TIMESTAMP(MAX(l.timecreated)), 'YYYY/MM/DD HH24:MI:SS')
    END                                                                      AS "Último uso"
FROM public.mdl_course_modules cm
JOIN public.mdl_modules m     ON m.id = cm.module
JOIN curso_parseado cp        ON cp.courseid = cm.course
LEFT JOIN midb.regionales reg ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint
LEFT JOIN midb.centros cen    ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint
LEFT JOIN public.mdl_logstore_standard_log l
       ON l.courseid = cp.courseid
      AND l.contextinstanceid = cm.id
      AND l.contextlevel = 70
WHERE (%(codigo_ficha)s     IS NULL OR cp.idnumber ILIKE %(codigo_ficha)s)
  AND (%(nombre_ficha)s     IS NULL OR cp.fullname ILIKE '%%' || %(nombre_ficha)s || '%%')
  AND (%(codigo_programa)s  IS NULL OR COALESCE(cp.codigo_programa,'') = %(codigo_programa)s)
  AND (%(nivel)s            IS NULL OR
       CASE WHEN cp.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada' ELSE 'No definido' END
       ILIKE '%%' || %(nivel)s || '%%')
  AND (%(modalidad)s        IS NULL OR
       CASE WHEN cp.letra_modalidad = 'V' THEN 'Titulada virtual'
            WHEN cp.letra_modalidad = 'A' THEN 'Titulada a distancia'
            WHEN cp.letra_modalidad IN ('P','PI') THEN 'Formación presencial'
            ELSE 'No definido' END ILIKE '%%' || %(modalidad)s || '%%')
  AND (%(regional)s         IS NULL OR COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, '') ILIKE '%%' || %(regional)s || '%%')
  AND (%(centro_formacion)s IS NULL OR COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, '') ILIKE '%%' || %(centro_formacion)s || '%%')
  AND (%(estado_grupo)s     IS NULL OR
       CASE WHEN cm.deletioninprogress > 0 THEN 'Eliminado'
            ELSE 'Activo' END = %(estado_grupo)s)
  AND (%(fecha_desde)s IS NULL OR l.timecreated IS NULL
       OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL OR l.timecreated IS NULL
       OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_hasta)s::date)
GROUP BY
    cp.idnumber, cp.fullname, cp.letra_modalidad,
    reg.nombre, cen.nombre, cp.codigo_regional, cp.codigo_centro,
    cp.codigo_programa, cp.programa_formacion, m.name
ORDER BY cp.fullname, "Total usos" DESC, m.name
