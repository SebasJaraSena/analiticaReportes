# Flujo de generación de reportes

Recorrido completo desde que el usuario solicita un reporte hasta que lo descarga.

## Arquitectura en una línea

Cola asíncrona con **RQ (Redis Queue)** + worker dedicado. El API encola y responde al
instante; un worker separado ejecuta el trabajo pesado en segundo plano. El frontend
consulta el estado por *polling*.

| Componente | Rol |
|---|---|
| `reportes_api` | Recibe la solicitud, encola el job, sirve estado y descarga |
| Redis | Broker de la cola (db 2, cola `"reportes"`) |
| `reportes_worker` | Ejecuta los jobs RQ + hilo scheduler para programados |
| DB control | Estado de solicitudes/programados (fuente de verdad) |
| Moodle DB | Origen de datos (solo lectura) |

---

## Paso a paso

### 1. Usuario llena filtros y da "Generar"

Browser (`app.js` → `generarReporte()`):

```
POST /api/reportes/registro_usuarios/generar
body: { filtros: {...}, formato: "xlsx" }
```

### 2. API recibe y encola (`routers/reportes.py`)

```
- valida filtros requeridos
- crea Solicitud en DB control → estado PENDIENTE, id=123
- _get_queue().enqueue(process_report_job, 123, job_timeout=3600)
  → mete el job en Redis (cola "reportes")
- responde 202: { solicitud_id: 123 }   ← INSTANTÁNEO, no espera
```

El usuario ya tiene respuesta. El reporte aún no existe.

### 3. Frontend empieza a vigilar

`startPolling(123)` → cada **4 s**:

```
GET /api/solicitudes/123  → lee estado actual
```

Muestra "Procesando… N filas".

### 4. Worker toma el job (`jobs.py` → `process_report_job`)

En el contenedor `reportes_worker`, el hilo RQ saca el job de Redis:

```
a. estado → PROCESANDO, fecha_inicio = now_bogota()
b. carga el SQL del reporte (load_sql)
c. _build_params(filtros) → arma params (arrays vs escalares, %%, etc.)
d. abre cursor SERVER-SIDE en Moodle DB y ejecuta el SQL
e. lee en lotes de 20_000 filas (fetchmany)
   - escribe cada lote a CSV/XLSX en archivo "parte"
   - cada ~50k filas / 5s → actualiza progreso en DB
       (filas_procesadas, mensaje_progreso)
   - chequea si el usuario canceló (estado=CANCELADO) → aborta
f. si filas > límite por archivo → varias partes → ZIP
```

### 5. Cierre del job

```
- 0 filas       → estado SIN_RESULTADOS (sin archivo)
- con datos     → mueve archivo final, estado FINALIZADO,
                  archivo_ruta, archivo_tamano, fecha_fin
- excepción     → estado ERROR, mensaje_error
```

### 6. El polling detecta el final

Siguiente `GET /api/solicitudes/123` devuelve `FINALIZADO`:

```
stopPolling()
muestra "✅ Reporte listo. Descargar ahora"
```

### 7. Descarga (`routers/solicitudes.py`)

```
GET /api/solicitudes/123/descargar
- valida: dueño + estado==FINALIZADO + archivo existe
- FileResponse(archivo_ruta)  → baja el xlsx/csv/zip
```

---

## Diagrama

```
BROWSER          API              REDIS         WORKER            DB / DISCO
  │  generar──────→│
  │               crea Solicitud(PENDIENTE)──────────────────────→ DB
  │               enqueue──────────→[job]
  │ ←──202 id=123──│
  │                                  │
  │  poll 4s ──────→│ lee estado ────────────────────────────────→ DB
  │ ←─PROCESANDO───│                 │
  │                                  └──→ worker saca job
  │                                        ejecuta SQL (cursor stream)
  │                                        escribe archivo ─────────→ DISCO
  │                                        update progreso ─────────→ DB
  │                                        FINALIZADO ──────────────→ DB
  │  poll 4s ──────→│ lee estado ────────────────────────────────→ DB
  │ ←─FINALIZADO───│
  │  descargar─────→│ FileResponse(archivo) ←──────────────────────  DISCO
  │ ←──archivo──────│
```

---

## Lo importante

- **Asíncrono**: el API responde al instante; el trabajo pesado va al worker → la web no
  se cuelga.
- **Polling**: el front pregunta cada 4 s (no hay websocket).
- **Streaming**: cursor server-side + lotes de 20 000 filas → reportes enormes sin agotar
  RAM.
- **Estado en DB**: la `Solicitud` es la "fuente de verdad" que conecta API ↔ worker ↔
  front.

---

## Estados de una solicitud

| Estado | Significado |
|---|---|
| `PENDIENTE` | Encolada, aún no la tomó el worker |
| `PROCESANDO` | Worker ejecutando la consulta y escribiendo el archivo |
| `FINALIZADO` | Listo, archivo descargable |
| `SIN_RESULTADOS` | La consulta no devolvió filas (no se genera archivo) |
| `ERROR` | Falló; `mensaje_error` tiene el detalle |
| `CANCELADO` | El usuario la canceló mientras procesaba |

---

## Reportes programados

El flujo es idéntico **desde el paso 2**, pero quien encola no es el clic del usuario sino
el **hilo scheduler** (`scheduler.py`), un loop dentro del worker que cada **60 s** busca
los programados con `proxima_ejecucion <= now`, los encola (mismo `process_report_job`) y
recalcula la siguiente ejecución con `calc_next()`.

```
Hilo scheduler (cada 60s):          Hilo worker (siempre):
  busca proxima_ejecucion<=now         espera job en Redis
  encola process_report_job  ───────→  lo recibe
  recalcula proxima_ejecucion          ejecuta: query→archivo
  sleep(60)                            marca FINALIZADO
```
