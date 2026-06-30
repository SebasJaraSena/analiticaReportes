# Control DB fuera de Docker (Postgres en el host)

La base de control (`reportes`: solicitudes, programados, usuarios) deja de correr como
contenedor y pasa a un **Postgres instalado en el host**. Así los datos no dependen del
ciclo de vida de los contenedores: recrear, borrar o reinstalar Docker no los toca.

> El host ya corre Postgres (la Moodle DB se accede vía `host.docker.internal`). La control
> DB puede vivir en **esa misma instancia** como una base separada llamada `reportes`.

---

## Qué cambió en el repo

- `docker-compose.yml`: se eliminó el servicio `db` y el volumen `reportes_db`. `api` y
  `worker` ya no dependen de `db` (solo de `redis`).
- `DATABASE_HOST` pasó de `db` a `host.docker.internal` (en `.env` / `.env.local` y como
  default en `api/config.py`).
- Las tablas se crean solas al arrancar (`init_control_db()` → `create_all`).

---

## Puesta en marcha en un servidor nuevo

### 1. Postgres en el host

Si ya está instalado (Moodle), saltar. Si no:

```bash
sudo apt install postgresql
```

### 2. Crear rol y base

```bash
sudo -u postgres psql -c "CREATE ROLE reportes LOGIN PASSWORD 'reportes_2026_secret';"
sudo -u postgres psql -c "CREATE DATABASE reportes OWNER reportes;"
```

> Usar la misma contraseña que `DATABASE_PASSWORD` del `.env`.

### 3. Permitir conexiones desde los contenedores

Los contenedores llegan al host por la red bridge de Docker (subred `172.x`). Hay que
abrir Postgres a esa red.

`postgresql.conf`:

```
listen_addresses = '*'
```

`pg_hba.conf` (agregar línea para la subred Docker):

```
host    reportes    reportes    172.16.0.0/12    scram-sha-256
```

Recargar:

```bash
sudo systemctl restart postgresql
```

### 4. Variables de entorno

En `.env` (producción) / `.env.local` (local):

```
DATABASE_HOST=host.docker.internal
DATABASE_PORT=5432
DATABASE_DB=reportes
DATABASE_USER=reportes
DATABASE_PASSWORD=reportes_2026_secret
```

### 5. Levantar

```bash
# producción
docker compose up -d --build --remove-orphans

# local
ENV_FILE=.env.local docker compose up -d --build --remove-orphans
```

`--remove-orphans` elimina el viejo contenedor `reportes_db` si existía.

---

## Migrar datos de la BD dockerizada (si ya había datos)

Hacer **antes** de apagar el contenedor viejo.

### 1. Dump del contenedor actual

```bash
docker exec reportes_db pg_dump -U reportes -d reportes \
  --no-owner --no-privileges > reportes_dump.sql
```

### 2. Restaurar en el Postgres del host

```bash
PGPASSWORD=reportes_2026_secret psql -h localhost -U reportes -d reportes < reportes_dump.sql
```

### 3. Verificar

```bash
PGPASSWORD=reportes_2026_secret psql -h localhost -U reportes -d reportes -c "
  SELECT 'solicitudes', count(*) FROM reportes_zajuna_solicitudes
  UNION ALL SELECT 'programados', count(*) FROM reportes_programados
  UNION ALL SELECT 'users', count(*) FROM reportes_users;"
```

### 4. Levantar el stack nuevo y comprobar

```bash
docker compose up -d --remove-orphans
curl -s http://localhost:8089/api/health
```

### 5. Limpieza (cuando esté confirmado)

El volumen viejo queda intacto como respaldo. Borrarlo solo cuando todo esté validado:

```bash
docker volume rm reportes_db
```

---

## Respaldos (recomendado)

Con la BD en el host, programar un dump diario:

```bash
# /etc/cron.d/reportes-backup
0 2 * * *  postgres  pg_dump -d reportes | gzip > /var/backups/reportes_$(date +\%F).sql.gz
```

---

## Verificación realizada (entorno local)

Migración probada end-to-end: dump del contenedor → restore en Postgres del host →
stack levantado sin el servicio `db` → API conecta (`Control DB inicializado`) y lee los
datos migrados (108 solicitudes, 4 programados, 2 usuarios).
