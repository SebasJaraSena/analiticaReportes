-- Reporte 1.3: Matrículas LMS
-- SIN INTEGRACION. Programa/código de fullname, modalidad/version de shortname,
-- regional/centro de midb (joins de slider_form/lib/modalidades.php).
WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber, c.shortname, c.fullname, c.category,
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
roles_usuario_curso AS (
    SELECT
        ra.userid,
        ctx.instanceid AS courseid,
        STRING_AGG(DISTINCT COALESCE(NULLIF(r.name,''), r.shortname), ', ') AS rol_usuario
    FROM public.mdl_role_assignments ra
    JOIN public.mdl_context ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
    JOIN public.mdl_role r ON r.id = ra.roleid
    GROUP BY ra.userid, ctx.instanceid
)
SELECT
    cp.idnumber                                                              AS "Código de grupo/ficha",
    cp.fullname                                                              AS "Nombre grupo/ficha en el LMS",
    CASE
        WHEN cp.letra_modalidad IN ('V','A','P','PI') THEN 'Formación titulada'
        ELSE 'No definido'
    END                                                                      AS "Nivel del grupo/ficha",
    CASE
        WHEN cp.letra_modalidad = 'V'         THEN 'Titulada virtual'
        WHEN cp.letra_modalidad = 'A'         THEN 'Titulada a distancia'
        WHEN cp.letra_modalidad IN ('P','PI') THEN 'Formación presencial'
        ELSE 'No definido'
    END                                                                      AS "Modalidad",
    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END                                                                      AS "Estado del grupo/ficha",
    COALESCE(cp.codigo_programa, 'No definido')                            AS "Código del Programa",
    COALESCE(cp.version_extraida, 'No definido')                          AS "Versión del Programa",
    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname)              AS "Programa de formación",
    COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, 'No definido') AS "Regional",
    COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, 'No definido')     AS "Centro de Formación",
    COALESCE(ru.rol_usuario, 'Sin rol asignado')                           AS "Rol de usuario",
    UPPER(SUBSTRING(LOWER(COALESCE(NULLIF(u.idnumber,''), u.username)) FROM '(cc|dni|ce|ppt)$'))
                                                                           AS "Tipo de Documento",
    REGEXP_REPLACE(COALESCE(NULLIF(u.idnumber,''), u.username), '(?i)(cc|dni|ce|ppt)$', '')
                                                                           AS "Documento",
    CONCAT(u.firstname, ' ', u.lastname)                                   AS "Nombres y apellidos",
    u.email                                                                 AS "Correo",
    CASE WHEN ue.status = 0 THEN 'Activo' ELSE 'Suspendido' END           AS "Estado matrícula",
    CASE
        WHEN u.deleted = 1  THEN 'Eliminado'
        WHEN u.suspended = 1 THEN 'Suspendido'
        ELSE 'Activo'
    END                                                                      AS "Estado del Usuario LMS",
    TO_CHAR(TO_TIMESTAMP(cp.startdate), 'YYYY/MM/DD HH24:MI:SS')          AS "Fecha inicio grupo/ficha",
    CASE WHEN cp.enddate = 0 THEN 'No definida'
         ELSE TO_CHAR(TO_TIMESTAMP(cp.enddate), 'YYYY/MM/DD HH24:MI:SS')
    END                                                                      AS "Fecha fin grupo/ficha",
    TO_CHAR(TO_TIMESTAMP(ue.timecreated), 'YYYY/MM/DD HH24:MI:SS')        AS "Fecha matrícula",
    TO_CHAR(TO_TIMESTAMP(ue.timemodified), 'YYYY/MM/DD HH24:MI:SS')       AS "Fecha actualización matrícula",
    CASE WHEN ue.timeend = 0 OR ue.timeend IS NULL THEN 'No definida'
         ELSE TO_CHAR(TO_TIMESTAMP(ue.timeend), 'YYYY/MM/DD HH24:MI:SS')
    END                                                                      AS "Fecha Desenrolamiento"
FROM public.mdl_user_enrolments ue
JOIN public.mdl_enrol e          ON e.id = ue.enrolid
JOIN curso_parseado cp           ON cp.courseid = e.courseid
JOIN public.mdl_user u           ON u.id = ue.userid
LEFT JOIN midb.regionales reg    ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint
LEFT JOIN midb.centros cen       ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint
LEFT JOIN roles_usuario_curso ru ON ru.userid = u.id AND ru.courseid = cp.courseid
WHERE u.deleted = 0
  AND (%(codigo_ficha)s     IS NULL OR cp.idnumber ILIKE %(codigo_ficha)s)
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
       CASE WHEN cp.visible = 0 THEN 'Oculto'
            WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
            WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
            ELSE 'En ejecución' END = %(estado_grupo)s)
  AND (%(rol_usuario)s       IS NULL OR ru.rol_usuario ILIKE '%%' || %(rol_usuario)s || '%%')
  AND (%(identificacion)s   IS NULL OR COALESCE(NULLIF(u.idnumber,''), u.username) ILIKE %(identificacion)s)
  AND (%(nombres_apellidos)s IS NULL OR CONCAT(u.firstname,' ',u.lastname) ILIKE '%%' || %(nombres_apellidos)s || '%%')
  AND (%(fecha_desde)s IS NULL
       OR TO_TIMESTAMP(ue.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL
       OR TO_TIMESTAMP(ue.timecreated)::date <= %(fecha_hasta)s::date)
  AND (%(fecha_inicio_desde)s IS NULL
       OR TO_TIMESTAMP(cp.startdate)::date >= %(fecha_inicio_desde)s::date)
  AND (%(fecha_inicio_hasta)s IS NULL
       OR TO_TIMESTAMP(cp.startdate)::date <= %(fecha_inicio_hasta)s::date)
  AND (%(fecha_fin_desde)s IS NULL
       OR (cp.enddate > 0 AND TO_TIMESTAMP(cp.enddate)::date >= %(fecha_fin_desde)s::date))
  AND (%(fecha_fin_hasta)s IS NULL
       OR (cp.enddate > 0 AND TO_TIMESTAMP(cp.enddate)::date <= %(fecha_fin_hasta)s::date))
ORDER BY cp.fullname, "Rol de usuario", "Nombres y apellidos"
