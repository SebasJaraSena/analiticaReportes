# Manual — Tablas Resumen en la Base de Datos Primaria (Opción A)

> **Para:** Equipo DBA / Administrador de la base primaria de Moodle (ZAJUNA).
> **Objetivo:** Permitir que el aplicativo de reportes (que apunta a la **réplica de solo lectura**)
> consulte tablas pequeñas pre-calculadas en lugar de escanear millones de filas de
> `mdl_logstore_standard_log` en cada reporte.

---

## 1. Idea general

```
Base PRIMARIA (escritura)
   │
   │  (1) Job nocturno agrega los logs del día anterior
   ▼
Tablas resumen  (mdl_report_*)
   │
   │  (2) Replicación normal del clúster
   ▼
RÉPLICA de lectura
   │
   │  (3) El aplicativo de reportes consulta SOLO estas tablas
   ▼
Excel / CSV
```

- El aplicativo **nunca escribe**. Solo lee de la réplica.
- Todo lo que se crea/escribe (tablas + job) vive en la **primaria**.
- Las tablas resumen son chicas → los reportes pasan de minutos a segundos.

---

## 2. Qué hay que hacer en la primaria (resumen ejecutivo)

| Paso | Acción | Frecuencia |
|------|--------|------------|
| 1 | Crear el esquema `report` y las tablas `mdl_report_*` (DDL §4) | Una vez |
| 2 | Crear la tabla de control `report.watermark` | Una vez |
| 3 | Cargar histórico inicial (backfill, §6) | Una vez |
| 4 | Programar el job nocturno incremental (§5, §7) | Diario |
| 5 | Confirmar que las tablas llegan a la réplica (§8) | Verificación |
| 6 | Dar `SELECT` sobre `report.*` al usuario del aplicativo en la réplica (§9) | Una vez |

---

## 3. Granularidad de las tablas

Todas las tablas resumen son **por día** (`fecha date`). El reporte luego suma los días
del rango que pida el usuario. Así un mismo día se calcula una sola vez y sirve a todos
los reportes.

Tablas propuestas (las 4 base + 2 opcionales):

| Tabla | Grano | Alimenta a |
|-------|-------|-----------|
| `report.login_day` | día · usuario · curso | Registro de usuarios, Tráfico, Ingresos |
| `report.tool_activity_day` | día · usuario · curso · herramienta | Participación por herramientas, Herramientas LMS |
| `report.estimated_time_day` | día · usuario · curso · herramienta | Tiempo de permanencia |
| `report.user_course_day` | día · usuario · curso | Snapshot de matrícula/estado (Registro, Matrículas) |
| `report.traffic_hour` *(opcional)* | día · hora · curso | Tráfico diario (rango hora 60 min) |
| `report.login_dim_day` *(opcional)* | día · usuario · curso · navegador/SO/país/ciudad | Ingresos por navegador |

---

## 4. DDL — crear esquema y tablas

