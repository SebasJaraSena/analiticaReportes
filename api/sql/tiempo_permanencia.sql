-- Reporte: Tiempo de Permanencia por Herramientas — PIVOT por usuario+ficha
-- Una fila por usuario+grupo. Porcentaje de tiempo estimado por tipo de herramienta.
-- Saltos >30 min se truncan a 30 min. Fuente: mdl_logstore_standard_log.
WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber, c.shortname, c.fullname,
        c.visible, c.startdate, c.enddate,
        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$')          AS codigo_programa,
        TRIM(REGEXP_REPLACE(c.fullname, '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$', '')) AS programa_formacion,
        SUBSTRING(c.shortname FROM '_R_([0-9]+)')                              AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)')                              AS codigo_centro,
        SUBSTRING(c.shortname FROM '^P_[0-9]+_([A-Za-z]+)_')                   AS letra_modalidad,
        SUBSTRING(c.shortname FROM '^P_[0-9]+_[A-Za-z]+_([0-9]+)')             AS version_extraida
    FROM public.mdl_course c
    WHERE c.id <> 1
),
eventos AS (
    SELECT
        l.userid, l.courseid, l.contextinstanceid, l.timecreated,
        LEAD(l.timecreated) OVER (
            PARTITION BY l.userid, l.courseid ORDER BY l.timecreated
        ) AS siguiente_evento
    FROM public.mdl_logstore_standard_log l
    WHERE l.userid > 0
      AND l.courseid IS NOT NULL
      AND (%(fecha_desde)s IS NULL
           OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL
           OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_hasta)s::date)
),
tiempos AS (
    SELECT userid, courseid, contextinstanceid,
        CASE
            WHEN siguiente_evento IS NULL THEN 0
            WHEN siguiente_evento - timecreated > 1800 THEN 1800
            WHEN siguiente_evento - timecreated < 0 THEN 0
            ELSE siguiente_evento - timecreated
        END AS segundos_estimados
    FROM eventos
),
modulo_tiempo AS (
    SELECT
        t.userid, t.courseid,
        CASE
            WHEN m.name = 'forum' AND mf.type = 'blog'  THEN 'blog'
            WHEN m.name = 'forum' AND mf.type = 'news'  THEN 'anuncio'
            WHEN m.name = 'forum'                        THEN 'foro'
            WHEN m.name IS NULL                          THEN 'curso'
            ELSE m.name
        END AS herramienta,
        t.segundos_estimados
    FROM tiempos t
    LEFT JOIN public.mdl_course_modules cm ON cm.id = t.contextinstanceid
    LEFT JOIN public.mdl_modules m         ON m.id = cm.module
    LEFT JOIN public.mdl_forum mf          ON mf.id = cm.instance AND m.name = 'forum'
),
pivot_tiempo AS (
    SELECT
        userid, courseid,
        SUM(segundos_estimados)                                                          AS seg_total,
        SUM(CASE WHEN herramienta = 'wiki'            THEN segundos_estimados ELSE 0 END) AS seg_wiki,
        SUM(CASE WHEN herramienta = 'quiz'            THEN segundos_estimados ELSE 0 END) AS seg_evaluaciones,
        SUM(CASE WHEN herramienta = 'assign'          THEN segundos_estimados ELSE 0 END) AS seg_evidencias,
        SUM(CASE WHEN herramienta IN ('feedback','survey') THEN segundos_estimados ELSE 0 END) AS seg_encuestas,
        SUM(CASE WHEN herramienta = 'blog'            THEN segundos_estimados ELSE 0 END) AS seg_blogs,
        SUM(CASE WHEN herramienta = 'anuncio'         THEN segundos_estimados ELSE 0 END) AS seg_anuncios,
        SUM(CASE WHEN herramienta = 'foro'            THEN segundos_estimados ELSE 0 END) AS seg_foros,
        SUM(CASE WHEN herramienta = 'scorm'           THEN segundos_estimados ELSE 0 END) AS seg_scorm,
        SUM(CASE WHEN herramienta = 'bigbluebuttonbn' THEN segundos_estimados ELSE 0 END) AS seg_sesiones,
        SUM(CASE WHEN herramienta = 'chat'            THEN segundos_estimados ELSE 0 END) AS seg_chats,
        SUM(CASE WHEN herramienta = 'curso'           THEN segundos_estimados ELSE 0 END) AS seg_curso
    FROM modulo_tiempo
    GROUP BY userid, courseid
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
    COALESCE(cp.codigo_programa, 'No definido')                            AS "Código Programa de Formación",
    COALESCE(cp.version_extraida, 'No definido')                           AS "Versión Programa",
    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname)               AS "Programa de formación",
    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END                                                                      AS "Estado grupo",
    UPPER(SUBSTRING(LOWER(COALESCE(NULLIF(u.idnumber,''), u.username)) FROM '(cc|dni|ce|ppt)$'))
                                                                             AS "Tipo de Identificación",
    COALESCE(NULLIF(u.idnumber,''), u.username)                             AS "Identificación",
    CONCAT(u.firstname, ' ', u.lastname)                                    AS "Nombres y apellidos",
    ROUND(pt.seg_total / 60.0, 2)                                          AS "Minutos totales estimados",
    ROUND(pt.seg_total / 3600.0, 4)                                        AS "Horas totales estimadas",
    ROUND(100.0 * pt.seg_wiki        / NULLIF(pt.seg_total, 0), 2)        AS "% Tiempo Wikis",
    ROUND(100.0 * pt.seg_evaluaciones / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Evaluaciones",
    ROUND(100.0 * pt.seg_evidencias   / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Evidencias",
    ROUND(100.0 * pt.seg_encuestas    / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Encuestas/Sondeos",
    ROUND(100.0 * pt.seg_blogs        / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Blogs",
    ROUND(100.0 * pt.seg_anuncios     / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Anuncios",
    ROUND(100.0 * pt.seg_foros        / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Foros Temáticos",
    ROUND(100.0 * pt.seg_scorm        / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo SCORM",
    ROUND(100.0 * pt.seg_sesiones     / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Sesiones en Línea",
    ROUND(100.0 * pt.seg_chats        / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Chats",
    ROUND(100.0 * pt.seg_curso        / NULLIF(pt.seg_total, 0), 2)       AS "% Tiempo Plataforma/LMS"
FROM pivot_tiempo pt
JOIN public.mdl_user u         ON u.id = pt.userid
JOIN curso_parseado cp         ON cp.courseid = pt.courseid
LEFT JOIN midb.regionales reg  ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint
LEFT JOIN midb.centros cen     ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint
WHERE u.deleted = 0
  AND pt.seg_total > 0
  AND (%(codigo_ficha)s      IS NULL OR cp.idnumber ILIKE %(codigo_ficha)s)
  AND (%(nombre_ficha)s      IS NULL OR cp.fullname ILIKE '%%' || %(nombre_ficha)s || '%%')
  AND (%(codigo_programa)s   IS NULL OR COALESCE(cp.codigo_programa,'') = %(codigo_programa)s)
  AND (%(nombre_programa)s   IS NULL OR COALESCE(NULLIF(cp.programa_formacion,''), cp.fullname) ILIKE '%%' || %(nombre_programa)s || '%%')
  AND (%(nivel)s             IS NULL OR
       CASE WHEN cp.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada' ELSE 'No definido' END
       ILIKE '%%' || %(nivel)s || '%%')
  AND (%(modalidad)s         IS NULL OR
       CASE WHEN cp.letra_modalidad = 'V' THEN 'Titulada virtual'
            WHEN cp.letra_modalidad = 'A' THEN 'Titulada a distancia'
            WHEN cp.letra_modalidad IN ('P','PI') THEN 'Formación presencial'
            ELSE 'No definido' END ILIKE '%%' || %(modalidad)s || '%%')
  AND (%(regional)s          IS NULL OR COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, '') ILIKE '%%' || %(regional)s || '%%')
  AND (%(centro_formacion)s  IS NULL OR COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, '') ILIKE '%%' || %(centro_formacion)s || '%%')
  AND (%(estado_grupo)s      IS NULL OR
       CASE WHEN cp.visible = 0 THEN 'Oculto'
            WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
            WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
            ELSE 'En ejecución' END = %(estado_grupo)s)
  AND (%(identificacion)s    IS NULL OR COALESCE(NULLIF(u.idnumber,''), u.username) ILIKE %(identificacion)s)
  AND (%(nombres_apellidos)s IS NULL OR CONCAT(u.firstname,' ',u.lastname) ILIKE '%%' || %(nombres_apellidos)s || '%%')
  AND (%(fecha_inicio_desde)s IS NULL OR TO_TIMESTAMP(cp.startdate)::date >= %(fecha_inicio_desde)s::date)
  AND (%(fecha_inicio_hasta)s IS NULL OR TO_TIMESTAMP(cp.startdate)::date <= %(fecha_inicio_hasta)s::date)
  AND (%(fecha_fin_desde)s IS NULL OR (cp.enddate > 0 AND TO_TIMESTAMP(cp.enddate)::date >= %(fecha_fin_desde)s::date))
  AND (%(fecha_fin_hasta)s IS NULL OR (cp.enddate > 0 AND TO_TIMESTAMP(cp.enddate)::date <= %(fecha_fin_hasta)s::date))
ORDER BY cp.fullname, "Nombres y apellidos"
