# Manual de Despliegue — Reportes ZAJUNA

Sistema de reportes administrativos pesados para Moodle/ZAJUNA. Stack: **FastAPI**
(API + UI web) + **RQ Worker** (generación en segundo plano) + **Redis** (cola) +
**PostgreSQL** (control DB en el host + Moodle DB solo lectura).

Este manual cubre un despliegue desde cero: requisitos, clonación, base de datos
externa, configuración de Moodle (plugin + web service), levantado de contenedores y
puesta detrás del reverse proxy.

---

## 1. Arquitectura

```
                    ┌─────────────────────────────────────────────┐
   Navegador  ──►   │  Reverse proxy (nginx/apache)  /analitica    │
                    └───────────────┬─────────────────────────────┘
                                    │
                    ┌───────────────▼──────────────┐
                    │  reportes-api (FastAPI:8089)  │  UI + REST + SSO
                    └───────┬───────────────┬───────┘
                            │               │
                 ┌──────────▼───┐   ┌───────▼─────────┐
                 │ Redis (cola) │   │ reportes-worker │  genera CSV/XLSX
                 └──────────────┘   └───────┬─────────┘
                                            │
        ┌───────────────────────────────────┼───────────────────────────┐
        │                                    │                           │
┌───────▼────────────┐          ┌────────────▼──────────┐   ┌────────────▼─────────┐
│ Control DB          │          │ Moodle/ZAJUNA DB      │   │ Volumen archivos     │
│ Postgres HOST       │          │ Postgres (solo lect.) │   │ reportes_generados   │
│ (reportes)          │          │ (zajuna / zajunadb)   │   │                      │
└─────────────────────┘          └───────────────────────┘   └──────────────────────┘
```

- **reportes-api**: expone la UI web y los endpoints REST. Puerto interno `8089`.
- **reportes-worker**: consume la cola Redis y ejecuta las consultas SQL pesadas,
  escribe los archivos. Corre además un hilo *scheduler* (daemon) que dispara los
  reportes programados (revisa cada 60s). No es cron del SO.
- **redis**: cola de trabajos (DB 2). Volumen `reportes_redis`.
- **Control DB** (`reportes`): tablas de solicitudes, programados y usuarios. **Vive
  FUERA de Docker**, en el Postgres del host, para que los datos sobrevivan al ciclo de
  vida de los contenedores. Ver `docs/bd-externa.md`.
- **Moodle DB**: fuente de datos, se accede **solo lectura**.
- **Volumen `reportes_generados`**: archivos CSV/XLSX generados. Se conservan los 100
  más recientes por usuario.

---

## 2. Requisitos del servidor

### Software

| Componente        | Versión mínima | Nota                                       |
|-------------------|----------------|--------------------------------------------|
| Docker Engine     | 24.x           | Con plugin `docker compose` v2             |
| Docker Compose    | v2             | `docker compose` (no `docker-compose`)     |
| PostgreSQL (host) | 14+            | Control DB + (opcional) Moodle DB          |
| Git               | cualquiera     | Para clonar                                |
| Moodle/ZAJUNA     | 4.3 (2023100900)| Para el plugin SSO                        |

Las imágenes traen Python 3.12 y todas las libs (ver `Dockerfile` / `requirements.txt`).
No se instala nada de Python en el host.

### Hardware recomendado

Los reportes son consultas pesadas sobre el log de Moodle (millones de filas) y escritura
de archivos grandes.

| Recurso | Mínimo | Recomendado | Razón                                                    |
|---------|--------|-------------|----------------------------------------------------------|
| CPU     | 2 vCPU | **4+ vCPU** | API corre 2 workers uvicorn; worker RQ hace agregaciones |
| RAM     | 4 GB   | **8+ GB**   | Pandas + XLSX en memoria por lotes; Postgres del host     |
| Disco   | 20 GB  | **50+ GB**  | Volumen de archivos generados (XLSX pesan ~4x CSV)        |

> El worker usa cursores server-side (streaming, `FETCH_SIZE=20_000`) para no cargar
> toda la consulta en RAM, pero XLSX igual acumula por lote. Con reportes de +1M filas,
> subir RAM.

### Puertos

- `8089` — API/UI (interno; se publica solo si no hay reverse proxy).
- `5432` — Postgres del host (los contenedores lo alcanzan por `host.docker.internal`).
- `6379` — Redis (interno al stack, no se publica).

---

## 3. Clonar el proyecto

```bash
cd /opt   # o el directorio que uses para despliegues
git clone <URL_DEL_REPO> reportes
cd reportes
git checkout main   # o la rama a desplegar (ej: bd-externa)
```

Estructura relevante:

