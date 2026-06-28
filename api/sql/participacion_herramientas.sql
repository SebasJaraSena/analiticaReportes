-- Reporte 1.7B: Participación por herramientas — por usuario y grupo/ficha.
-- Ajustes aplicados:
-- 2. Se quitaron del SELECT final las columnas no solicitadas.
-- 3. Foros y blogs ahora cuentan participaciones/interacciones, no solo creaciones.

WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber,
        c.shortname,
        c.fullname,
        c.category,
        c.visible,
        c.startdate,
        c.enddate,

        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$') AS codigo_programa,

        TRIM(
            REGEXP_REPLACE(
                c.fullname,
                '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$',
                ''
            )
        ) AS programa_formacion,

        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS codigo_centro,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_([A-Za-z]+)_') AS letra_modalidad,
        SUBSTRING(c.shortname FROM '^[0-9]*P_[0-9]+_[A-Za-z]+_([0-9]+)') AS version_extraida
    FROM public.mdl_course c
    WHERE c.id <> 1
),

matriculas_usuario_curso AS (
    SELECT
        e.courseid,
        ue.userid,

        BOOL_OR(
            ue.status = 0
            AND e.status = 0
        ) AS matricula_activa_lms,

        MIN(ue.timecreated) AS fecha_primera_matricula,
        MAX(ue.timemodified) AS fecha_ultima_actualizacion_matricula,
        MIN(NULLIF(ue.timestart, 0)) AS fecha_inicio_matricula,
        MAX(NULLIF(ue.timeend, 0)) AS fecha_fin_matricula

    FROM public.mdl_user_enrolments ue
    JOIN public.mdl_enrol e
        ON e.id = ue.enrolid
    GROUP BY
        e.courseid,
        ue.userid
),

roles_usuario_curso AS (
    SELECT
        ra.userid,
        ctx.instanceid AS courseid,

        STRING_AGG(
            DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname),
            ', '
        ) AS rol_usuario,

        STRING_AGG(
            DISTINCT r.shortname,
            ', '
        ) AS rol_shortnames

    FROM public.mdl_role_assignments ra
    JOIN public.mdl_context ctx
        ON ctx.id = ra.contextid
       AND ctx.contextlevel = 50
    JOIN public.mdl_role r
        ON r.id = ra.roleid
    GROUP BY
        ra.userid,
        ctx.instanceid
),

base_matriculas AS (
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
        cp.category,
        cp.startdate,
        cp.enddate,
        cp.visible,
        cp.shortname,

        u.id AS userid,
        COALESCE(NULLIF(u.idnumber, ''), u.username) AS identificacion_base,

        CASE
            WHEN LOWER(COALESCE(NULLIF(u.idnumber, ''), u.username)) ~ '(cc|dni|ce|ppt|ti|te)$'
            THEN UPPER(
                SUBSTRING(
                    LOWER(COALESCE(NULLIF(u.idnumber, ''), u.username))
                    FROM '(cc|dni|ce|ppt|ti|te)$'
                )
            )
            ELSE 'No definido'
        END AS tipo_documento,

        CASE
            WHEN LOWER(COALESCE(NULLIF(u.idnumber, ''), u.username)) ~ '(cc|dni|ce|ppt|ti|te)$'
            THEN REGEXP_REPLACE(
                COALESCE(NULLIF(u.idnumber, ''), u.username),
                '(cc|dni|ce|ppt|ti|te)$',
                '',
                'i'
            )
            ELSE COALESCE(NULLIF(u.idnumber, ''), u.username)
        END AS documento,

        CONCAT(u.firstname, ' ', u.lastname) AS nombres_apellidos,
        u.email,

        COALESCE(ruc.rol_usuario, 'Sin rol asignado') AS rol_usuario,
        COALESCE(ruc.rol_shortnames, '') AS rol_shortnames,

        CASE
            WHEN muc.matricula_activa_lms THEN 'Activo'
            ELSE 'Inactivo'
        END AS estado_usuario_grupo,

        CASE
            WHEN u.deleted = 1 THEN 'Eliminado'
            WHEN u.suspended = 1 THEN 'Suspendido'
            ELSE 'Activo'
        END AS estado_usuario_lms,

        muc.fecha_primera_matricula,
        muc.fecha_ultima_actualizacion_matricula,
        muc.fecha_inicio_matricula,
        muc.fecha_fin_matricula

    FROM matriculas_usuario_curso muc
    JOIN curso_parseado cp
        ON cp.courseid = muc.courseid
    JOIN public.mdl_user u
        ON u.id = muc.userid
    LEFT JOIN roles_usuario_curso ruc
        ON ruc.userid = u.id
       AND ruc.courseid = cp.courseid
    WHERE u.deleted = 0
),

