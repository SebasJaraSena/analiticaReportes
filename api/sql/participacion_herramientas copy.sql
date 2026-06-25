-- Reporte 1.7B: Participación por herramientas — por usuario y grupo/ficha.
-- SOFIA Plus no está integrado en esta base; sus estados se reportan como no disponibles.
WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber, c.shortname, c.fullname, c.category,
        c.visible, c.startdate, c.enddate,
        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$')          AS codigo_programa,
        TRIM(REGEXP_REPLACE(c.fullname, '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$', '')) AS programa_formacion,
        SUBSTRING(c.shortname FROM '_R_([0-9]+)')                              AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)')                              AS codigo_centro,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_([A-Za-z]+)_')             AS letra_modalidad,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_[A-Za-z]+_([0-9]+)')       AS version_extraida
    FROM public.mdl_course c
    WHERE c.id <> 1
),
base_matriculas AS (
    SELECT DISTINCT
        cp.courseid,
        cp.idnumber        AS codigo_ficha,
        cp.fullname        AS nombre_ficha,
        cp.codigo_programa,
        cp.version_extraida,
        cp.programa_formacion,
        cp.letra_modalidad,
        cp.codigo_regional,
        cp.codigo_centro,
        cp.category,
        cp.startdate, cp.enddate, cp.visible,
        cp.shortname,
        u.id               AS userid,
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
        STRING_AGG(DISTINCT COALESCE(NULLIF(r.name,''), r.shortname), ', ') AS rol_usuario,
        STRING_AGG(DISTINCT r.shortname, ', ') AS rol_shortnames,
        CASE WHEN ue.status = 0 THEN 'Activo' ELSE 'Inactivo' END AS estado_usuario_grupo,
        CASE
            WHEN u.deleted = 1 THEN 'Eliminado'
            WHEN u.suspended = 1 THEN 'Suspendido'
            ELSE 'Activo'
        END AS estado_usuario_lms
    FROM public.mdl_user_enrolments ue
    JOIN public.mdl_enrol e      ON e.id = ue.enrolid
    JOIN curso_parseado cp       ON cp.courseid = e.courseid
    JOIN public.mdl_user u       ON u.id = ue.userid
    LEFT JOIN public.mdl_context ctx ON ctx.instanceid = cp.courseid AND ctx.contextlevel = 50
    LEFT JOIN public.mdl_role_assignments ra ON ra.userid = u.id AND ra.contextid = ctx.id
    LEFT JOIN public.mdl_role r ON r.id = ra.roleid
    WHERE (%(codigo_ficha)s      IS NULL OR cp.idnumber ILIKE '%%' || %(codigo_ficha)s || '%%')
      AND (%(nombre_ficha)s      IS NULL OR cp.fullname ILIKE '%%' || %(nombre_ficha)s || '%%')
      AND (%(identificacion)s    IS NULL OR u.username ILIKE '%%' || %(identificacion)s || '%%')
      AND (%(nombres_apellidos)s IS NULL OR CONCAT(u.firstname,' ',u.lastname) ILIKE '%%' || %(nombres_apellidos)s || '%%')
    GROUP BY cp.courseid, cp.idnumber, cp.fullname, cp.codigo_programa, cp.version_extraida, cp.programa_formacion,
             cp.letra_modalidad, cp.codigo_regional, cp.codigo_centro, cp.category,
             cp.startdate, cp.enddate, cp.visible, cp.shortname,
             u.id, u.username, u.firstname, u.lastname, u.deleted, u.suspended, ue.status
),
ingresos AS (
    SELECT userid, courseid,
           COUNT(DISTINCT l.timecreated) AS total_ingresos,
           MAX(TO_TIMESTAMP(l.timecreated)) AS ultimo_ingreso
    FROM public.mdl_logstore_standard_log l
    WHERE l.action = 'viewed' AND l.userid > 0 AND l.courseid IS NOT NULL
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(l.timecreated)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(l.timecreated)::date <= %(fecha_hasta)s::date)
    GROUP BY userid, courseid
),
blogs AS (
    SELECT fp.userid, f.course AS courseid, COUNT(fp.id) AS total
    FROM public.mdl_forum_discussions fd
    JOIN public.mdl_forum_posts fp ON fp.discussion = fd.id AND fp.parent = 0
    JOIN public.mdl_forum f ON f.id = fd.forum
    WHERE f.type = 'blog' AND f.name ILIKE 'Blog%%'
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(fp.created)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(fp.created)::date <= %(fecha_hasta)s::date)
    GROUP BY fp.userid, f.course
),
evaluaciones AS (
    SELECT userid, courseid, COUNT(*) AS total
    FROM public.mdl_logstore_standard_log
    WHERE objecttable = 'quiz_attempts' AND target = 'attempt' AND action = 'submitted'
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(timecreated)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(timecreated)::date <= %(fecha_hasta)s::date)
    GROUP BY userid, courseid
),
evidencias AS (
    SELECT mas.userid, ma.course AS courseid, COUNT(DISTINCT mas.assignment) AS total
    FROM public.mdl_assign_submission mas
    JOIN public.mdl_assign ma ON ma.id = mas.assignment
    WHERE mas.status IN ('submitted','draft')
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(COALESCE(NULLIF(mas.timemodified, 0), mas.timecreated))::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(COALESCE(NULLIF(mas.timemodified, 0), mas.timecreated))::date <= %(fecha_hasta)s::date)
    GROUP BY mas.userid, ma.course
),
foros AS (
    SELECT mfd.userid, mf.course AS courseid, COUNT(DISTINCT mfd.id) AS total
    FROM public.mdl_forum_discussions mfd
    JOIN public.mdl_forum mf ON mf.id = mfd.forum
    WHERE mf.type NOT IN ('news','blog')
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(mfd.timemodified)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(mfd.timemodified)::date <= %(fecha_hasta)s::date)
    GROUP BY mfd.userid, mf.course
),
comentarios AS (
    SELECT mfp.userid, mf.course AS courseid, COUNT(DISTINCT mfp.id) AS total
    FROM public.mdl_forum_posts mfp
    JOIN public.mdl_forum_discussions mfd ON mfd.id = mfp.discussion
    JOIN public.mdl_forum mf ON mf.id = mfd.forum
    WHERE mf.type NOT IN ('news','blog')
      AND mfp.subject ILIKE 'Re:%%'
      AND (mf.name IS NULL OR mf.name NOT ILIKE 'ANUNCIOS')
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(mfp.created)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(mfp.created)::date <= %(fecha_hasta)s::date)
      AND NOT EXISTS (
          SELECT 1 FROM public.mdl_role_assignments r2
          JOIN public.mdl_context ctx2 ON r2.contextid = ctx2.id
          WHERE r2.userid = mfp.userid AND r2.roleid = 3
            AND ctx2.contextlevel = 50 AND ctx2.instanceid = mf.course
      )
    GROUP BY mfp.userid, mf.course
),
encuestas AS (
    SELECT userid, courseid, SUM(total) AS total
    FROM (
        SELECT mfc.userid, mf.course AS courseid, COUNT(DISTINCT mfc.id) AS total
        FROM public.mdl_feedback_completed mfc
        JOIN public.mdl_feedback mf ON mf.id = mfc.feedback
        WHERE (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(mfc.timemodified)::date >= %(fecha_desde)s::date)
          AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(mfc.timemodified)::date <= %(fecha_hasta)s::date)
        GROUP BY mfc.userid, mf.course
        UNION ALL
        SELECT msa.userid, ms.course AS courseid, COUNT(DISTINCT msa.id) AS total
        FROM public.mdl_survey_answers msa
        JOIN public.mdl_survey ms ON ms.id = msa.survey
        WHERE (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(msa.time)::date >= %(fecha_desde)s::date)
          AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(msa.time)::date <= %(fecha_hasta)s::date)
        GROUP BY msa.userid, ms.course
    ) x
    GROUP BY userid, courseid
),
wikis AS (
    SELECT userid, courseid, COUNT(*) AS total
    FROM public.mdl_logstore_standard_log
    WHERE component = 'mod_wiki' AND eventname ILIKE '%%page_updated%%'
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(timecreated)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(timecreated)::date <= %(fecha_hasta)s::date)
    GROUP BY userid, courseid
),
scorm AS (
    SELECT sa.userid, s.course AS courseid, COUNT(DISTINCT sa.id) AS total
    FROM public.mdl_scorm_attempt sa
    JOIN public.mdl_scorm s ON s.id = sa.scormid
    GROUP BY sa.userid, s.course
),
sesiones AS (
    SELECT bl.userid, b.course AS courseid, COUNT(DISTINCT b.id) AS total
    FROM public.mdl_bigbluebuttonbn_logs bl
    JOIN public.mdl_bigbluebuttonbn b ON b.id = bl.bigbluebuttonbnid
    WHERE (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(bl.timecreated)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(bl.timecreated)::date <= %(fecha_hasta)s::date)
    GROUP BY bl.userid, b.course
),
chats AS (
    SELECT cm.userid, c.course AS courseid, COUNT(DISTINCT cm.id) AS total
    FROM public.mdl_chat_messages cm
    JOIN public.mdl_chat c ON c.id = cm.chatid
    WHERE (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(cm.timestamp)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(cm.timestamp)::date <= %(fecha_hasta)s::date)
    GROUP BY cm.userid, c.course
),
anuncios AS (
    SELECT mfp.userid, mf.course AS courseid, COUNT(DISTINCT mfd.id) AS total
    FROM public.mdl_forum_posts mfp
    JOIN public.mdl_forum_discussions mfd ON mfd.id = mfp.discussion
    JOIN public.mdl_forum mf ON mf.id = mfd.forum
    WHERE mf.type = 'news'
      AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(mfp.created)::date >= %(fecha_desde)s::date)
      AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(mfp.created)::date <= %(fecha_hasta)s::date)
    GROUP BY mfp.userid, mf.course
)
SELECT
    COALESCE(reg.nombre, 'Regional ' || bm.codigo_regional, 'No definido') AS "Regional",
    COALESCE(bm.codigo_centro, 'No definido')                              AS "Código del centro",
    COALESCE(cen.nombre, 'Centro ' || bm.codigo_centro, 'No definido')     AS "Nombre del centro",
    COALESCE(bm.codigo_programa, 'No definido')                           AS "Código del programa",
    COALESCE(bm.version_extraida, 'No definido')                          AS "Versión programa",
    COALESCE(NULLIF(bm.programa_formacion, ''), bm.nombre_ficha)          AS "Nombre del programa de formación",
    CASE WHEN bm.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada' ELSE 'No definido' END
                                                                             AS "Nivel de formación",
    'No disponible (SOFIA Plus)'                                             AS "Estado del Programa",
    bm.codigo_ficha                                                          AS "Código del grupo",
    TO_CHAR(TO_TIMESTAMP(bm.startdate), 'YYYY/MM/DD HH24:MI:SS')             AS "Fecha de inicio del grupo",
    CASE WHEN bm.enddate = 0 THEN 'No definida'
         ELSE TO_CHAR(TO_TIMESTAMP(bm.enddate), 'YYYY/MM/DD HH24:MI:SS')
    END                                                                      AS "Fecha fin del grupo",
    COALESCE(bm.tipo_documento, 'No definido')                               AS "Tipo de Identificación",
    bm.documento                                                             AS "Identificación",
    bm.nombres_apellidos                                                     AS "Nombres y apellidos",
    bm.estado_usuario_grupo                                                  AS "Estado del usuario en el grupo",
    CASE
        WHEN bm.visible = 0 THEN 'Oculto'
        WHEN bm.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN bm.enddate > 0 AND bm.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END                                                                      AS "Estado grupo",
    COALESCE(i.total_ingresos, 0)                                            AS "Número de ingresos del usuario a grupo/ficha",
    CASE WHEN i.ultimo_ingreso IS NOT NULL
         THEN TO_CHAR(i.ultimo_ingreso, 'YYYY/MM/DD HH24:MI:SS')
         ELSE NULL
    END                                                                      AS "Fecha del último ingreso grupo/ficha",
    COALESCE(w.total, 0)                                                     AS "Número de wikis con participaciones del usuario",
    COALESCE(en.total, 0)                                                    AS "Número de encuestas realizadas por el usuario",
    COALESCE(fo.total, 0)                                                    AS "Número de participaciones del usuario en foros",
    COALESCE(co.total, 0)                                                    AS "Número de comentarios del usuario en foros",
    COALESCE(ev.total, 0)                                                    AS "Número de Pruebas de Conocimientos realizadas por el usuario",
    COALESCE(bl.total, 0)                                                    AS "Número de blogs con participaciones del usuario",
    COALESCE(evi.total, 0)                                                   AS "Número de evidencias entregadas por el usuario",
    COALESCE(sc.total, 0)                                                    AS "Número de scorm con participaciones del usuario",
    COALESCE(se.total, 0)                                                    AS "Número de sesiones en línea con participaciones del usuario",
    COALESCE(ch.total, 0)                                                    AS "Número de chats con participación del usuario",
    COALESCE(an.total, 0)                                                    AS "Número de anuncios con participaciones del usuario"
