-- Reporte: Tiempo de Permanencia por Herramientas.
-- Una fila por usuario+grupo. Porcentaje de tiempo estimado por tipo de herramienta.
-- Saltos >30 min se truncan a 30 min. Fuente principal: mdl_logstore_standard_log.
WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber, c.shortname, c.fullname,
        c.visible, c.startdate, c.enddate,
        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$') AS codigo_programa,
        TRIM(REGEXP_REPLACE(c.fullname, '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$', '')) AS programa_formacion,
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS codigo_centro,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_([A-Za-z]+)_') AS letra_modalidad,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_[A-Za-z]+_([0-9]+)') AS version_extraida
    FROM public.mdl_course c
    WHERE c.id <> 1
),
roles_usuario_curso AS (
    SELECT
        ra.userid,
        ctx.instanceid AS courseid,
        STRING_AGG(DISTINCT COALESCE(NULLIF(r.name,''), r.shortname), ', ') AS rol_usuario,
        STRING_AGG(DISTINCT r.shortname, ', ') AS rol_shortnames
    FROM public.mdl_role_assignments ra
    JOIN public.mdl_context ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
    JOIN public.mdl_role r ON r.id = ra.roleid
    GROUP BY ra.userid, ctx.instanceid
),
matriculas_usuario_curso AS (
    SELECT
        ue.userid,
        e.courseid,
        CASE WHEN BOOL_OR(ue.status = 0) THEN 'Activo' ELSE 'Inactivo' END AS estado_usuario_grupo
    FROM public.mdl_user_enrolments ue
    JOIN public.mdl_enrol e ON e.id = ue.enrolid
    GROUP BY ue.userid, e.courseid
),
base_usuarios AS (
    SELECT
        cp.courseid,
        cp.idnumber AS codigo_ficha,
        cp.fullname AS nombre_ficha,
        cp.codigo_programa,
        cp.version_extraida,
        cp.programa_formacion,
        cp.letra_modalidad,
        cp.codigo_regional,
        cp.codigo_centro,
        cp.startdate,
        cp.enddate,
        cp.visible,
        cp.shortname,
        u.id AS userid,
        CASE
            WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti)$'
            THEN UPPER(SUBSTRING(LOWER(u.username) FROM '(cc|dni|ce|ppt|ti)$'))
            ELSE 'No definido'
        END AS tipo_documento,
        CASE
            WHEN LOWER(u.username) ~ '(cc|dni|ce|ppt|ti)$'
            THEN REGEXP_REPLACE(u.username, '(cc|dni|ce|ppt|ti)$', '', 'i')
            ELSE u.username
        END AS documento,
        CONCAT(u.firstname, ' ', u.lastname) AS nombres_apellidos,
        COALESCE(ruc.rol_usuario, 'Sin rol asignado') AS rol_usuario,
        COALESCE(ruc.rol_shortnames, '') AS rol_shortnames,
        COALESCE(muc.estado_usuario_grupo, 'Sin matrícula') AS estado_usuario_grupo,
        CASE
            WHEN u.deleted = 1 THEN 'Eliminado'
            WHEN u.suspended = 1 THEN 'Suspendido'
            ELSE 'Activo'
        END AS estado_usuario_lms
    FROM curso_parseado cp
    JOIN matriculas_usuario_curso muc ON muc.courseid = cp.courseid
    JOIN public.mdl_user u ON u.id = muc.userid
    LEFT JOIN roles_usuario_curso ruc ON ruc.userid = u.id AND ruc.courseid = cp.courseid
    WHERE (%(codigo_ficha)s IS NULL OR cp.idnumber ILIKE '%%' || %(codigo_ficha)s || '%%')
      AND (%(nombre_ficha)s IS NULL OR cp.fullname ILIKE '%%' || %(nombre_ficha)s || '%%')
      AND (%(identificacion)s IS NULL OR u.username ILIKE '%%' || %(identificacion)s || '%%')
      AND (%(nombres_apellidos)s IS NULL OR CONCAT(u.firstname,' ',u.lastname) ILIKE '%%' || %(nombres_apellidos)s || '%%')
      AND (%(nombre_programa)s IS NULL OR COALESCE(NULLIF(cp.programa_formacion,''), cp.fullname) ILIKE '%%' || %(nombre_programa)s || '%%')
      AND (%(codigo_programa)s IS NULL OR COALESCE(cp.codigo_programa,'') ILIKE '%%' || %(codigo_programa)s || '%%')
      AND (%(nivel)s IS NULL OR CASE WHEN cp.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada' ELSE 'No definido' END ILIKE '%%' || %(nivel)s || '%%')
      AND (%(modalidad)s IS NULL OR
           CASE WHEN cp.letra_modalidad = 'V' THEN 'Titulada virtual'
                WHEN cp.letra_modalidad = 'A' THEN 'Titulada a distancia'
                WHEN cp.letra_modalidad IN ('P','PI') THEN 'Titulada presencial'
                ELSE 'No definido' END ILIKE '%%' || %(modalidad)s || '%%')
      AND (%(estado_grupo)s IS NULL OR
           CASE WHEN cp.visible = 0 THEN 'Oculto'
                WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
                WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
                ELSE 'En ejecución' END = %(estado_grupo)s)
      AND (%(rol_usuario)s IS NULL OR COALESCE(ruc.rol_shortnames, '') ILIKE '%%' || %(rol_usuario)s || '%%')
      AND (%(estado_usuario)s IS NULL OR
           CASE WHEN u.deleted = 1 THEN 'Eliminado'
                WHEN u.suspended = 1 THEN 'Suspendido'
                ELSE 'Activo' END = %(estado_usuario)s)
      AND (%(estado_aprendiz)s IS NULL OR 'No disponible (SOFIA Plus)' = %(estado_aprendiz)s)
      AND (%(origen_datos)s IS NULL OR
           CASE WHEN (cp.shortname ~ '^P_[0-9]+_' OR cp.shortname ~ '^[0-9]+P_[0-9]+_')
                THEN 'Integración' ELSE 'Manual' END = %(origen_datos)s)
      AND (%(fecha_inicio)s IS NULL OR TO_TIMESTAMP(cp.startdate)::date >= %(fecha_inicio)s::date)
      AND (%(fecha_fin)s IS NULL OR (cp.enddate > 0 AND TO_TIMESTAMP(cp.enddate)::date <= %(fecha_fin)s::date))
),
eventos AS (
    SELECT
        l.userid,
        l.courseid,
        l.contextinstanceid,
        l.timecreated,
        LEAD(l.timecreated) OVER (
            PARTITION BY l.userid, l.courseid ORDER BY l.timecreated
        ) AS siguiente_evento
    FROM public.mdl_logstore_standard_log l
    JOIN base_usuarios bu ON bu.userid = l.userid AND bu.courseid = l.courseid
    WHERE l.userid > 0
      AND l.courseid IS NOT NULL
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_hasta)s::date)
),
tiempos AS (
    SELECT
        userid,
        courseid,
        contextinstanceid,
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
        t.userid,
        t.courseid,
        CASE
            WHEN m.name = 'forum' AND mf.type = 'blog' THEN 'blog'
            WHEN m.name = 'forum' AND mf.type = 'news' THEN 'anuncio'
            WHEN m.name = 'forum' THEN 'foro'
            WHEN m.name IN ('attendance', 'attendanceregister') THEN 'asistencia'
            WHEN m.name IS NULL THEN 'curso'
            ELSE m.name
        END AS herramienta,
        t.segundos_estimados
    FROM tiempos t
    LEFT JOIN public.mdl_course_modules cm ON cm.id = t.contextinstanceid
    LEFT JOIN public.mdl_modules m ON m.id = cm.module
    LEFT JOIN public.mdl_forum mf ON mf.id = cm.instance AND m.name = 'forum'
),
pivot_tiempo AS (
    SELECT
        userid,
        courseid,
        SUM(segundos_estimados) AS seg_total,
        SUM(CASE WHEN herramienta = 'wiki' THEN segundos_estimados ELSE 0 END) AS seg_wiki,
        SUM(CASE WHEN herramienta IN ('feedback','survey') THEN segundos_estimados ELSE 0 END) AS seg_encuestas,
        SUM(CASE WHEN herramienta = 'foro' THEN segundos_estimados ELSE 0 END) AS seg_foros,
        SUM(CASE WHEN herramienta = 'quiz' THEN segundos_estimados ELSE 0 END) AS seg_evaluaciones,
        SUM(CASE WHEN herramienta = 'blog' THEN segundos_estimados ELSE 0 END) AS seg_blogs,
        SUM(CASE WHEN herramienta = 'assign' THEN segundos_estimados ELSE 0 END) AS seg_evidencias,
        SUM(CASE WHEN herramienta = 'scorm' THEN segundos_estimados ELSE 0 END) AS seg_scorm,
        SUM(CASE WHEN herramienta = 'bigbluebuttonbn' THEN segundos_estimados ELSE 0 END) AS seg_sesiones,
        SUM(CASE WHEN herramienta = 'chat' THEN segundos_estimados ELSE 0 END) AS seg_chats,
        SUM(CASE WHEN herramienta = 'asistencia' THEN segundos_estimados ELSE 0 END) AS seg_asistencia
    FROM modulo_tiempo
    GROUP BY userid, courseid
),
ingresos AS (
    SELECT
        userid,
        courseid,
        COUNT(DISTINCT timecreated) AS total_ingresos,
        MAX(TO_TIMESTAMP(timecreated)) AS ultimo_ingreso
    FROM public.mdl_logstore_standard_log
    WHERE action = 'viewed'
      AND userid > 0
      AND courseid IS NOT NULL
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(timecreated)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(timecreated)::date <= %(fecha_hasta)s::date)
    GROUP BY userid, courseid
)
SELECT
    COALESCE(reg.nombre, 'Regional ' || bu.codigo_regional, 'No definido') AS "Regional",
    COALESCE(bu.codigo_centro, 'No definido') AS "Código del centro",
    COALESCE(cen.nombre, 'Centro ' || bu.codigo_centro, 'No definido') AS "Nombre del centro",
    COALESCE(bu.codigo_programa, 'No definido') AS "Código del programa",
    COALESCE(bu.version_extraida, 'No definido') AS "Versión programa",
    COALESCE(NULLIF(bu.programa_formacion, ''), bu.nombre_ficha) AS "Nombre del programa de formación",
    CASE WHEN bu.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada' ELSE 'No definido' END AS "Nivel de formación",
    'No disponible (SOFIA Plus)' AS "Estado del Programa",
    bu.codigo_ficha AS "Código del grupo",
    TO_CHAR(TO_TIMESTAMP(bu.startdate), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha de inicio del grupo",
    CASE WHEN bu.enddate = 0 THEN 'No definida'
         ELSE TO_CHAR(TO_TIMESTAMP(bu.enddate), 'YYYY/MM/DD HH24:MI:SS')
    END AS "Fecha fin del grupo",
    COALESCE(bu.tipo_documento, 'No definido') AS "Tipo de Identificación",
    bu.documento AS "Identificación",
    bu.nombres_apellidos AS "Nombres y apellidos",
    bu.estado_usuario_grupo AS "Estado del usuario en el grupo",
    CASE
        WHEN bu.visible = 0 THEN 'Oculto'
        WHEN bu.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN bu.enddate > 0 AND bu.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado grupo",
    COALESCE(i.total_ingresos, 0) AS "Número de ingresos del usuario a grupo/ficha",
    CASE WHEN i.ultimo_ingreso IS NOT NULL
         THEN TO_CHAR(i.ultimo_ingreso, 'YYYY/MM/DD HH24:MI:SS')
         ELSE NULL
    END AS "Fecha del último ingreso grupo/ficha",
    ROUND(100.0 * pt.seg_wiki / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en wikis con participaciones del usuario",
    ROUND(100.0 * pt.seg_encuestas / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en encuestas realizadas por el usuario",
    ROUND(100.0 * pt.seg_foros / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en foros",
    ROUND(100.0 * pt.seg_evaluaciones / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en Pruebas de Conocimientos",
    ROUND(100.0 * pt.seg_blogs / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en blogs",
    ROUND(100.0 * pt.seg_evidencias / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en evidencias entregadas",
    ROUND(100.0 * pt.seg_scorm / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en scorm",
    ROUND(100.0 * pt.seg_sesiones / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en sesiones en línea",
    ROUND(100.0 * pt.seg_chats / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en chats",
    ROUND(100.0 * pt.seg_asistencia / NULLIF(pt.seg_total, 0), 2) AS "Porcentaje de tiempo en lista de asistencia",
    ROUND(pt.seg_total / 60.0, 2) AS "Total tiempo en grupo/ficha"
FROM pivot_tiempo pt
JOIN base_usuarios bu ON bu.userid = pt.userid AND bu.courseid = pt.courseid
LEFT JOIN ingresos i ON i.userid = bu.userid AND i.courseid = bu.courseid
LEFT JOIN midb.regionales reg ON reg.rgn_id = NULLIF(bu.codigo_regional, '')::bigint
LEFT JOIN midb.centros cen ON cen.sed_id = NULLIF(bu.codigo_centro, '')::bigint
WHERE pt.seg_total > 0
  AND (%(nombre_programa)s IS NULL OR COALESCE(NULLIF(bu.programa_formacion,''), bu.nombre_ficha) ILIKE '%%' || %(nombre_programa)s || '%%')
  AND (%(codigo_programa)s IS NULL OR COALESCE(bu.codigo_programa,'') ILIKE '%%' || %(codigo_programa)s || '%%')
  AND (%(nivel)s IS NULL OR CASE WHEN bu.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada' ELSE 'No definido' END ILIKE '%%' || %(nivel)s || '%%')
  AND (%(modalidad)s IS NULL OR
       CASE WHEN bu.letra_modalidad = 'V' THEN 'Titulada virtual'
            WHEN bu.letra_modalidad = 'A' THEN 'Titulada a distancia'
            WHEN bu.letra_modalidad IN ('P','PI') THEN 'Titulada presencial'
            ELSE 'No definido' END ILIKE '%%' || %(modalidad)s || '%%')
  AND (%(regional)s IS NULL OR COALESCE(reg.nombre, 'Regional ' || bu.codigo_regional, '') ILIKE '%%' || %(regional)s || '%%')
  AND (%(centro_formacion)s IS NULL OR COALESCE(cen.nombre, 'Centro ' || bu.codigo_centro, '') ILIKE '%%' || %(centro_formacion)s || '%%')
  AND (%(estado_grupo)s IS NULL OR
       CASE WHEN bu.visible = 0 THEN 'Oculto'
            WHEN bu.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
            WHEN bu.enddate > 0 AND bu.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
            ELSE 'En ejecución' END = %(estado_grupo)s)
  AND (%(rol_usuario)s IS NULL OR bu.rol_shortnames ILIKE '%%' || %(rol_usuario)s || '%%')
  AND (%(estado_usuario)s IS NULL OR bu.estado_usuario_lms = %(estado_usuario)s)
  AND (%(estado_aprendiz)s IS NULL OR 'No disponible (SOFIA Plus)' = %(estado_aprendiz)s)
  AND (%(origen_datos)s IS NULL OR
       CASE WHEN (bu.shortname ~ '^P_[0-9]+_' OR bu.shortname ~ '^[0-9]+P_[0-9]+_')
            THEN 'Integración' ELSE 'Manual' END = %(origen_datos)s)
  AND (%(fecha_inicio)s IS NULL OR TO_TIMESTAMP(bu.startdate)::date >= %(fecha_inicio)s::date)
  AND (%(fecha_fin)s IS NULL OR (bu.enddate > 0 AND TO_TIMESTAMP(bu.enddate)::date <= %(fecha_fin)s::date))
ORDER BY bu.codigo_ficha, bu.nombres_apellidos