ingresos_ava AS (
    SELECT
        l.userid,
        l.courseid,
        COUNT(l.id) AS total_ingresos,
        MAX(TO_TIMESTAMP(l.timecreated) AT TIME ZONE 'America/Bogota') AS ultimo_ingreso
    FROM public.mdl_logstore_standard_log l
    WHERE l.userid > 0
      AND l.courseid IS NOT NULL
      AND (
            l.eventname = E'\\core\\event\\course_viewed'
            OR (
                l.component = 'core'
                AND l.target = 'course'
                AND l.action = 'viewed'
            )
          )
      AND (%(fecha_desde)s IS NULL OR l.timecreated >= EXTRACT(EPOCH FROM %(fecha_desde)s::date AT TIME ZONE 'America/Bogota')::bigint)
      AND (%(fecha_hasta)s IS NULL OR l.timecreated < EXTRACT(EPOCH FROM ((%(fecha_hasta)s::date + 1) AT TIME ZONE 'America/Bogota'))::bigint)
    GROUP BY
        l.userid,
        l.courseid
),

blogs AS (
    SELECT
        fp.userid,
        f.course AS courseid,
        COUNT(DISTINCT fp.id) AS total
    FROM public.mdl_forum_discussions fd
    JOIN public.mdl_forum_posts fp
        ON fp.discussion = fd.id
    JOIN public.mdl_forum f
        ON f.id = fd.forum
    WHERE f.type = 'blog'
      AND fp.userid > 0
      AND (
            %(fecha_desde)s IS NULL
            OR (TO_TIMESTAMP(fp.created) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (TO_TIMESTAMP(fp.created) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        fp.userid,
        f.course
),

evaluaciones AS (
    SELECT
        qa.userid,
        q.course AS courseid,
        COUNT(qa.id) AS total
    FROM public.mdl_quiz_attempts qa
    JOIN public.mdl_quiz q
        ON q.id = qa.quiz
    WHERE qa.state = 'finished'
      AND qa.timefinish > 0
      AND (
            %(fecha_desde)s IS NULL
            OR (TO_TIMESTAMP(qa.timefinish) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (TO_TIMESTAMP(qa.timefinish) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        qa.userid,
        q.course
),

evidencias AS (
    SELECT
        mas.userid,
        ma.course AS courseid,
        COUNT(DISTINCT mas.assignment) AS total
    FROM public.mdl_assign_submission mas
    JOIN public.mdl_assign ma
        ON ma.id = mas.assignment
    WHERE mas.status = 'submitted'
      AND (
            %(fecha_desde)s IS NULL
            OR (
                TO_TIMESTAMP(
                    COALESCE(NULLIF(mas.timemodified, 0), mas.timecreated)
                ) AT TIME ZONE 'America/Bogota'
            )::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (
                TO_TIMESTAMP(
                    COALESCE(NULLIF(mas.timemodified, 0), mas.timecreated)
                ) AT TIME ZONE 'America/Bogota'
            )::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        mas.userid,
        ma.course
),

foros AS (
    SELECT
        mfp.userid,
        mf.course AS courseid,
        COUNT(DISTINCT mfp.id) AS total
    FROM public.mdl_forum_posts mfp
    JOIN public.mdl_forum_discussions mfd
        ON mfd.id = mfp.discussion
    JOIN public.mdl_forum mf
        ON mf.id = mfd.forum
    WHERE mf.type NOT IN ('news', 'blog')
      AND mfp.userid > 0
      AND (
            %(fecha_desde)s IS NULL
            OR (TO_TIMESTAMP(mfp.created) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (TO_TIMESTAMP(mfp.created) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        mfp.userid,
        mf.course
),

comentarios_foros AS (
    SELECT
        mfp.userid,
        mf.course AS courseid,
        COUNT(DISTINCT mfp.id) AS total
    FROM public.mdl_forum_posts mfp
    JOIN public.mdl_forum_discussions mfd
        ON mfd.id = mfp.discussion
    JOIN public.mdl_forum mf
        ON mf.id = mfd.forum
    WHERE mf.type NOT IN ('news', 'blog')
      AND mfp.parent > 0
      AND (
            %(fecha_desde)s IS NULL
            OR (TO_TIMESTAMP(mfp.created) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (TO_TIMESTAMP(mfp.created) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        mfp.userid,
        mf.course
),

encuestas AS (
    SELECT
        userid,
        courseid,
        SUM(total) AS total
    FROM (
        SELECT
            mfc.userid,
            mf.course AS courseid,
            COUNT(DISTINCT mfc.id) AS total
        FROM public.mdl_feedback_completed mfc
        JOIN public.mdl_feedback mf
            ON mf.id = mfc.feedback
        WHERE (
                %(fecha_desde)s IS NULL
                OR (TO_TIMESTAMP(mfc.timemodified) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
              )
          AND (
                %(fecha_hasta)s IS NULL
                OR (TO_TIMESTAMP(mfc.timemodified) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
              )
        GROUP BY
            mfc.userid,
            mf.course

        UNION ALL

        SELECT
            msa.userid,
            ms.course AS courseid,
            COUNT(DISTINCT msa.id) AS total
        FROM public.mdl_survey_answers msa
        JOIN public.mdl_survey ms
            ON ms.id = msa.survey
        WHERE (
                %(fecha_desde)s IS NULL
                OR (TO_TIMESTAMP(msa.time) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
              )
          AND (
                %(fecha_hasta)s IS NULL
                OR (TO_TIMESTAMP(msa.time) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
              )
        GROUP BY
            msa.userid,
            ms.course
    ) x
    GROUP BY
        userid,
        courseid
),

wikis AS (
    SELECT
        l.userid,
        l.courseid,
        COUNT(l.id) AS total
    FROM public.mdl_logstore_standard_log l
    WHERE l.component = 'mod_wiki'
      AND l.userid > 0
      AND l.courseid IS NOT NULL
      AND (
            l.eventname ILIKE '%%page_updated%%'
            OR l.action IN ('created', 'updated')
          )
      AND (%(fecha_desde)s IS NULL OR l.timecreated >= EXTRACT(EPOCH FROM %(fecha_desde)s::date AT TIME ZONE 'America/Bogota')::bigint)
      AND (%(fecha_hasta)s IS NULL OR l.timecreated < EXTRACT(EPOCH FROM ((%(fecha_hasta)s::date + 1) AT TIME ZONE 'America/Bogota'))::bigint)
    GROUP BY
        l.userid,
        l.courseid
),

scorm AS (
    SELECT
        l.userid,
        l.courseid,
        COUNT(DISTINCT COALESCE(l.contextinstanceid, l.objectid, l.id)) AS total
    FROM public.mdl_logstore_standard_log l
    WHERE l.userid > 0
      AND l.courseid IS NOT NULL
      AND l.component = 'mod_scorm'
      AND (
            l.action IN ('viewed', 'launched', 'submitted', 'completed', 'updated')
            OR l.eventname ILIKE '%%scorm%%'
          )
      AND (%(fecha_desde)s IS NULL OR l.timecreated >= EXTRACT(EPOCH FROM %(fecha_desde)s::date AT TIME ZONE 'America/Bogota')::bigint)
      AND (%(fecha_hasta)s IS NULL OR l.timecreated < EXTRACT(EPOCH FROM ((%(fecha_hasta)s::date + 1) AT TIME ZONE 'America/Bogota'))::bigint)
    GROUP BY
        l.userid,
        l.courseid
),

sesiones_linea AS (
    SELECT
        bl.userid,
        b.course AS courseid,
        COUNT(DISTINCT b.id) AS total
    FROM public.mdl_bigbluebuttonbn_logs bl
    JOIN public.mdl_bigbluebuttonbn b
        ON b.id = bl.bigbluebuttonbnid
    WHERE bl.userid > 0
      AND (
            %(fecha_desde)s IS NULL
            OR (TO_TIMESTAMP(bl.timecreated) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (TO_TIMESTAMP(bl.timecreated) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        bl.userid,
        b.course
),

chats AS (
    SELECT
        cm.userid,
        c.course AS courseid,
        COUNT(DISTINCT cm.id) AS total
    FROM public.mdl_chat_messages cm
    JOIN public.mdl_chat c
        ON c.id = cm.chatid
    WHERE cm.userid > 0
      AND (
            %(fecha_desde)s IS NULL
            OR (TO_TIMESTAMP(cm.timestamp) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (TO_TIMESTAMP(cm.timestamp) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        cm.userid,
        c.course
),

anuncios AS (
    SELECT
        mfp.userid,
        mf.course AS courseid,
        COUNT(DISTINCT mfp.id) AS total
    FROM public.mdl_forum_posts mfp
    JOIN public.mdl_forum_discussions mfd
        ON mfd.id = mfp.discussion
    JOIN public.mdl_forum mf
        ON mf.id = mfd.forum
    WHERE mf.type = 'news'
      AND (
            %(fecha_desde)s IS NULL
            OR (TO_TIMESTAMP(mfp.created) AT TIME ZONE 'America/Bogota')::date >= %(fecha_desde)s::date
          )
      AND (
            %(fecha_hasta)s IS NULL
            OR (TO_TIMESTAMP(mfp.created) AT TIME ZONE 'America/Bogota')::date <= %(fecha_hasta)s::date
          )
    GROUP BY
        mfp.userid,
        mf.course
)

SELECT
    COALESCE(reg.nombre, 'Regional ' || bm.codigo_regional, 'No definido') AS "Regional",
    COALESCE(bm.codigo_centro, 'No definido') AS "Código del centro",
    COALESCE(cen.nombre, 'Centro ' || bm.codigo_centro, 'No definido') AS "Nombre del centro",

    COALESCE(bm.codigo_programa, 'No definido') AS "Código del programa",
    COALESCE(bm.version_extraida, 'No definido') AS "Versión programa",
    COALESCE(NULLIF(bm.programa_formacion, ''), bm.nombre_ficha) AS "Nombre del programa de formación",

    CASE
        WHEN bm.letra_modalidad IN ('V', 'A', 'P', 'PI') THEN 'Formación titulada'
        ELSE 'No definido'
    END AS "Nivel de formación",

    'No disponible (SOFIA Plus)' AS "Estado del Programa",

    bm.codigo_ficha AS "Código del grupo",

    CASE
        WHEN bm.startdate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(bm.startdate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha de inicio del grupo",

    CASE
        WHEN bm.enddate = 0 THEN 'No definida'
        ELSE TO_CHAR(
            TO_TIMESTAMP(bm.enddate) AT TIME ZONE 'America/Bogota',
            'YYYY/MM/DD HH24:MI:SS'
        )
    END AS "Fecha fin del grupo",

    bm.tipo_documento AS "Tipo de Identificación",
    bm.documento AS "Identificación",
    bm.nombres_apellidos AS "Nombres y apellidos",

    bm.estado_usuario_grupo AS "Estado del usuario en el grupo",

    CASE
        WHEN bm.visible = 0 THEN 'Oculto'
        WHEN bm.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN bm.enddate > 0 AND bm.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado grupo/ficha LMS",

    COALESCE(i.total_ingresos, 0) AS "Número de ingresos del usuario al AVA",

    CASE
        WHEN i.ultimo_ingreso IS NOT NULL
        THEN TO_CHAR(i.ultimo_ingreso, 'YYYY/MM/DD HH24:MI:SS')
        ELSE 'Sin ingreso registrado'
    END AS "Fecha del último ingreso al AVA",

    COALESCE(w.total, 0) AS "Número de participaciones del usuario en wikis",
    COALESCE(en.total, 0) AS "Número de encuestas realizadas por el usuario",
    COALESCE(fo.total, 0) AS "Número de foros creados por el usuario",
    COALESCE(co.total, 0) AS "Número de comentarios del usuario en foros",
    COALESCE(ev.total, 0) AS "Número de pruebas de conocimiento realizadas por el usuario",
    COALESCE(bl.total, 0) AS "Número de blogs creados por el usuario",
    COALESCE(evi.total, 0) AS "Número de evidencias entregadas por el usuario",
    COALESCE(sc.total, 0) AS "Número de participaciones del usuario en SCORM",
    COALESCE(se.total, 0) AS "Número de sesiones en línea con participación del usuario",
    COALESCE(ch.total, 0) AS "Número de chats con participación del usuario",
    COALESCE(an.total, 0) AS "Número de anuncios con participación del usuario"

FROM base_matriculas bm

LEFT JOIN midb.regionales reg
    ON reg.rgn_id = NULLIF(bm.codigo_regional, '')::bigint

LEFT JOIN midb.centros cen
    ON cen.sed_id = NULLIF(bm.codigo_centro, '')::bigint

LEFT JOIN ingresos_ava i
    ON i.userid = bm.userid
   AND i.courseid = bm.courseid

LEFT JOIN blogs bl
    ON bl.userid = bm.userid
   AND bl.courseid = bm.courseid

LEFT JOIN evaluaciones ev
    ON ev.userid = bm.userid
   AND ev.courseid = bm.courseid

LEFT JOIN evidencias evi
    ON evi.userid = bm.userid
   AND evi.courseid = bm.courseid

LEFT JOIN foros fo
    ON fo.userid = bm.userid
   AND fo.courseid = bm.courseid

LEFT JOIN comentarios_foros co
    ON co.userid = bm.userid
   AND co.courseid = bm.courseid

LEFT JOIN encuestas en
    ON en.userid = bm.userid
   AND en.courseid = bm.courseid

LEFT JOIN wikis w
    ON w.userid = bm.userid
   AND w.courseid = bm.courseid

LEFT JOIN scorm sc
    ON sc.userid = bm.userid
   AND sc.courseid = bm.courseid

LEFT JOIN sesiones_linea se
    ON se.userid = bm.userid
   AND se.courseid = bm.courseid

LEFT JOIN chats ch
    ON ch.userid = bm.userid
   AND ch.courseid = bm.courseid

LEFT JOIN anuncios an
    ON an.userid = bm.userid
   AND an.courseid = bm.courseid

WHERE (%(nombre_programa)s IS NULL OR COALESCE(NULLIF(bm.programa_formacion, ''), bm.nombre_ficha) ILIKE '%%' || %(nombre_programa)s || '%%')

  AND (%(codigo_programa)s IS NULL OR COALESCE(bm.codigo_programa, '') ILIKE '%%' || %(codigo_programa)s || '%%')

  AND (%(codigo_ficha)s IS NULL OR bm.codigo_ficha ILIKE '%%' || %(codigo_ficha)s || '%%')

  AND (%(nombre_ficha)s IS NULL OR bm.nombre_ficha ILIKE '%%' || %(nombre_ficha)s || '%%')

  AND (
        %(nivel)s IS NULL
        OR CASE
            WHEN bm.letra_modalidad IN ('V', 'A', 'P', 'PI') THEN 'Formación titulada'
            ELSE 'No definido'
           END = ANY(%(nivel)s::text[])
      )

  AND (
        %(modalidad)s IS NULL
        OR CASE
            WHEN bm.letra_modalidad = 'V' THEN 'Titulada virtual'
            WHEN bm.letra_modalidad = 'A' THEN 'Titulada a distancia'
            WHEN bm.letra_modalidad IN ('P', 'PI') THEN 'Titulada presencial'
            ELSE 'No definido'
           END = ANY(%(modalidad)s::text[])
      )

  AND (
        %(regional)s IS NULL
        OR COALESCE(reg.nombre, 'Regional ' || bm.codigo_regional, '') ILIKE '%%' || %(regional)s || '%%'
      )

  AND (
        %(centro_formacion)s IS NULL
        OR COALESCE(cen.nombre, 'Centro ' || bm.codigo_centro, '') ILIKE '%%' || %(centro_formacion)s || '%%'
      )

  AND (
        %(estado_grupo)s IS NULL
        OR CASE
            WHEN bm.visible = 0 THEN 'Oculto'
            WHEN bm.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
            WHEN bm.enddate > 0 AND bm.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
            ELSE 'En ejecución'
           END = %(estado_grupo)s
      )

  AND (
        %(rol_usuario)s IS NULL
        OR EXISTS (SELECT 1 FROM unnest(string_to_array(bm.rol_shortnames, ',')) AS _r(role)
                   WHERE trim(_r.role) = ANY(%(rol_usuario)s::text[]))
        OR EXISTS (SELECT 1 FROM unnest(string_to_array(bm.rol_usuario, ',')) AS _r(role)
                   WHERE trim(_r.role) = ANY(%(rol_usuario)s::text[]))
      )

  AND (
        %(estado_usuario)s IS NULL
        OR bm.estado_usuario_lms = %(estado_usuario)s
      )

  AND (
        %(estado_aprendiz)s IS NULL
        OR bm.estado_usuario_grupo = %(estado_aprendiz)s
      )

  AND (
        %(identificacion)s IS NULL
        OR bm.identificacion_base ILIKE '%%' || %(identificacion)s || '%%'
        OR bm.documento ILIKE '%%' || %(identificacion)s || '%%'
      )

  AND (
        %(nombres_apellidos)s IS NULL
        OR bm.nombres_apellidos ILIKE '%%' || %(nombres_apellidos)s || '%%'
      )

  AND (
        %(origen_datos)s IS NULL
        OR CASE
            WHEN bm.shortname ~ '^P_[0-9]+_'
              OR bm.shortname ~ '^[0-9]+P_[0-9]+_'
            THEN 'Integración'
            ELSE 'Manual'
           END = %(origen_datos)s
      )

  AND (
        %(fecha_inicio)s IS NULL
        OR TO_TIMESTAMP(bm.startdate)::date >= %(fecha_inicio)s::date
      )

  AND (
        %(fecha_fin)s IS NULL
        OR (
            bm.enddate > 0
            AND TO_TIMESTAMP(bm.enddate)::date <= %(fecha_fin)s::date
        )
      )

ORDER BY
    bm.codigo_ficha,
    bm.nombres_apellidos