-- ============================================================
-- 1.1. Registro de usuarios
-- Reporte completo de usuarios matriculados en los grupos/fichas sin importar rol. Incluye ingresos únicos por día; si no tiene ingresos, muestra 0.
-- ============================================================
WITH "curso_parseado" AS (
    SELECT
        c.id AS "courseid",
        c.idnumber,
        c.shortname,
        c.fullname,
        c.category,
        c.visible,
        c.startdate,
        c.enddate,
        c.timecreated,
        SUBSTRING(c.shortname FROM '^P_([0-9]+)_') AS "codigo_programa_extraido",
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS "regional_extraida",
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS "centro_extraido"
    FROM "mdl_course" c
    WHERE c.id <> 1
),
"semillas" AS (
    SELECT
        4 AS "categoria_origen",
        s.code::text AS "codigo_programa",
        s.program_type,
        s.education_level,
        s.prog_name,
        s.design_version,
        s.seed_version,
        s.current_version,
        s.modality,
        s.status_seed,
        s.lms_id
    FROM "INTEGRACION"."SEEDS" s
    WHERE s.status_seed = 'A'

    UNION ALL

    SELECT
        6 AS "categoria_origen",
        s.code::text AS "codigo_programa",
        s.program_type,
        s.education_level,
        s.prog_name,
        s.design_version,
        s.seed_version,
        s.current_version,
        s.modality,
        s.status_seed,
        s.lms_id
    FROM "INTEGRACION"."SEEDS_INDUCTION" s
    WHERE s.status_seed = 'A'
),
"campos_usuario" AS (
    SELECT
        uid.userid,
        MAX(CASE WHEN uif.shortname IN ('tipo_documento', 'tipodocumento', 'tipo_doc', 'tipoidentificacion', 'tipo_identificacion') THEN uid.data END) AS "tipo_documento",
        MAX(CASE WHEN uif.shortname IN ('documento', 'numero_documento', 'identificacion', 'cedula', 'numero_identificacion') THEN uid.data END) AS "documento"
    FROM "mdl_user_info_data" uid
    JOIN "mdl_user_info_field" uif ON uif.id = uid.fieldid
    GROUP BY uid.userid
),
"roles_usuario_curso" AS (
    SELECT
        ra.userid,
        ctx.instanceid AS "courseid",
        STRING_AGG(DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname), ', ') AS "rol_usuario"
    FROM "mdl_role_assignments" ra
    JOIN "mdl_context" ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
    JOIN "mdl_role" r ON r.id = ra.roleid
    GROUP BY ra.userid, ctx.instanceid
),
"ingresos_curso" AS (
    SELECT
        l.userid,
        l.courseid,
        COUNT(DISTINCT DATE(TO_TIMESTAMP(l.timecreated))) AS "total_dias_ingreso",
        COUNT(*) AS "total_ingresos",
        MIN(l.timecreated) AS "fecha_primer_acceso_grupo",
        MAX(l.timecreated) AS "fecha_ultimo_acceso_grupo"
    FROM "mdl_logstore_standard_log" l
    WHERE l.userid > 0
      AND l.courseid IS NOT NULL
      AND l.action = 'viewed'
    GROUP BY l.userid, l.courseid
)
SELECT
    cp.idnumber AS "Código de grupo/ficha",
    cp.fullname AS "Nombre grupo/ficha en el LMS",
    COALESCE(s.education_level, 'No definido') AS "Nivel del grupo/ficha",
    COALESCE(s.modality, 'No definido') AS "Modalidad",
    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado del grupo/ficha",
    COALESCE(s.codigo_programa, cp."codigo_programa_extraido", 'No definido') AS "Codigo Programa de Formación",
    COALESCE(s.current_version::text, s.design_version::text, s.seed_version::text, 'No definido') AS "Versión Programa de Formación",
    COALESCE(s.prog_name, 'No definido') AS "Programa de formación",
    TO_CHAR(TO_TIMESTAMP(cp.startdate), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha de inicio de grupo/ficha",
    CASE WHEN cp.enddate IS NULL OR cp.enddate = 0 THEN 'No definida' ELSE TO_CHAR(TO_TIMESTAMP(cp.enddate), 'YYYY/MM/DD HH24:MI:SS') END AS "Fecha fin de grupo/ficha",
    COALESCE(cp."regional_extraida", 'No definido') AS "Regional",
    COALESCE(cp."centro_extraido", 'No definido') AS "Centro de Formación",
    COALESCE(ru."rol_usuario", 'Sin rol asignado') AS "Rol de usuario",
    COALESCE(cu."tipo_documento", 'No definido') AS "Tipo de Documento",
    COALESCE(cu."documento", u.username) AS "Documento",
    CONCAT(u.firstname, ' ', u.lastname) AS "Nombres y apellidos",
    CASE WHEN ic."fecha_primer_acceso_grupo" IS NULL THEN 'Sin acceso' ELSE TO_CHAR(TO_TIMESTAMP(ic."fecha_primer_acceso_grupo"), 'YYYY/MM/DD HH24:MI:SS') END AS "Fecha de acceso al grupo/ficha",
    CASE WHEN u.lastaccess IS NULL OR u.lastaccess = 0 THEN 'Sin acceso' ELSE TO_CHAR(TO_TIMESTAMP(u.lastaccess), 'YYYY/MM/DD HH24:MI:SS') END AS "Fecha de ultimo acceso al LMS",
    COALESCE(ic."total_dias_ingreso", 0) AS "Total días que Ingresó",
    COALESCE(ic."total_ingresos", 0) AS "Total ingresos al grupo/ficha"
FROM "mdl_user_enrolments" ue
JOIN "mdl_enrol" e ON e.id = ue.enrolid
JOIN "curso_parseado" cp ON cp."courseid" = e.courseid
JOIN "mdl_user" u ON u.id = ue.userid
LEFT JOIN "semillas" s ON s."codigo_programa" = cp."codigo_programa_extraido" AND s."categoria_origen" = cp.category
LEFT JOIN "campos_usuario" cu ON cu.userid = u.id
LEFT JOIN "roles_usuario_curso" ru ON ru.userid = u.id AND ru."courseid" = cp."courseid"
LEFT JOIN "ingresos_curso" ic ON ic.userid = u.id AND ic.courseid = cp."courseid"
WHERE u.deleted = 0
ORDER BY cp.fullname, "Rol de usuario", "Nombres y apellidos";


-- ============================================================
-- 1.2. Ingresos por navegador, ubicación y sistema
-- Moodle estándar no guarda user-agent, sistema operativo, navegador, país ni ciudad en mdl_logstore_standard_log. La consulta deja esos campos como no disponibles y entrega IP, origen, fecha/hora e ingresos únicos.
-- ============================================================
SELECT
    EXTRACT(YEAR FROM TO_TIMESTAMP(l.timecreated))::int AS "Año",
    EXTRACT(MONTH FROM TO_TIMESTAMP(l.timecreated))::int AS "Mes",
    EXTRACT(WEEK FROM TO_TIMESTAMP(l.timecreated))::int AS "Semana del año",
    TO_CHAR(TO_TIMESTAMP(l.timecreated), 'HH24:00:00') AS "Hora",
    'No disponible en Moodle estándar' AS "Sistema operativo",
    'No disponible en Moodle estándar' AS "Navegador web",
    'No disponible en Moodle estándar' AS "Pais",
    'No disponible en Moodle estándar' AS "Ciudad",
    COALESCE(l.ip, 'Sin IP') AS "IP",
    COALESCE(l.origin, 'Sin origen') AS "Origen acceso",
    COUNT(*) AS "Total ingresos",
    COUNT(DISTINCT l.userid) AS "Usuarios únicos"
FROM "mdl_logstore_standard_log" l
JOIN "mdl_user" u ON u.id = l.userid
WHERE l.userid > 0
  AND u.deleted = 0
  AND l.action = 'viewed'
GROUP BY
    EXTRACT(YEAR FROM TO_TIMESTAMP(l.timecreated)),
    EXTRACT(MONTH FROM TO_TIMESTAMP(l.timecreated)),
    EXTRACT(WEEK FROM TO_TIMESTAMP(l.timecreated)),
    TO_CHAR(TO_TIMESTAMP(l.timecreated), 'HH24:00:00'),
    COALESCE(l.ip, 'Sin IP'),
    COALESCE(l.origin, 'Sin origen')
ORDER BY "Año" DESC, "Mes" DESC, "Semana del año" DESC, "Hora" DESC;


-- ============================================================
-- 1.3. Matrículas LMS
-- Usuarios enrolados por grupo/ficha con rol, estado y fecha de matrícula. Usa INTEGRACION para completar programa, nivel y modalidad.
-- ============================================================
WITH "curso_parseado" AS (
    SELECT
        c.id AS "courseid", c.idnumber, c.shortname, c.fullname, c.category, c.visible, c.startdate, c.enddate,
        SUBSTRING(c.shortname FROM '^P_([0-9]+)_') AS "codigo_programa_extraido",
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS "regional_extraida",
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS "centro_extraido"
    FROM "mdl_course" c
    WHERE c.id <> 1
),
"semillas" AS (
    SELECT 4 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.current_version, s.design_version, s.seed_version, s.modality
    FROM "INTEGRACION"."SEEDS" s
    WHERE s.status_seed = 'A'
    UNION ALL
    SELECT 6 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.current_version, s.design_version, s.seed_version, s.modality
    FROM "INTEGRACION"."SEEDS_INDUCTION" s
    WHERE s.status_seed = 'A'
),
"roles_usuario_curso" AS (
    SELECT
        ra.userid,
        ctx.instanceid AS "courseid",
        STRING_AGG(DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname), ', ') AS "rol_usuario"
    FROM "mdl_role_assignments" ra
    JOIN "mdl_context" ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
    JOIN "mdl_role" r ON r.id = ra.roleid
    GROUP BY ra.userid, ctx.instanceid
)
SELECT
    cp.idnumber AS "Código grupo/ficha",
    cp.fullname AS "Nombre grupo/ficha en el LMS",
    COALESCE(s.education_level, 'No definido') AS "Nivel del programa",
    COALESCE(s.modality, 'No definido') AS "Modalidad",
    COALESCE(cp."regional_extraida", 'No definido') AS "Regional",
    COALESCE(cp."centro_extraido", 'No definido') AS "Centro de Formación",
    COALESCE(cp."codigo_programa_extraido", s."codigo_programa", 'No definido') AS "Código Programa de Formación",
    COALESCE(s.current_version::text, s.design_version::text, s.seed_version::text, 'No definido') AS "Versión Programa de Formación",
    COALESCE(s.prog_name, 'No definido') AS "Programa de formación",
    TO_CHAR(TO_TIMESTAMP(cp.startdate), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha de inicio grupo/ficha",
    CASE WHEN cp.enddate = 0 THEN 'No definida' ELSE TO_CHAR(TO_TIMESTAMP(cp.enddate), 'YYYY/MM/DD HH24:MI:SS') END AS "Fecha fin de grupo/ficha",
    u.username AS "Documento",
    CONCAT(u.firstname, ' ', u.lastname) AS "Nombres y apellidos",
    u.email AS "Correo",
    COALESCE(ru."rol_usuario", 'Sin rol asignado') AS "Rol de usuario",
    CASE WHEN ue.status = 0 THEN 'Activo' ELSE 'Suspendido' END AS "Estado matrícula",
    TO_CHAR(TO_TIMESTAMP(ue.timecreated), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha matrícula",
    TO_CHAR(TO_TIMESTAMP(ue.timemodified), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha actualización matrícula"
FROM "mdl_user_enrolments" ue
JOIN "mdl_enrol" e ON e.id = ue.enrolid
JOIN "curso_parseado" cp ON cp."courseid" = e.courseid
JOIN "mdl_user" u ON u.id = ue.userid
LEFT JOIN "semillas" s ON s."codigo_programa" = cp."codigo_programa_extraido" AND s."categoria_origen" = cp.category
LEFT JOIN "roles_usuario_curso" ru ON ru.userid = u.id AND ru."courseid" = cp."courseid"
WHERE u.deleted = 0
ORDER BY cp.fullname, "Rol de usuario", "Nombres y apellidos";


-- ============================================================
-- 1.4. Usuarios por ambiente
-- La base actual es zajuna. Si producción, pruebas y entrenamiento están en bases separadas, cambia el literal Ambiente o ejecuta esta consulta en cada base.
-- ============================================================
SELECT
    'ZAJUNA' AS "Ambiente",
    EXTRACT(YEAR FROM TO_TIMESTAMP(u.timecreated))::int AS "Año",
    EXTRACT(MONTH FROM TO_TIMESTAMP(u.timecreated))::int AS "Mes",
    CASE
        WHEN u.auth = 'manual' THEN 'Manual'
        ELSE 'Integración / Externo'
    END AS "Origen de datos",
    COUNT(*) AS "Total usuarios",
    COUNT(*) FILTER (WHERE u.deleted = 0 AND u.suspended = 0) AS "Usuarios activos",
    COUNT(*) FILTER (WHERE u.suspended = 1) AS "Usuarios suspendidos",
    COUNT(*) FILTER (WHERE u.deleted = 1) AS "Usuarios eliminados"
FROM "mdl_user" u
WHERE u.id > 2
GROUP BY
    EXTRACT(YEAR FROM TO_TIMESTAMP(u.timecreated)),
    EXTRACT(MONTH FROM TO_TIMESTAMP(u.timecreated)),
    CASE WHEN u.auth = 'manual' THEN 'Manual' ELSE 'Integración / Externo' END
ORDER BY "Año" DESC, "Mes" DESC, "Origen de datos";


-- ============================================================
-- 1.5. Fichas y programas de formación
-- Listado de cursos/fichas creadas para programas. Usa el shortname del curso para programa, regional y centro, y SEEDS/SEEDS_INDUCTION para nombre del programa, modalidad y nivel.
-- ============================================================
WITH "curso_parseado" AS (
    SELECT
        c.id AS "courseid", c.idnumber, c.shortname, c.fullname, c.category, c.visible, c.startdate, c.enddate, c.timecreated,
        SUBSTRING(c.shortname FROM '^P_([0-9]+)_') AS "codigo_programa_extraido",
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS "regional_extraida",
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS "centro_extraido"
    FROM "mdl_course" c
    WHERE c.id <> 1
),
"semillas" AS (
    SELECT 4 AS "categoria_origen", s.code::text AS "codigo_programa", s.program_type, s.education_level, s.prog_name, s.current_version, s.design_version, s.seed_version, s.modality
    FROM "INTEGRACION"."SEEDS" s
    WHERE s.status_seed = 'A'
    UNION ALL
    SELECT 6 AS "categoria_origen", s.code::text AS "codigo_programa", s.program_type, s.education_level, s.prog_name, s.current_version, s.design_version, s.seed_version, s.modality
    FROM "INTEGRACION"."SEEDS_INDUCTION" s
    WHERE s.status_seed = 'A'
),
"roles_por_curso" AS (
    SELECT
        ctx.instanceid AS "courseid",
        COUNT(DISTINCT ra.userid) FILTER (WHERE r.shortname IN ('student')) AS "total_aprendices",
        COUNT(DISTINCT ra.userid) FILTER (WHERE r.shortname IN ('teacher', 'editingteacher')) AS "total_instructores",
        COUNT(DISTINCT ra.userid) AS "total_usuarios_con_rol"
    FROM "mdl_role_assignments" ra
    JOIN "mdl_context" ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
    JOIN "mdl_role" r ON r.id = ra.roleid
    GROUP BY ctx.instanceid
)
SELECT
    cp.idnumber AS "Código grupo/ficha",
    cp.fullname AS "Nombre grupo/ficha en el LMS",
    COALESCE(s.education_level, 'No definido') AS "Nivel del grupo/ficha",
    COALESCE(s.modality, 'No definido') AS "Modalidad",
    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END AS "Estado del grupo/ficha",
    COALESCE(cp."codigo_programa_extraido", s."codigo_programa", 'No definido') AS "Código Programa de Formación",
    COALESCE(s.current_version::text, s.design_version::text, s.seed_version::text, 'No definido') AS "Versión Programa de Formación",
    COALESCE(s.prog_name, 'No definido') AS "Programa de formación",
    COALESCE(cp."regional_extraida", 'No definido') AS "Regional",
    COALESCE(cp."centro_extraido", 'No definido') AS "Centro de Formación",
    TO_CHAR(TO_TIMESTAMP(cp.timecreated), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha creación curso LMS",
    TO_CHAR(TO_TIMESTAMP(cp.startdate), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha inicio grupo/ficha",
    CASE WHEN cp.enddate = 0 THEN 'No definida' ELSE TO_CHAR(TO_TIMESTAMP(cp.enddate), 'YYYY/MM/DD HH24:MI:SS') END AS "Fecha fin grupo/ficha",
    COALESCE(rpc."total_aprendices", 0) AS "Total aprendices",
    COALESCE(rpc."total_instructores", 0) AS "Total instructores",
    COALESCE(rpc."total_usuarios_con_rol", 0) AS "Total usuarios con rol"
FROM "curso_parseado" cp
LEFT JOIN "semillas" s ON s."codigo_programa" = cp."codigo_programa_extraido" AND s."categoria_origen" = cp.category
LEFT JOIN "roles_por_curso" rpc ON rpc."courseid" = cp."courseid"
ORDER BY cp.timecreated DESC, cp.fullname;


-- ============================================================
-- 1.6. Tráfico diario de usuarios
-- Suma de ingresos únicos por usuario por día. El origen de datos se aproxima por el patrón del shortname del curso.
-- ============================================================
SELECT
    DATE(TO_TIMESTAMP(l.timecreated)) AS "Fecha",
    CASE
        WHEN c.shortname ~ '^P_[0-9]+_.*_R_[0-9]+_C_[0-9]+' THEN 'Integración'
        ELSE 'Manual'
    END AS "Origen de datos",
    COUNT(*) AS "Total eventos",
    COUNT(DISTINCT l.userid) AS "Usuarios únicos",
    COUNT(DISTINCT l.courseid) AS "Grupos/fichas con actividad"
FROM "mdl_logstore_standard_log" l
JOIN "mdl_user" u ON u.id = l.userid
JOIN "mdl_course" c ON c.id = l.courseid
WHERE l.userid > 0
  AND u.deleted = 0
  AND l.action = 'viewed'
  AND l.courseid IS NOT NULL
GROUP BY
    DATE(TO_TIMESTAMP(l.timecreated)),
    CASE WHEN c.shortname ~ '^P_[0-9]+_.*_R_[0-9]+_C_[0-9]+' THEN 'Integración' ELSE 'Manual' END
ORDER BY "Fecha" DESC, "Origen de datos";


-- ============================================================
-- 1.7. Uso de herramientas LMS
-- Tendencia de uso de herramientas del LMS por curso/ficha y módulo. Cuenta eventos, usuarios únicos y rango de uso.
-- ============================================================
WITH "curso_parseado" AS (
    SELECT
        c.id AS "courseid", c.idnumber, c.shortname, c.fullname, c.category,
        SUBSTRING(c.shortname FROM '^P_([0-9]+)_') AS "codigo_programa_extraido",
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS "regional_extraida",
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS "centro_extraido"
    FROM "mdl_course" c
    WHERE c.id <> 1
),
"semillas" AS (
    SELECT 4 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.current_version, s.modality
    FROM "INTEGRACION"."SEEDS" s
    WHERE s.status_seed = 'A'
    UNION ALL
    SELECT 6 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.current_version, s.modality
    FROM "INTEGRACION"."SEEDS_INDUCTION" s
    WHERE s.status_seed = 'A'
)
SELECT
    cp.idnumber AS "Código grupo/ficha",
    cp.fullname AS "Nombre grupo/ficha en el LMS",
    COALESCE(s.education_level, 'No definido') AS "Nivel del programa",
    COALESCE(s.modality, 'No definido') AS "Modalidad",
    COALESCE(cp."regional_extraida", 'No definido') AS "Regional",
    COALESCE(cp."centro_extraido", 'No definido') AS "Centro de Formación",
    COALESCE(cp."codigo_programa_extraido", s."codigo_programa", 'No definido') AS "Código Programa de Formación",
    COALESCE(s.prog_name, 'No definido') AS "Programa de formación",
    m.name AS "Herramienta LMS",
    COUNT(DISTINCT cm.id) AS "Actividades creadas",
    COUNT(l.id) AS "Total usos",
    COUNT(DISTINCT l.userid) AS "Usuarios únicos",
    CASE WHEN MIN(l.timecreated) IS NULL THEN 'Sin uso' ELSE TO_CHAR(TO_TIMESTAMP(MIN(l.timecreated)), 'YYYY/MM/DD HH24:MI:SS') END AS "Primer uso",
    CASE WHEN MAX(l.timecreated) IS NULL THEN 'Sin uso' ELSE TO_CHAR(TO_TIMESTAMP(MAX(l.timecreated)), 'YYYY/MM/DD HH24:MI:SS') END AS "Último uso"
FROM "mdl_course_modules" cm
JOIN "mdl_modules" m ON m.id = cm.module
JOIN "curso_parseado" cp ON cp."courseid" = cm.course
LEFT JOIN "semillas" s ON s."codigo_programa" = cp."codigo_programa_extraido" AND s."categoria_origen" = cp.category
LEFT JOIN "mdl_logstore_standard_log" l ON l.courseid = cp."courseid" AND l.contextinstanceid = cm.id AND l.contextlevel = 70
GROUP BY
    cp.idnumber, cp.fullname, s.education_level, s.modality, cp."regional_extraida", cp."centro_extraido",
    cp."codigo_programa_extraido", s."codigo_programa", s.prog_name, m.name
ORDER BY cp.fullname, "Total usos" DESC, m.name;


-- ============================================================
-- 1.7B. Participación por herramientas
-- Conteo de participación por usuario y ficha: ingresos, blogs, evaluaciones, evidencias, foros, comentarios, sondeos, wikis y SCORM. Integra la lógica de las consultas del megareporte.
-- ============================================================
WITH "curso_parseado" AS (
    SELECT
        c.id AS "courseid", c.idnumber, c.shortname, c.fullname, c.category, c.startdate, c.enddate,
        SUBSTRING(c.shortname FROM '^P_([0-9]+)_') AS "codigo_programa_extraido",
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS "regional_extraida",
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS "centro_extraido"
    FROM "mdl_course" c
    WHERE c.id <> 1
),
"semillas" AS (
    SELECT 4 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.current_version, s.modality
    FROM "INTEGRACION"."SEEDS" s
    WHERE s.status_seed = 'A'
    UNION ALL
    SELECT 6 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.current_version, s.modality
    FROM "INTEGRACION"."SEEDS_INDUCTION" s
    WHERE s.status_seed = 'A'
),
"base_matriculas" AS (
    SELECT DISTINCT
        cp."courseid",
        cp.idnumber AS "codigo_ficha",
        cp.fullname AS "nombre_ficha",
        cp."codigo_programa_extraido",
        cp."regional_extraida",
        cp."centro_extraido",
        cp.category,
        u.id AS "userid",
        u.username AS "documento",
        CONCAT(u.firstname, ' ', u.lastname) AS "nombres_apellidos",
        STRING_AGG(DISTINCT COALESCE(NULLIF(r.name, ''), r.shortname), ', ') AS "rol_usuario"
    FROM "mdl_user_enrolments" ue
    JOIN "mdl_enrol" e ON e.id = ue.enrolid
    JOIN "curso_parseado" cp ON cp."courseid" = e.courseid
    JOIN "mdl_user" u ON u.id = ue.userid
    LEFT JOIN "mdl_context" ctx ON ctx.instanceid = cp."courseid" AND ctx.contextlevel = 50
    LEFT JOIN "mdl_role_assignments" ra ON ra.userid = u.id AND ra.contextid = ctx.id
    LEFT JOIN "mdl_role" r ON r.id = ra.roleid
    WHERE u.deleted = 0
    GROUP BY cp."courseid", cp.idnumber, cp.fullname, cp."codigo_programa_extraido", cp."regional_extraida", cp."centro_extraido", cp.category, u.id, u.username, u.firstname, u.lastname
),
"ingresos" AS (
    SELECT userid, courseid, COUNT(*) AS total_ingresos
    FROM "mdl_logstore_standard_log"
    WHERE action = 'viewed' AND userid > 0 AND courseid IS NOT NULL
    GROUP BY userid, courseid
),
"blogs" AS (
    SELECT fp.userid, f.course AS courseid, COUNT(fp.id) AS total_blogs
    FROM "mdl_forum_discussions" fd
    JOIN "mdl_forum_posts" fp ON fp.discussion = fd.id AND fp.parent = 0
    JOIN "mdl_forum" f ON f.id = fd.forum
    WHERE f.type = 'blog' OR f.name ILIKE 'Blog%'
    GROUP BY fp.userid, f.course
),
"evaluaciones" AS (
    SELECT userid, courseid, COUNT(*) AS total_evaluaciones
    FROM "mdl_logstore_standard_log"
    WHERE objecttable = 'quiz_attempts' AND target = 'attempt' AND action = 'submitted'
    GROUP BY userid, courseid
),
"evidencias" AS (
    SELECT mas.userid, ma.course AS courseid, COUNT(DISTINCT mas.assignment) AS total_evidencias
    FROM "mdl_assign_submission" mas
    JOIN "mdl_assign" ma ON ma.id = mas.assignment
    WHERE mas.status IN ('submitted', 'draft')
    GROUP BY mas.userid, ma.course
),
"foros" AS (
    SELECT mfd.userid, mf.course AS courseid, COUNT(DISTINCT mfd.id) AS total_foros
    FROM "mdl_forum_discussions" mfd
    JOIN "mdl_forum" mf ON mf.id = mfd.forum
    WHERE mf.type NOT IN ('news', 'blog')
    GROUP BY mfd.userid, mf.course
),
"comentarios" AS (
    SELECT mfp.userid, mf.course AS courseid, COUNT(DISTINCT mfp.id) AS total_comentarios_foro
    FROM "mdl_forum_posts" mfp
    JOIN "mdl_forum_discussions" mfd ON mfd.id = mfp.discussion
    JOIN "mdl_forum" mf ON mf.id = mfd.forum
    WHERE mf.type NOT IN ('news', 'blog') AND mfp.parent <> 0 AND UPPER(mf.name) <> 'ANUNCIOS'
    GROUP BY mfp.userid, mf.course
),
"sondeos" AS (
    SELECT userid, courseid, SUM(total) AS total_sondeos
    FROM (
        SELECT mfc.userid, mf.course AS courseid, COUNT(DISTINCT mfc.id) AS total
        FROM "mdl_feedback_completed" mfc
        JOIN "mdl_feedback" mf ON mf.id = mfc.feedback
        GROUP BY mfc.userid, mf.course
        UNION ALL
        SELECT msa.userid, ms.course AS courseid, COUNT(DISTINCT msa.id) AS total
        FROM "mdl_survey_answers" msa
        JOIN "mdl_survey" ms ON ms.id = msa.survey
        GROUP BY msa.userid, ms.course
    ) x
    GROUP BY userid, courseid
),
"wikis" AS (
    SELECT userid, courseid, COUNT(*) AS total_wikis
    FROM "mdl_logstore_standard_log"
    WHERE component = 'mod_wiki' AND eventname LIKE '%page_updated%'
    GROUP BY userid, courseid
),
"scorm" AS (
    SELECT userid, courseid, COUNT(*) AS total_scorm
    FROM "mdl_logstore_standard_log"
    WHERE component = 'mod_scorm' AND userid > 0 AND courseid IS NOT NULL
    GROUP BY userid, courseid
)
SELECT
    bm."codigo_ficha" AS "Código grupo/ficha",
    bm."nombre_ficha" AS "Nombre grupo/ficha en el LMS",
    COALESCE(s.education_level, 'No definido') AS "Nivel del programa",
    COALESCE(s.modality, 'No definido') AS "Modalidad",
    COALESCE(bm."regional_extraida", 'No definido') AS "Regional",
    COALESCE(bm."centro_extraido", 'No definido') AS "Centro de Formación",
    COALESCE(bm."codigo_programa_extraido", s."codigo_programa", 'No definido') AS "Código Programa de Formación",
    COALESCE(s.prog_name, 'No definido') AS "Programa de formación",
    COALESCE(bm."rol_usuario", 'Sin rol asignado') AS "Rol de usuario",
    bm."documento" AS "Documento",
    bm."nombres_apellidos" AS "Nombres y apellidos",
    COALESCE(i.total_ingresos, 0) AS "Ingresos",
    COALESCE(bl.total_blogs, 0) AS "Blogs",
    COALESCE(ev.total_evaluaciones, 0) AS "Evaluaciones",
    COALESCE(evi.total_evidencias, 0) AS "Evidencias",
    COALESCE(f.total_foros, 0) AS "Foros discusiones",
    COALESCE(co.total_comentarios_foro, 0) AS "Foros comentarios",
    COALESCE(so.total_sondeos, 0) AS "Sondeos",
    COALESCE(w.total_wikis, 0) AS "Wikis",
    COALESCE(sc.total_scorm, 0) AS "SCORM",
    COALESCE(i.total_ingresos, 0) + COALESCE(bl.total_blogs, 0) + COALESCE(ev.total_evaluaciones, 0) + COALESCE(evi.total_evidencias, 0) + COALESCE(f.total_foros, 0) + COALESCE(co.total_comentarios_foro, 0) + COALESCE(so.total_sondeos, 0) + COALESCE(w.total_wikis, 0) + COALESCE(sc.total_scorm, 0) AS "Total participación herramientas"
FROM "base_matriculas" bm
LEFT JOIN "semillas" s ON s."codigo_programa" = bm."codigo_programa_extraido" AND s."categoria_origen" = bm.category
LEFT JOIN "ingresos" i ON i.userid = bm.userid AND i.courseid = bm."courseid"
LEFT JOIN "blogs" bl ON bl.userid = bm.userid AND bl.courseid = bm."courseid"
LEFT JOIN "evaluaciones" ev ON ev.userid = bm.userid AND ev.courseid = bm."courseid"
LEFT JOIN "evidencias" evi ON evi.userid = bm.userid AND evi.courseid = bm."courseid"
LEFT JOIN "foros" f ON f.userid = bm.userid AND f.courseid = bm."courseid"
LEFT JOIN "comentarios" co ON co.userid = bm.userid AND co.courseid = bm."courseid"
LEFT JOIN "sondeos" so ON so.userid = bm.userid AND so.courseid = bm."courseid"
LEFT JOIN "wikis" w ON w.userid = bm.userid AND w.courseid = bm."courseid"
LEFT JOIN "scorm" sc ON sc.userid = bm.userid AND sc.courseid = bm."courseid"
ORDER BY bm."codigo_ficha", bm."nombres_apellidos";


-- ============================================================
-- 1.8A. Tiempo de permanencia por herramientas
-- Moodle no guarda permanencia exacta por herramienta. Esta consulta estima el tiempo con la diferencia entre eventos consecutivos del usuario en el curso, limitada a máximo 30 minutos por salto.
-- ============================================================
WITH "eventos" AS (
    SELECT
        l.userid,
        l.courseid,
        l.contextinstanceid,
        l.contextlevel,
        l.timecreated,
        LEAD(l.timecreated) OVER (PARTITION BY l.userid, l.courseid ORDER BY l.timecreated) AS "siguiente_evento"
    FROM "mdl_logstore_standard_log" l
    WHERE l.userid > 0
      AND l.courseid IS NOT NULL
),
"tiempos" AS (
    SELECT
        userid,
        courseid,
        contextinstanceid,
        CASE
            WHEN "siguiente_evento" IS NULL THEN 0
            WHEN "siguiente_evento" - timecreated > 1800 THEN 1800
            WHEN "siguiente_evento" - timecreated < 0 THEN 0
            ELSE "siguiente_evento" - timecreated
        END AS "segundos_estimados"
    FROM "eventos"
),
"curso_parseado" AS (
    SELECT
        c.id AS "courseid", c.idnumber, c.shortname, c.fullname, c.category,
        SUBSTRING(c.shortname FROM '^P_([0-9]+)_') AS "codigo_programa_extraido",
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS "regional_extraida",
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS "centro_extraido"
    FROM "mdl_course" c
    WHERE c.id <> 1
),
"semillas" AS (
    SELECT 4 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.modality
    FROM "INTEGRACION"."SEEDS" s
    WHERE s.status_seed = 'A'
    UNION ALL
    SELECT 6 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.modality
    FROM "INTEGRACION"."SEEDS_INDUCTION" s
    WHERE s.status_seed = 'A'
)
SELECT
    cp.idnumber AS "Código grupo/ficha",
    cp.fullname AS "Nombre grupo/ficha en el LMS",
    COALESCE(s.education_level, 'No definido') AS "Nivel del programa",
    COALESCE(s.modality, 'No definido') AS "Modalidad",
    COALESCE(cp."regional_extraida", 'No definido') AS "Regional",
    COALESCE(cp."centro_extraido", 'No definido') AS "Centro de Formación",
    COALESCE(cp."codigo_programa_extraido", s."codigo_programa", 'No definido') AS "Código Programa de Formación",
    COALESCE(s.prog_name, 'No definido') AS "Programa de formación",
    u.username AS "Documento",
    CONCAT(u.firstname, ' ', u.lastname) AS "Nombres y apellidos",
    COALESCE(m.name, 'Curso / LMS') AS "Herramienta LMS",
    ROUND(SUM(t."segundos_estimados") / 60.0, 2) AS "Minutos estimados",
    ROUND(SUM(t."segundos_estimados") / 3600.0, 2) AS "Horas estimadas",
    ROUND(100.0 * SUM(t."segundos_estimados") / NULLIF(SUM(SUM(t."segundos_estimados")) OVER (PARTITION BY cp."courseid", u.id), 0), 2) AS "Porcentaje tiempo usuario curso"
FROM "tiempos" t
JOIN "mdl_user" u ON u.id = t.userid
JOIN "curso_parseado" cp ON cp."courseid" = t.courseid
LEFT JOIN "semillas" s ON s."codigo_programa" = cp."codigo_programa_extraido" AND s."categoria_origen" = cp.category
LEFT JOIN "mdl_course_modules" cm ON cm.id = t.contextinstanceid
LEFT JOIN "mdl_modules" m ON m.id = cm.module
WHERE u.deleted = 0
GROUP BY cp."courseid", cp.idnumber, cp.fullname, s.education_level, s.modality, cp."regional_extraida", cp."centro_extraido", cp."codigo_programa_extraido", s."codigo_programa", s.prog_name, u.id, u.username, u.firstname, u.lastname, m.name
ORDER BY cp.fullname, "Nombres y apellidos", "Minutos estimados" DESC;


-- ============================================================
-- 1.8B. Sesiones en línea - versión segura por logs
-- Consulta segura que no falla si no existe tabla del plugin. Detecta eventos de videoconferencia por componentes/eventos en el log estándar.
-- ============================================================
WITH "curso_parseado" AS (
    SELECT
        c.id AS "courseid", c.idnumber, c.shortname, c.fullname, c.category,
        SUBSTRING(c.shortname FROM '^P_([0-9]+)_') AS "codigo_programa_extraido",
        SUBSTRING(c.shortname FROM '_R_([0-9]+)') AS "regional_extraida",
        SUBSTRING(c.shortname FROM '_C_([0-9]+)') AS "centro_extraido"
    FROM "mdl_course" c
    WHERE c.id <> 1
),
"semillas" AS (
    SELECT 4 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.modality
    FROM "INTEGRACION"."SEEDS" s
    WHERE s.status_seed = 'A'
    UNION ALL
    SELECT 6 AS "categoria_origen", s.code::text AS "codigo_programa", s.education_level, s.prog_name, s.modality
    FROM "INTEGRACION"."SEEDS_INDUCTION" s
    WHERE s.status_seed = 'A'
)
SELECT
    cp.idnumber AS "Código grupo/ficha",
    cp.fullname AS "Nombre grupo/ficha en el LMS",
    COALESCE(s.education_level, 'No definido') AS "Nivel de Formación",
    COALESCE(s.modality, 'No definido') AS "Modalidad",
    COALESCE(cp."regional_extraida", 'No definido') AS "Regional",
    COALESCE(cp."centro_extraido", 'No definido') AS "Centro de Formación",
    COALESCE(cp."codigo_programa_extraido", s."codigo_programa", 'No definido') AS "Código Programa",
    COALESCE(s.prog_name, 'No definido') AS "Nombre de programa",
    l.component AS "Componente videoconferencia",
    l.eventname AS "Evento",
    l.objecttable AS "Tabla objeto",
    l.objectid AS "ID objeto",
    TO_CHAR(TO_TIMESTAMP(MIN(l.timecreated)), 'YYYY/MM/DD HH24:MI:SS') AS "Primera actividad sesión",
    TO_CHAR(TO_TIMESTAMP(MAX(l.timecreated)), 'YYYY/MM/DD HH24:MI:SS') AS "Última actividad sesión",
    COUNT(*) AS "Total eventos sesión",
    COUNT(DISTINCT l.userid) AS "Usuarios participantes"
FROM "mdl_logstore_standard_log" l
JOIN "curso_parseado" cp ON cp."courseid" = l.courseid
LEFT JOIN "semillas" s ON s."codigo_programa" = cp."codigo_programa_extraido" AND s."categoria_origen" = cp.category
WHERE l.userid > 0
  AND l.courseid IS NOT NULL
  AND (
        l.component ILIKE '%bigbluebutton%'
     OR l.component ILIKE '%zoom%'
     OR l.component ILIKE '%teams%'
     OR l.component ILIKE '%webex%'
     OR l.eventname ILIKE '%bigbluebutton%'
     OR l.eventname ILIKE '%zoom%'
     OR l.eventname ILIKE '%meeting%'
     OR l.eventname ILIKE '%session%'
  )
GROUP BY
    cp.idnumber, cp.fullname, s.education_level, s.modality, cp."regional_extraida", cp."centro_extraido", cp."codigo_programa_extraido", s."codigo_programa", s.prog_name,
    l.component, l.eventname, l.objecttable, l.objectid
ORDER BY "Primera actividad sesión" DESC;


-- ============================================================
-- 1.8C. Sesiones en línea - BigBlueButton si existe el plugin
-- Usar esta consulta solo si existen las tablas mdl_bigbluebuttonbn y mdl_bigbluebuttonbn_logs.
-- ============================================================
SELECT
    c.idnumber AS "Código grupo/ficha",
    c.fullname AS "Nombre grupo/ficha en el LMS",
    b.name AS "Nombre sesión",
    TO_CHAR(TO_TIMESTAMP(b.openingtime), 'YYYY/MM/DD HH24:MI:SS') AS "Fecha inicio sesión",
    CASE WHEN b.closingtime = 0 THEN 'No definida' ELSE TO_CHAR(TO_TIMESTAMP(b.closingtime), 'YYYY/MM/DD HH24:MI:SS') END AS "Fecha fin sesión",
    COUNT(DISTINCT bl.userid) AS "Usuarios participantes",
    COUNT(bl.id) AS "Total eventos sesión"
FROM "mdl_bigbluebuttonbn" b
JOIN "mdl_course" c ON c.id = b.course
LEFT JOIN "mdl_bigbluebuttonbn_logs" bl ON bl.bigbluebuttonbnid = b.id
WHERE c.id <> 1
GROUP BY c.idnumber, c.fullname, b.name, b.openingtime, b.closingtime
ORDER BY "Fecha inicio sesión" DESC;


-- ============================================================
-- 0. Totales tablero inicial
-- Consulta de apoyo para la vista inicial: usuarios, aprendices, instructores, grupos/fichas y actividades LMS.
-- ============================================================
SELECT
    COUNT(DISTINCT u.id) FILTER (WHERE u.deleted = 0) AS "Total usuarios",
    COUNT(DISTINCT u.id) FILTER (WHERE u.deleted = 0 AND u.suspended = 0) AS "Total usuarios activos",
    COUNT(DISTINCT u.id) FILTER (WHERE r.shortname IN ('teacher', 'editingteacher') AND u.deleted = 0) AS "Total instructores",
    COUNT(DISTINCT u.id) FILTER (WHERE r.shortname IN ('teacher', 'editingteacher') AND u.deleted = 0 AND u.suspended = 0) AS "Total instructores activos",
    COUNT(DISTINCT u.id) FILTER (WHERE r.shortname = 'student' AND u.deleted = 0) AS "Total aprendices",
    COUNT(DISTINCT u.id) FILTER (WHERE r.shortname = 'student' AND u.deleted = 0 AND u.suspended = 0) AS "Total aprendices activos",
    COUNT(DISTINCT c.id) FILTER (WHERE c.id <> 1) AS "Total grupos/fichas",
    COUNT(DISTINCT c.id) FILTER (WHERE c.id <> 1 AND c.visible = 1) AS "Total grupos/fichas activos",
    COUNT(DISTINCT l.userid) AS "Usuarios con ingreso",
    (SELECT COUNT(*) FROM "mdl_assign") AS "Evidencias",
    (SELECT COUNT(*) FROM "mdl_quiz") AS "Evaluaciones",
    (SELECT COUNT(*) FROM "mdl_feedback") AS "Sondeos",
    (SELECT COUNT(*) FROM "mdl_forum" WHERE type NOT IN ('news', 'blog')) AS "Foros",
    (SELECT COUNT(*) FROM "mdl_forum" WHERE type = 'blog' OR name ILIKE 'Blog%') AS "Blogs",
    (SELECT COUNT(*) FROM "mdl_wiki") AS "Wikis"
FROM "mdl_user" u
LEFT JOIN "mdl_role_assignments" ra ON ra.userid = u.id
LEFT JOIN "mdl_role" r ON r.id = ra.roleid
LEFT JOIN "mdl_context" ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
LEFT JOIN "mdl_course" c ON c.id = ctx.instanceid
LEFT JOIN "mdl_logstore_standard_log" l ON l.userid = u.id;


-- ============================================================
-- AUX. Validación de columnas disponibles
-- Consultas auxiliares para revisar esquemas, tablas y columnas antes de ajustar nombres de regional/centro o campos personalizados.
-- ============================================================
-- Tablas del esquema INTEGRACION
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'INTEGRACION'
ORDER BY table_name;

-- Columnas de SEEDS, SEEDS_INDUCTION y V_PROGRAMA_FORMACION_B
SELECT table_schema, table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'INTEGRACION'
  AND table_name IN ('SEEDS', 'SEEDS_INDUCTION', 'V_PROGRAMA_FORMACION_B')
ORDER BY table_name, ordinal_position;

-- Campos personalizados de usuario: tipo documento, documento, etc.
SELECT f.id, f.shortname, f.name, f.datatype
FROM "mdl_user_info_field" f
ORDER BY f.shortname;

