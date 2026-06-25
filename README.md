# Reportes ZAJUNA

Sistema de reportes administrativos pesados para Moodle/ZAJUNA integrado al stack Superset.

## Arquitectura

```
reportes-api     (FastAPI, puerto 8089)  — expone endpoints REST + UI web
reportes-worker  (RQ Worker)             — procesa consultas en segundo plano
Redis            (existente)             — cola de trabajos (DB 2)
PostgreSQL       (existente, superset)   — tabla de control reportes_zajuna_solicitudes
PostgreSQL       (Moodle/ZAJUNA)         — fuente de datos (solo lectura)
```

## Instalación

### 1. Configurar variables de entorno

```bash
cp docker/.env-local.example docker/.env-local
# Editar docker/.env-local con los datos reales de conexión a Moodle
```

Variables requeridas en `docker/.env-local`:
```
MOODLE_DB_HOST=<host>
MOODLE_DB_PORT=5432
MOODLE_DB_NAME=moodle
MOODLE_DB_USER=<usuario_readonly>
MOODLE_DB_PASSWORD=<contraseña>
REPORTES_SECRET_KEY=<valor_aleatorio_seguro>
```

> **Seguridad**: Crear un usuario PostgreSQL de solo lectura para Moodle:
> ```sql
> CREATE USER reportes_ro WITH PASSWORD 'contraseña';
> GRANT CONNECT ON DATABASE moodle TO reportes_ro;
> GRANT USAGE ON SCHEMA public TO reportes_ro;
> GRANT SELECT ON ALL TABLES IN SCHEMA public TO reportes_ro;
> ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO reportes_ro;
> ```

### 2. Levantar

```bash
docker compose -f docker-compose-image-tag.yml up -d --build
```

Solo los servicios nuevos:
```bash
docker compose -f docker-compose-image-tag.yml up -d --build reportes-api reportes-worker
```

### 3. Verificar

```bash
# Health check
curl http://localhost:8089/api/health

# Lista de reportes
curl http://localhost:8089/api/reportes

# Logs del worker
docker logs -f reportes_zajuna_worker

# Logs del API
docker logs -f reportes_zajuna_api
```

### 4. Acceder a la UI

Abrir en el navegador: **http://localhost:8089**

O agregar enlace desde Superset en `tail_js_custom_extra.html`:
```html
<!-- Botón en el menú de Superset -->
<script>
document.addEventListener('DOMContentLoaded', () => {
  // Ver sección de integración abajo
});
</script>
```

## Uso

1. Ingresar correo electrónico en la pantalla principal
2. Seleccionar reporte
3. Configurar filtros
4. Clic en **Generar Reporte**
5. El sistema crea la solicitud y la encola
6. En **Mis Solicitudes** ver estado (PENDIENTE → PROCESANDO → FINALIZADO)
7. Clic en **Descargar** cuando esté FINALIZADO

## Agregar nuevos reportes

1. Crear `api/reportes/nuevo_reporte.py` con definición de filtros
2. Crear `api/sql/nuevo_reporte.sql` con la consulta parametrizada
3. Importar en `api/reportes/registry.py`

### Formato de parámetros SQL (psycopg2)

```sql
-- Usa %(nombre_filtro)s para parámetros
-- Para filtros opcionales usa el patrón:
AND (%(mi_filtro)s IS NULL OR columna = %(mi_filtro)s)
AND (%(texto)s IS NULL OR columna ILIKE '%' || %(texto)s || '%')
AND (%(fecha)s IS NULL OR fecha_col::date >= %(fecha)s::date)
```

## Pruebas

```bash
cd reportes_zajuna
pip install pytest
pytest tests/
```

## Volúmenes

- `reportes_generados`: archivos CSV/XLSX generados, montado en `/app/reportes_generados`
- Persistente entre reinicios de contenedores
- Se conservan los 100 archivos más recientes por usuario; los anteriores se marcan como `EXPIRADO` y se eliminan del volumen.

## Endpoints API

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/reportes` | Lista de reportes disponibles |
| GET | `/api/reportes/{codigo}/filtros` | Definición de filtros |
| POST | `/api/reportes/{codigo}/generar` | Crear solicitud |
| GET | `/api/solicitudes` | Lista solicitudes (`?usuario_email=`) |
| GET | `/api/solicitudes/{id}` | Estado de solicitud |
| GET | `/api/solicitudes/{id}/descargar-email?email=` | Descargar por email |
| GET | `/api/solicitudes/{id}/descargar?token=` | Descargar por token |

Swagger UI: **http://localhost:8089/api/docs**