```
reportes/
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
├── worker_start.py
├── .env / .env.local        # crear a partir de los de ejemplo
├── api/                      # FastAPI, jobs, sql, reportes
├── frontend/                 # UI estática (app.js, styles.css, index.html)
└── docs/                     # esta documentación
```

---

## 4. Base de datos externa (Postgres del host)

La control DB **no** corre en Docker. Se crea en el Postgres del host. Detalle completo
en `docs/bd-externa.md`; resumen:

### 4.1 Instalar Postgres (si no existe)

```bash
sudo apt install postgresql
```

### 4.2 Crear rol y base de control

```bash
sudo -u postgres psql -c "CREATE ROLE reportes LOGIN PASSWORD 'reportes_2026_secret';"
sudo -u postgres psql -c "CREATE DATABASE reportes OWNER reportes;"
```

> La contraseña debe coincidir con `DATABASE_PASSWORD` del `.env`. Las tablas se crean
> solas al arrancar el worker/API (`init_control_db()`).

### 4.3 Usuario de solo lectura para Moodle

**No** usar el superusuario para leer Moodle. Crear uno de solo lectura:

```sql
-- Conectado a la base de Moodle (zajuna / zajunadb)
CREATE USER reportes_ro WITH PASSWORD 'ro_secret';
GRANT CONNECT ON DATABASE zajunadb TO reportes_ro;
GRANT USAGE ON SCHEMA public TO reportes_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO reportes_ro;
```

### 4.4 Permitir conexiones desde los contenedores

Los contenedores llegan al host por la red bridge de Docker (subred `172.x`).

`postgresql.conf`:
```
listen_addresses = '*'
```

`pg_hba.conf` (agregar líneas para la subred Docker):
```
host    reportes    reportes       172.16.0.0/12    scram-sha-256
host    zajunadb    reportes_ro    172.16.0.0/12    scram-sha-256
```

Recargar:
```bash
sudo systemctl restart postgresql
```

---

## 5. Variables de entorno

Dos archivos: `.env` (producción) y `.env.local` (local). El compose elige con
`ENV_FILE`:

```yaml
env_file: ${ENV_FILE:-.env}
```

- Producción → usa `.env` por defecto.
- Local → **hay que prefijar** `ENV_FILE=.env.local` en cada `docker compose up`.

### 5.1 `.env` (producción) — variables clave

```ini
# ── Control DB (Postgres del host) ──────────────────
DATABASE_HOST=host.docker.internal
DATABASE_PORT=5432
DATABASE_DB=reportes
DATABASE_USER=reportes
DATABASE_PASSWORD=reportes_2026_secret

# ── Moodle DB (solo lectura) ────────────────────────
MOODLE_DB_HOST=host.docker.internal
MOODLE_DB_PORT=5432
MOODLE_DB_NAME=zajunadb
MOODLE_DB_USER=reportes_ro
MOODLE_DB_PASSWORD=ro_secret

# ── Redis ───────────────────────────────────────────
REDIS_HOST=redis
REDIS_PORT=6379

# ── Seguridad (JWT) ─────────────────────────────────
REPORTES_SECRET_KEY=<valor_aleatorio_largo>   # NO dejar "change-me..."

# ── Moodle SSO (Web Services) ───────────────────────
MOODLE_URL=https://zajunavideo5.com/zajuna     # acceso desde el contenedor
MOODLE_WS_SERVICE=reportes_zajuna
MOODLE_HOST_HEADER=zajunavideo5.com            # debe coincidir con wwwroot
MOODLE_PUBLIC_URL=https://zajunavideo5.com/zajuna

# ── Frontend / proxy ────────────────────────────────
REPORTES_FRONTEND_URL=https://zajunavideo5.com/analitica
REPORTES_BASE_PATH=/analitica                  # debe coincidir con location del proxy

# ── CORS ────────────────────────────────────────────
REPORTES_CORS_ORIGINS=https://zajunavideo5.com

# ── Archivos ────────────────────────────────────────
REPORTES_OUTPUT_DIR=/app/reportes_generados
REPORTES_MAX_FILES_PER_USER=100
```

> **`REPORTES_SECRET_KEY`**: si queda en `change-me-in-production`, el API **no arranca**
> (falla por diseño). Generar uno: `openssl rand -hex 32`.
>
> **`REPORTES_DOCS_ENABLED`**: no ponerla (o `false`) en producción — deshabilita
> `/api/docs` y `/api/redoc`. Solo `true` en local.

---

## 6. Configuración de Moodle (plugin + web service)

La integración SSO tiene dos piezas: un **web service** que emite tokens y el **plugin
`local_reporteszajuna`** que agrega el enlace/botón y redirige con el token.