```sql
-- Ejecutar en la PRIMARIA
CREATE SCHEMA IF NOT EXISTS report;

-- 4.1 Ingresos (logins) por día/usuario/curso
CREATE TABLE IF NOT EXISTS report.login_day (
    fecha        date    NOT NULL,
    userid       bigint  NOT NULL,
    courseid     bigint  NOT NULL,
    ingresos     integer NOT NULL DEFAULT 0,   -- cantidad de eventos 'viewed'
    primer_ts    bigint,                        -- MIN(timecreated) del día
    ultimo_ts    bigint,                        -- MAX(timecreated) del día
    PRIMARY KEY (fecha, userid, courseid)
);
CREATE INDEX IF NOT EXISTS ix_login_day_course ON report.login_day (courseid, fecha);
CREATE INDEX IF NOT EXISTS ix_login_day_user   ON report.login_day (userid, fecha);

-- 4.2 Actividad por herramienta (conteos)
CREATE TABLE IF NOT EXISTS report.tool_activity_day (
    fecha        date         NOT NULL,
    userid       bigint       NOT NULL,
    courseid     bigint       NOT NULL,
    herramienta  varchar(40)  NOT NULL,   -- wiki, encuesta, evaluacion, evidencia,
                                          -- blog, anuncio, foro, comentario, scorm,
                                          -- sesion, chat
    cantidad     integer      NOT NULL DEFAULT 0,
    PRIMARY KEY (fecha, userid, courseid, herramienta)
);
CREATE INDEX IF NOT EXISTS ix_tool_act_course ON report.tool_activity_day (courseid, fecha);

-- 4.3 Tiempo estimado por herramienta (segundos)
CREATE TABLE IF NOT EXISTS report.estimated_time_day (
    fecha        date         NOT NULL,
    userid       bigint       NOT NULL,
    courseid     bigint       NOT NULL,
    herramienta  varchar(40)  NOT NULL,
    segundos     bigint       NOT NULL DEFAULT 0,  -- saltos > 1800s se truncan a 1800
    PRIMARY KEY (fecha, userid, courseid, herramienta)
);
CREATE INDEX IF NOT EXISTS ix_est_time_course ON report.estimated_time_day (courseid, fecha);

-- 4.4 Snapshot matrícula/estado usuario-curso por día
CREATE TABLE IF NOT EXISTS report.user_course_day (
    fecha           date    NOT NULL,
    userid          bigint  NOT NULL,
    courseid        bigint  NOT NULL,
    estado_matricula varchar(20),   -- Activa / Suspendida
    rol_shortnames   varchar(200),  -- 'student, editingteacher'
    PRIMARY KEY (fecha, userid, courseid)
);

-- 4.5 (Opcional) Tráfico por hora
CREATE TABLE IF NOT EXISTS report.traffic_hour (
    fecha            date     NOT NULL,
    hora             smallint NOT NULL,   -- 0..23
    courseid         bigint   NOT NULL,
    usuarios_unicos  integer  NOT NULL DEFAULT 0,
    PRIMARY KEY (fecha, hora, courseid)
);

-- 4.6 (Opcional) Ingresos con dimensiones de navegador
CREATE TABLE IF NOT EXISTS report.login_dim_day (
    fecha            date         NOT NULL,
    courseid         bigint       NOT NULL,
    so               varchar(60),
    navegador        varchar(60),
    pais             varchar(60),
    ciudad           varchar(80),
    ingresos_unicos  integer      NOT NULL DEFAULT 0,
    PRIMARY KEY (fecha, courseid, so, navegador, pais, ciudad)
);

-- 4.7 Control de avance del job (watermark)
CREATE TABLE IF NOT EXISTS report.watermark (
    job_name       varchar(60) PRIMARY KEY,
    last_full_date date NOT NULL          -- último día YA consolidado
);
```

---

## 5. Lógica del job nocturno (incremental e idempotente)

Regla clave: **procesar por día completo, borrar-y-reinsertar ese día**. Así, si el job se
re-ejecuta, no duplica. Solo toca el día anterior (y, por seguridad, re-procesa los últimos
2–3 días por si llegaron logs tardíos).

Pseudocódigo:

```
desde = (SELECT last_full_date FROM report.watermark WHERE job_name = 'login_day') - 2 días
hasta = ayer

para cada día D entre [desde, hasta]:
    BEGIN;
      DELETE FROM report.login_day WHERE fecha = D;
      INSERT INTO report.login_day (...)
        SELECT ... FROM mdl_logstore_standard_log
        WHERE DATE(TO_TIMESTAMP(timecreated)) = D
        GROUP BY ...;
    COMMIT;

UPDATE report.watermark SET last_full_date = ayer WHERE job_name = 'login_day';
```

### Ejemplo real: `report.login_day` para un día

```sql
-- :dia es la fecha a consolidar (ej '2026-06-24')
DELETE FROM report.login_day WHERE fecha = :dia;

INSERT INTO report.login_day (fecha, userid, courseid, ingresos, primer_ts, ultimo_ts)
SELECT
    DATE(TO_TIMESTAMP(l.timecreated))      AS fecha,
    l.userid,
    l.courseid,
    COUNT(*)                                AS ingresos,
    MIN(l.timecreated)                      AS primer_ts,
    MAX(l.timecreated)                      AS ultimo_ts
FROM public.mdl_logstore_standard_log l
WHERE l.userid > 0
  AND l.courseid IS NOT NULL
  AND l.action = 'viewed'
  AND TO_TIMESTAMP(l.timecreated) >= :dia::timestamp
  AND TO_TIMESTAMP(l.timecreated) <  (:dia::date + 1)::timestamp
GROUP BY 1, 2, 3;
```

> Filtrar por rango de `timecreated` (no por `DATE(...)` en el WHERE) permite usar el índice
> de `timecreated`. Si no existe, ver §10.

`tool_activity_day` y `estimated_time_day` siguen el mismo patrón pero agrupando además por
`herramienta` (la clasificación de módulo igual que en los SQL actuales del aplicativo:
`wiki / quiz→evaluacion / assign→evidencia / forum(blog/news/foro) / scorm / bigbluebuttonbn→sesion / chat`).

