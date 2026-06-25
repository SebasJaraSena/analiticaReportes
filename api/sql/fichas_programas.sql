-- Reporte 1.5: Fichas y programas de formación
-- SIN INTEGRACION. Programa/código de fullname, modalidad/version de shortname,
-- regional/centro de midb (joins de slider_form/lib/modalidades.php).
WITH curso_parseado AS (
    SELECT
        c.id AS courseid,
        c.idnumber, c.shortname, c.fullname, c.category,
        c.visible, c.startdate, c.enddate, c.timecreated,
        SUBSTRING(c.fullname FROM '\(([0-9]+)(?:_PRY_[0-9]+)?\)\s*$')          AS codigo_programa,
        TRIM(REGEXP_REPLACE(c.fullname, '\s*\([0-9]+(?:_PRY_[0-9]+)?\)\s*$', '')) AS programa_formacion,
        SUBSTRING(c.shortname FROM '_R_([0-9]+)')                              AS codigo_regional,
        SUBSTRING(c.shortname FROM '_C_([0-9]+)')                              AS codigo_centro,
        SUBSTRING(c.shortname FROM '^P_[0-9]+_([A-Za-z]+)_')                   AS letra_modalidad,
        SUBSTRING(c.shortname FROM '^P_[0-9]+_[A-Za-z]+_([0-9]+)')             AS version_extraida
    FROM public.mdl_course c
    WHERE c.id <> 1
),
roles_por_curso AS (
    SELECT
        ctx.instanceid AS courseid,
        COUNT(DISTINCT ra.userid) FILTER (WHERE r.shortname = 'student' AND ue.status = 0)    AS aprendices_activos,
        COUNT(DISTINCT ra.userid) FILTER (WHERE r.shortname = 'student' AND ue.status <> 0)   AS aprendices_inactivos,
        COUNT(DISTINCT ra.userid) FILTER (WHERE r.shortname IN ('teacher','editingteacher') AND ue.status = 0)  AS instructores_activos,
        COUNT(DISTINCT ra.userid) FILTER (WHERE r.shortname IN ('teacher','editingteacher') AND ue.status <> 0) AS instructores_inactivos,
        COUNT(DISTINCT ra.userid) AS total_usuarios_con_rol
    FROM public.mdl_role_assignments ra
    JOIN public.mdl_context ctx ON ctx.id = ra.contextid AND ctx.contextlevel = 50
    JOIN public.mdl_role r ON r.id = ra.roleid
    LEFT JOIN public.mdl_enrol en ON en.courseid = ctx.instanceid
    LEFT JOIN public.mdl_user_enrolments ue ON ue.userid = ra.userid AND ue.enrolid = en.id
    GROUP BY ctx.instanceid
)
SELECT
    COALESCE(cp.codigo_programa, 'No definido')                            AS "Código Programa de Formación",
    COALESCE(cp.version_extraida, 'No definido')                          AS "Versión Programa de Formación",
    COALESCE(NULLIF(cp.programa_formacion, ''), cp.fullname)              AS "Programa de formación",
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
    cp.idnumber                                                             AS "Código grupo/ficha",
    cp.fullname                                                             AS "Nombre grupo/ficha en el LMS",
    CASE
        WHEN cp.visible = 0 THEN 'Oculto'
        WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
        WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
        ELSE 'En ejecución'
    END                                                                      AS "Estado del grupo/ficha",
    COALESCE(reg.nombre, 'Regional ' || cp.codigo_regional, 'No definido') AS "Regional",
    COALESCE(cen.nombre, 'Centro ' || cp.codigo_centro, 'No definido')     AS "Centro de Formación",
    TO_CHAR(TO_TIMESTAMP(cp.timecreated), 'YYYY/MM/DD HH24:MI:SS')        AS "Fecha creación curso LMS",
    TO_CHAR(TO_TIMESTAMP(cp.startdate), 'YYYY/MM/DD HH24:MI:SS')          AS "Fecha inicio grupo/ficha",
    CASE WHEN cp.enddate = 0 THEN 'No definida'
         ELSE TO_CHAR(TO_TIMESTAMP(cp.enddate), 'YYYY/MM/DD HH24:MI:SS')
    END                                                                      AS "Fecha fin grupo/ficha",
    COALESCE(rpc.aprendices_activos, 0)                                    AS "Cantidad de Aprendices Activos",
    COALESCE(rpc.aprendices_inactivos, 0)                                  AS "Cantidad de Aprendices Inactivos",
    COALESCE(rpc.instructores_activos, 0)                                  AS "Cantidad de Instructores Activos",
    COALESCE(rpc.instructores_inactivos, 0)                                AS "Cantidad de Instructores Inactivos",
    COALESCE(rpc.total_usuarios_con_rol, 0)                                AS "Total Usuarios con Rol"
FROM curso_parseado cp
LEFT JOIN midb.regionales reg ON reg.rgn_id = NULLIF(cp.codigo_regional, '')::bigint
LEFT JOIN midb.centros cen    ON cen.sed_id = NULLIF(cp.codigo_centro, '')::bigint
LEFT JOIN roles_por_curso rpc ON rpc.courseid = cp.courseid
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
  AND (%(estado)s IS NULL OR
       CASE WHEN cp.visible = 0 THEN 'Oculto'
            WHEN cp.startdate > EXTRACT(EPOCH FROM NOW()) THEN 'No iniciado'
            WHEN cp.enddate > 0 AND cp.enddate < EXTRACT(EPOCH FROM NOW()) THEN 'Finalizado'
            ELSE 'En ejecución' END = %(estado)s)
  AND (%(nombre_programa)s IS NULL OR COALESCE(NULLIF(cp.programa_formacion,''), cp.fullname) ILIKE '%%' || %(nombre_programa)s || '%%')
  AND (%(fecha_desde)s IS NULL OR TO_TIMESTAMP(cp.timecreated)::date >= %(fecha_desde)s::date)
  AND (%(fecha_hasta)s IS NULL OR TO_TIMESTAMP(cp.timecreated)::date <= %(fecha_hasta)s::date)
  AND (%(fecha_inicio_desde)s IS NULL OR TO_TIMESTAMP(cp.startdate)::date >= %(fecha_inicio_desde)s::date)
  AND (%(fecha_inicio_hasta)s IS NULL OR TO_TIMESTAMP(cp.startdate)::date <= %(fecha_inicio_hasta)s::date)
  AND (%(fecha_fin_desde)s IS NULL OR (cp.enddate > 0 AND TO_TIMESTAMP(cp.enddate)::date >= %(fecha_fin_desde)s::date))
  AND (%(fecha_fin_hasta)s IS NULL OR (cp.enddate > 0 AND TO_TIMESTAMP(cp.enddate)::date <= %(fecha_fin_hasta)s::date))
ORDER BY cp.timecreated DESC, cp.fullname