### 6.1 Crear el Web Service

En Moodle como admin: **Administración del sitio → Extensiones → Servicios web**.

1. **Habilitar servicios web**: `Administración del sitio → Características avanzadas →
   Habilitar servicios web` = Sí. Habilitar el protocolo **REST**.
2. **Crear servicio externo**: `Servicios web → Servicios externos → Agregar`.
   - Nombre: `Reportes ZAJUNA`
   - **Nombre corto (shortname): `reportes_zajuna`** ← debe coincidir con
     `MOODLE_WS_SERVICE` y con el que busca `redirect.php`.
   - Habilitado: Sí.
   - "Solo usuarios autorizados": según política (no es obligatorio; el token se crea por
     usuario en `redirect.php`).
   - No requiere agregar funciones — el login solo necesita que el token exista en
     `mdl_external_tokens`.

> El API valida el token consultando directamente `mdl_external_tokens` en la BD de
> Moodle (no llama funciones WS). Basta con que el servicio exista, esté habilitado y el
> plugin emita el token.

### 6.2 Instalar el plugin

El plugin vive en `local/reporteszajuna` dentro del Moodle:

```bash
# Copiar la carpeta del plugin al Moodle (ajustar rutas)
sudo cp -r /ruta/al/plugin/reporteszajuna /var/www/zajuna/local/
sudo chown -R www-data:www-data /var/www/zajuna/local/reporteszajuna
```

Archivos del plugin:

| Archivo          | Función                                                        |
|------------------|---------------------------------------------------------------|
| `version.php`    | versión (`2026062801`), requiere Moodle 4.3                    |
| `db/access.php`  | define capability `local/reporteszajuna:view` + archetypes     |
| `db/upgrade.php` | inserta capability + concede a roles custom de ZAJUNA          |
| `lib.php`        | `has_capability` + agrega enlace en navegación de usuario      |
| `settings.php`   | ajuste `reportes_url` (URL del API) en admin                   |
| `redirect.php`   | crea/reusa token y redirige a `/api/auth/moodle-autologin`     |

Ejecutar el upgrade en Moodle: **Administración del sitio → Notificaciones** (o CLI):

```bash
sudo -u www-data php /var/www/zajuna/admin/cli/upgrade.php
sudo -u www-data php /var/www/zajuna/admin/cli/purge_caches.php
```

### 6.3 Configurar la URL del API en el plugin

**Administración del sitio → Extensiones → Local → Reportes ZAJUNA**, campo
`reportes_url`:

- Producción: `https://zajunavideo5.com/analitica` (o la URL pública del API tras proxy).
- Local: `http://localhost:8089`.

`redirect.php` redirige a `<reportes_url>/api/auth/moodle-autologin?token=...`.

### 6.4 Permisos (quién ve el botón)

La capability `local/reporteszajuna:view` controla el acceso. Por diseño la ven **todos
los roles menos aprendiz (student) e invitado**:

- `db/access.php` la concede a: manager, coursecreator, editingteacher, teacher.
- `db/upgrade.php` la concede a roles custom de ZAJUNA (support, academiccoordinator,
  virtualdinamizador, training, dataanalyst, etc.).
- student y guest → `CAP_PREVENT`.

Para ajustar por rol: **Administración del sitio → Usuarios → Permisos → Definir roles**
→ editar rol → buscar `local/reporteszajuna:view`. El botón/enlace aparece **solo** si el
usuario tiene la capability (`lib.php` la valida con `has_capability`).

### 6.5 Flujo SSO resumido

```
Usuario en Moodle → clic "Reportes" → redirect.php
   → crea token en mdl_external_tokens (servicio reportes_zajuna)
   → redirige a  <reportes_url>/api/auth/moodle-autologin?token=XXX
API (moodle-autologin):
   → busca el token en mdl_external_tokens (JOIN mdl_user)
   → valida capability del usuario
   → emite JWT propio (HS256) y aterriza al usuario en la UI
```

---

## 7. Reverse proxy

El API escucha en `8089`. En producción va detrás de nginx/apache bajo la ruta
`/analitica`. `REPORTES_BASE_PATH` debe coincidir con el `location`.

### nginx (ejemplo)

```nginx
location /analitica/ {
    proxy_pass http://127.0.0.1:8089/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 300s;   # reportes/preview pesados
}
```

### apache (ejemplo)

```apache
ProxyPreserveHost On
ProxyPass        /analitica/ http://127.0.0.1:8089/
ProxyPassReverse /analitica/ http://127.0.0.1:8089/
ProxyTimeout 300
```