---

## 6. Carga histórica inicial (backfill)

Una sola vez, antes de activar el job diario. Procesar todo el histórico **por mes** para no
reventar memoria ni WAL:

```sql
-- repetir cambiando el mes, o con un bloque DO/loop
INSERT INTO report.login_day (...)
SELECT ...
FROM public.mdl_logstore_standard_log l
WHERE l.action = 'viewed' AND l.userid > 0 AND l.courseid IS NOT NULL
  AND TO_TIMESTAMP(l.timecreated) >= '2024-05-01'
  AND TO_TIMESTAMP(l.timecreated) <  '2024-06-01'
GROUP BY DATE(TO_TIMESTAMP(l.timecreated)), l.userid, l.courseid;
```

- Hacerlo en **horario de baja carga**.
- Al terminar: `UPDATE report.watermark SET last_full_date = <ultimo dia cargado>`.
- Correr `ANALYZE report.login_day;` (y las demás) al final.

Rango de datos actual detectado en logs: desde **2024-05-30**. Ajustar fechas reales.

---

## 7. Programación del job

Dos opciones, según lo que permita el DBA:

**A) `pg_cron` (dentro de Postgres, recomendado si está instalado):**
```sql
-- 02:30 cada día
SELECT cron.schedule('report_nightly', '30 2 * * *', $$ CALL report.run_nightly(); $$);
```
(empaquetar la lógica de §5 en un procedimiento `report.run_nightly()`).

**B) `cron` del sistema operativo en la primaria:**
```cron
30 2 * * *  psql -d zajuna -f /opt/report/run_nightly.sql >> /var/log/report_nightly.log 2>&1
```

Duración esperada: solo procesa ~1–3 días → segundos/minutos, no horas.

---

## 8. Replicación a la réplica de lectura

- **Si la réplica es física (streaming / hot standby):** las tablas `report.*` se replican
  **automáticamente**, igual que el resto del clúster. **No hay que hacer nada extra.**
- **Si la réplica es lógica (logical replication):** hay que **añadir las tablas a la
  publicación**:
  ```sql
  ALTER PUBLICATION <nombre_publicacion> ADD TABLE
      report.login_day, report.tool_activity_day,
      report.estimated_time_day, report.user_course_day,
      report.traffic_hour, report.login_dim_day;
  ```
  y crear el esquema `report` también en la réplica antes de suscribir.

> **Confirmar con el DBA qué tipo de réplica es.** Es el único punto que cambia el procedimiento.

---

## 9. Permisos para el aplicativo

En la **réplica** (o en la primaria si los roles se replican), dar solo lectura:

```sql
GRANT USAGE ON SCHEMA report TO <usuario_app>;
GRANT SELECT ON ALL TABLES IN SCHEMA report TO <usuario_app>;
ALTER DEFAULT PRIVILEGES IN SCHEMA report GRANT SELECT TO <usuario_app>;
```

El aplicativo **no necesita** acceso a `mdl_logstore_standard_log` una vez migrado.

---

## 10. Índice recomendado en la primaria (para que el job sea rápido)

Si el backfill/job va lento, crear (en horario de baja carga, `CONCURRENTLY`):

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_log_time_action
  ON public.mdl_logstore_standard_log (timecreated)
  WHERE action = 'viewed';
```
o un índice más amplio `(timecreated, courseid, userid)` según lo que el DBA prefiera.

---

## 11. Mantenimiento

- `VACUUM (ANALYZE)` sobre `report.*` después del backfill y periódicamente.
- Retención: las tablas resumen son chicas; normalmente **no** hace falta purgar. Si se quiere,
  borrar por `fecha < ahora - N años`.
- Las tablas resumen **se pueden reconstruir** desde los logs en cualquier momento (re-correr
  backfill). No son fuente de verdad, son caché.

---

## 12. Resumen de un vistazo para el DBA

1. `CREATE SCHEMA report` + tablas (§4).
2. Backfill histórico por mes (§6).
3. Programar job nocturno incremental (§5 + §7).
4. Confirmar tipo de réplica → física = nada; lógica = `ALTER PUBLICATION` (§8).
5. `GRANT SELECT` al usuario del aplicativo (§9).

El aplicativo de reportes se reescribe luego para leer `report.*` en vez de los logs crudos
(esa parte la hace el equipo del aplicativo, no el DBA).