FROM base_matriculas bm
LEFT JOIN midb.regionales reg ON reg.rgn_id = NULLIF(bm.codigo_regional, '')::bigint
LEFT JOIN midb.centros cen    ON cen.sed_id = NULLIF(bm.codigo_centro, '')::bigint
LEFT JOIN ingresos i          ON i.userid = bm.userid  AND i.courseid = bm.courseid
LEFT JOIN blogs bl            ON bl.userid = bm.userid  AND bl.courseid = bm.courseid
LEFT JOIN evaluaciones ev     ON ev.userid = bm.userid AND ev.courseid = bm.courseid
LEFT JOIN evidencias evi      ON evi.userid = bm.userid AND evi.courseid = bm.courseid
LEFT JOIN foros fo            ON fo.userid = bm.userid  AND fo.courseid = bm.courseid
LEFT JOIN comentarios co      ON co.userid = bm.userid AND co.courseid = bm.courseid
LEFT JOIN encuestas en        ON en.userid = bm.userid  AND en.courseid = bm.courseid
LEFT JOIN wikis w             ON w.userid = bm.userid   AND w.courseid = bm.courseid
LEFT JOIN scorm sc            ON sc.userid = bm.userid  AND sc.courseid = bm.courseid
LEFT JOIN sesiones se         ON se.userid = bm.userid  AND se.courseid = bm.courseid
LEFT JOIN chats ch            ON ch.userid = bm.userid  AND ch.courseid = bm.courseid
LEFT JOIN anuncios an         ON an.userid = bm.userid  AND an.courseid = bm.courseid
WHERE (%(nombre_programa)s  IS NULL OR COALESCE(NULLIF(bm.programa_formacion,''), bm.nombre_ficha) ILIKE '%%' || %(nombre_programa)s || '%%')
  AND (%(codigo_programa)s  IS NULL OR COALESCE(bm.codigo_programa,'') ILIKE '%%' || %(codigo_programa)s || '%%')
  AND (%(nivel)s            IS NULL OR CASE WHEN bm.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada' ELSE 'No definido' END ILIKE '%%' || %(nivel)s || '%%')
  AND (%(modalidad)s        IS NULL OR
       CASE WHEN bm.letra_modalidad = 'V' THEN 'Titulada virtual'
            WHEN bm.letra_modalidad = 'A' THEN 'Titulada a distancia'
            WHEN bm.letra_modalidad IN ('P','PI') THEN 'Titulada presencial'
            ELSE 'No definido' END ILIKE '%%' || %(modalidad)s || '%%')
  AND (%(regional)s         IS NULL OR COALESCE(reg.nombre, 'Regional ' || bm.codigo_regional, '') ILIKE '%%' || %(regional)s || '%%')
  AND (%(centro_formacion)s IS NULL OR COALESCE(cen.nombre, 'Centro ' || bm.codigo_centro, '') ILIKE '%%' || %(centro_formacion)s || '%%')
  AND (%(estado_grupo)s     IS NULL OR
       CASE WHEN bm.visible = 0 THEN 'Oculto'
            WHEN bm.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
            WHEN bm.enddate > 0 AND bm.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
            ELSE 'En ejecución' END = %(estado_grupo)s)
  AND (%(rol_usuario)s      IS NULL OR bm.rol_shortnames ILIKE '%%' || %(rol_usuario)s || '%%')
  AND (%(estado_usuario)s   IS NULL OR bm.estado_usuario_lms = %(estado_usuario)s)
  AND (%(estado_aprendiz)s  IS NULL OR 'No disponible (SOFIA Plus)' = %(estado_aprendiz)s)
  AND (%(origen_datos)s     IS NULL OR
       CASE WHEN (bm.shortname ~ '^P_[0-9]+_' OR bm.shortname ~ '^[0-9]+P_[0-9]+_')
            THEN 'Integración' ELSE 'Manual' END = %(origen_datos)s)
  AND (%(fecha_inicio)s IS NULL OR TO_TIMESTAMP(bm.startdate)::date = %(fecha_inicio)s::date)
  AND (%(fecha_fin)s IS NULL OR (bm.enddate > 0 AND TO_TIMESTAMP(bm.enddate)::date = %(fecha_fin)s::date))
ORDER BY bm.codigo_ficha, bm.nombres_apellidos