> Sin proxy (acceso directo/local): dejar `REPORTES_BASE_PATH=` vacío y usar
> `http://IP:8089`. El puerto ya se publica en `docker-compose.yml`.

---

## 8. Levantar los contenedores

### Producción

```bash
cd /opt/reportes
docker compose up -d --build --remove-orphans
```

### Local

```bash
ENV_FILE=.env.local docker compose up -d --build --remove-orphans
```

Notas:
- `--build` es **obligatorio** tras cambios en `api/routers`, `api/main.py`, `jobs.py` o
  `frontend/` (no están montados como volumen).
- `api/sql` y `api/reportes` **sí** están montados (`:ro`), pero el caché SQL por proceso
  requiere reiniciar el contenedor tras editarlos.
- `docker compose restart` **no** respeta `ENV_FILE` — siempre usar `up -d`.
- `--remove-orphans` limpia el viejo contenedor `reportes_db` si existía.

---

## 9. Verificación

```bash
# Health del API
curl -s http://localhost:8089/api/health

# Lista de reportes
curl -s http://localhost:8089/api/reportes

# Logs
docker logs -f reportes_api
docker logs -f reportes_worker      # debe decir "Scheduler thread iniciado" y "Worker listo"
```

Comprobar que el worker conecta a la control DB:
```
[INFO] ... Control DB inicializado
```

Prueba funcional: entrar por Moodle (botón Reportes) → generar un reporte pequeño →
verificar que pasa PENDIENTE → PROCESANDO → FINALIZADO y descarga.

---

## 10. Mantenimiento

### Respaldo de la control DB (recomendado — cron del SO)

```bash
# /etc/cron.d/reportes-backup
0 2 * * *  postgres  pg_dump -d reportes | gzip > /var/backups/reportes_$(date +\%F).sql.gz
```

### Archivos generados

- Volumen `reportes_generados`. Se conservan los 100 más recientes por usuario; los
  anteriores se marcan `EXPIRADO` y se borran del volumen (`cleanup_old_report_files`).

### Actualizar la app

```bash
cd /opt/reportes
git pull
docker compose up -d --build --remove-orphans
```

### Migrar datos si vienes de la BD dockerizada

Ver `docs/bd-externa.md` §"Migrar datos" (dump del contenedor → restore en Postgres del
host). El volumen viejo `reportes_reportes_db` puede quedar como respaldo hasta validar.

---

## 11. Troubleshooting

| Síntoma | Causa probable | Fix |
|---------|----------------|-----|
| API no arranca, error `secret_key` | `REPORTES_SECRET_KEY=change-me...` | Poner clave real (`openssl rand -hex 32`) |
| "No se pudo verificar el token en la BD de Moodle" | `.env` apunta a BD Moodle equivocada, o WS `reportes_zajuna` inexistente/deshabilitado | Revisar `MOODLE_DB_NAME` + crear/habilitar servicio web |
| Login local falla tras rebuild | Se levantó sin `ENV_FILE=.env.local` (usó `.env`) | `ENV_FILE=.env.local docker compose up -d` |
| Cambios de frontend no se ven | Caché del navegador / archivos no montados | Ya hay cache-busting (`?v=mtime`); rebuild con `--build` |
| Contenedor no conecta a Postgres del host | `pg_hba.conf` / `listen_addresses` | Abrir subred `172.16.0.0/12`, `listen_addresses='*'`, restart postgres |
| Preview tarda y da 503 | Reporte de agregación pesada (>30s SLA) | Es por diseño: acota filtros o usa generación (no preview) |
| Botón "Reportes" no aparece en Moodle | Usuario sin capability | Verificar rol tiene `local/reporteszajuna:view` |
| `git push` "could not read Username" | Shell no interactivo sin credenciales | Correr `! git push origin <rama>` interactivo con PAT |

---

## 12. Checklist de despliegue

- [ ] Docker + Compose v2 instalados
- [ ] Postgres del host con `listen_addresses='*'` y `pg_hba` abierto a subred Docker
- [ ] Rol + base `reportes` creados
- [ ] Usuario `reportes_ro` (solo lectura) sobre la BD de Moodle
- [ ] `.env` completo, con `REPORTES_SECRET_KEY` real
- [ ] Web service `reportes_zajuna` creado y habilitado en Moodle
- [ ] Plugin `local_reporteszajuna` instalado + upgrade + `reportes_url` configurada
- [ ] Reverse proxy `/analitica` → `:8089` (si aplica)
- [ ] `docker compose up -d --build --remove-orphans`
- [ ] `/api/health` OK + worker "Scheduler thread iniciado"
- [ ] Prueba SSO desde Moodle + generar un reporte
- [ ] Cron de respaldo de la control DB
