'use strict';

const API = window.REPORTES_BASE || '';
let currentReporteCodigo = null;
let selectedFormat = 'xlsx';
let pollingInterval = null;

// ── Auth ─────────────────────────────────────────────────────────────────────
function getToken() { return localStorage.getItem('rz_token'); }
function getEmail() { return localStorage.getItem('rz_email') || ''; }

function setSession(token, email) {
  localStorage.setItem('rz_token', token);
  localStorage.setItem('rz_email', email);
}

function clearSession() {
  localStorage.removeItem('rz_token');
  localStorage.removeItem('rz_email');
}

async function authFetch(url, opts = {}) {
  const token = getToken();
  const headers = Object.assign({}, opts.headers || {});
  if (token) headers['Authorization'] = 'Bearer ' + token;
  const res = await fetch(url, Object.assign({}, opts, { headers }));
  if (res.status === 401) {
    clearSession();
    showLoginScreen('Sesión expirada. Inicia sesión nuevamente.');
    throw new Error('Unauthorized');
  }
  return res;
}

// ── Login / logout ────────────────────────────────────────────────────────────
function showLoginScreen(msg) {
  document.getElementById('app-shell').classList.add('hidden');
  document.getElementById('login-screen').classList.add('active');
  stopPolling();
  if (msg) {
    const el = document.getElementById('login-error');
    el.textContent = msg;
    el.style.display = 'block';
  }
}

function showApp(email) {
  document.getElementById('login-screen').classList.remove('active');
  document.getElementById('app-shell').classList.remove('hidden');
  document.getElementById('user-display').textContent = email;
  loadReportes();
  document.getElementById('nav-reportes').classList.add('active');
}

async function _attemptLogin(endpoint, username, password) {
  const res = await fetch(API + endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  const data = await res.json();
  if (!res.ok) return { ok: false, detail: data.detail, status: res.status };
  return { ok: true, token: data.access_token };
}

async function doLogin() {
  const username = document.getElementById('login-username').value.trim();
  const password = document.getElementById('login-password').value;
  const errEl    = document.getElementById('login-error');
  const btn      = document.getElementById('login-btn');
  errEl.style.display = 'none';

  if (!username || !password) {
    errEl.textContent = 'Ingresa usuario y contraseña.';
    errEl.style.display = 'block';
    return;
  }

  btn.disabled = true;
  btn.textContent = 'Iniciando sesión…';

  try {
    let result = await _attemptLogin('/api/auth/moodle-login', username, password);
    if (!result.ok && (username === 'admin' || result.status === 503)) {
      result = await _attemptLogin('/api/auth/login', username, password);
    }
    if (!result.ok) {
      errEl.textContent = result.detail || 'Credenciales incorrectas.';
      errEl.style.display = 'block';
      return;
    }

    const meRes = await fetch(API + '/api/auth/me', {
      headers: { 'Authorization': 'Bearer ' + result.token },
    });
    const me = await meRes.json();
    if (!meRes.ok) {
      errEl.textContent = 'No se pudo obtener el perfil de usuario.';
      errEl.style.display = 'block';
      return;
    }

    setSession(result.token, me.email);
    showApp(me.email);
    document.getElementById('login-password').value = '';
    document.getElementById('login-username').value  = '';
  } catch (e) {
    if (e.message !== 'Unauthorized') {
      errEl.textContent = 'Error de conexión. Verifica que el servidor esté activo.';
      errEl.style.display = 'block';
    }
  } finally {
    btn.disabled = false;
    btn.textContent = 'Iniciar sesión';
  }
}

async function doLogout() {
  const token = getToken();
  let moodleLogoutUrl = null;
  if (token) {
    try {
      const res = await fetch(API + '/api/auth/logout', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + token },
      });
      if (res.ok) moodleLogoutUrl = (await res.json()).moodle_logout_url;
    } catch (_) {}
  }
  clearSession();
  if (moodleLogoutUrl) window.location.href = moodleLogoutUrl;
  else showLoginScreen(null);
}

document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && document.getElementById('login-screen').classList.contains('active')) {
    doLogin();
  }
});

// ── Navigation ────────────────────────────────────────────────────────────────
function showPage(name) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.getElementById('page-' + name).classList.add('active');
  document.querySelectorAll('nav a').forEach(a => a.classList.remove('active'));
  const navEl = document.getElementById('nav-' + name);
  if (navEl) navEl.classList.add('active');
  stopPolling();
  if (name === 'solicitudes') loadSolicitudes();
  if (name === 'programados') loadProgramados();
}

// ── Reports list ──────────────────────────────────────────────────────────────
async function loadReportes() {
  const grid = document.getElementById('reportes-grid');
  try {
    const res  = await authFetch(API + '/api/reportes');
    const data = await res.json();
    if (!data.length) {
      grid.innerHTML = '<div class="empty">No hay reportes disponibles.</div>';
      return;
    }
    grid.innerHTML = data.map(r => `
      <div class="report-card" onclick="openFiltros('${r.codigo}')">
        <h3>${r.nombre}</h3>
        <p>${r.descripcion}</p>
        <button class="btn btn-primary btn-sm" style="margin-top:.85rem;"
                onclick="event.stopPropagation();openFiltros('${r.codigo}')">
          Configurar y generar
        </button>
      </div>
    `).join('');
  } catch (e) {
    if (e.message !== 'Unauthorized')
      grid.innerHTML = '<div class="empty">Error cargando reportes. Verifica la conexión.</div>';
  }
}

// ── Filters page ──────────────────────────────────────────────────────────────
async function openFiltros(codigo) {
  currentReporteCodigo = codigo;
  showPage('filtros');

  const form = document.getElementById('filtros-form');
  form.innerHTML = '<div style="grid-column:1/-1;padding:.5rem 0;color:var(--muted);font-size:.88rem;">Cargando filtros…</div>';
  document.getElementById('filtros-titulo').textContent   = '';
  document.getElementById('filtros-desc').textContent     = '';
  document.getElementById('filtros-alert').className      = 'hidden';
  document.getElementById('preview-section').classList.add('hidden');
  document.getElementById('preview-table-wrap').innerHTML = '';
  const chart = document.getElementById('preview-chart');
  chart.className = 'hidden';
  chart.innerHTML = '';

  try {
    const res  = await authFetch(API + '/api/reportes/' + codigo + '/filtros');
    const data = await res.json();
    document.getElementById('filtros-titulo').textContent = data.nombre;
    document.getElementById('filtros-desc').textContent   = data.descripcion;
    form.innerHTML = _renderFiltros(data.filtros, 'f_', 'data-filtro');
  } catch (e) {
    if (e.message !== 'Unauthorized')
      showAlert('filtros-alert', 'error', 'Error cargando filtros del reporte.');
  }
}

function _renderFiltros(filtros, idPrefix, dataAttr) {
  return filtros.map(f => {
    if (f.tipo === 'select') {
      const items = (f.opciones || [])
        .filter(o => o.value !== '')
        .map(o => `<label class="checkbox-item">
          <input type="checkbox" ${dataAttr}="${f.nombre}" value="${o.value}"> ${o.label}
        </label>`).join('');
      return `<div class="form-group">
        <label>${f.etiqueta}${f.requerido ? ' *' : ''}</label>
        <div class="checkbox-group" id="${idPrefix}${f.nombre}">${items}</div>
      </div>`;
    }
    return `<div class="form-group">
      <label>${f.etiqueta}${f.requerido ? ' *' : ''}</label>
      <input type="${f.tipo === 'date' ? 'date' : 'text'}"
             id="${idPrefix}${f.nombre}" ${dataAttr}="${f.nombre}"
             placeholder="${f.placeholder || ''}"/>
    </div>`;
  }).join('');
}

// ── Format toggle ─────────────────────────────────────────────────────────────
function selectFormat(fmt) {
  selectedFormat = fmt;
  document.getElementById('fmt-xlsx').classList.toggle('selected', fmt === 'xlsx');
  document.getElementById('fmt-csv').classList.toggle('selected', fmt === 'csv');
}

// ── Collect filters ───────────────────────────────────────────────────────────
function _collectFromContainer(containerId, idPrefix, dataAttr) {
  const filtros = {};
  document.querySelectorAll(`#${containerId} [id^="${idPrefix}"]`).forEach(el => {
    const nombre = el.id.replace(new RegExp('^' + idPrefix), '');
    if (el.classList.contains('checkbox-group')) {
      const checked = Array.from(el.querySelectorAll('input[type=checkbox]:checked')).map(cb => cb.value);
      filtros[nombre] = checked.length > 0 ? checked : null;
    } else {
      filtros[nombre] = el.value.trim() || null;
    }
  });
  return filtros;
}

function collectFiltros() {
  return _collectFromContainer('filtros-form', 'f_', 'data-filtro');
}

// ── Generate report ───────────────────────────────────────────────────────────
async function generarReporte() {
  const filtros = collectFiltros();
  const btn = document.getElementById('btn-generar');
  btn.disabled = true;
  btn.innerHTML = '<span class="spin">⏳</span> Generando…';
  try {
    const res  = await authFetch(API + '/api/reportes/' + currentReporteCodigo + '/generar', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ filtros, formato: selectedFormat }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Error desconocido');
    showAlert('filtros-alert', 'success', `✅ ${data.message} (Solicitud #${data.solicitud_id})`);
    startPolling(data.solicitud_id);
  } catch (e) {
    if (e.message !== 'Unauthorized')
      showAlert('filtros-alert', 'error', '❌ Error: ' + e.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = '⚡ Generar Reporte';
  }
}

// ── Polling ───────────────────────────────────────────────────────────────────
function startPolling(solicitudId) {
  stopPolling();
  pollingInterval = setInterval(async () => {
    try {
      const res  = await authFetch(API + '/api/solicitudes/' + solicitudId);
      const data = await res.json();
      if (data.estado === 'FINALIZADO') {
        stopPolling();
        showAlert('filtros-alert', 'success',
          `✅ Reporte listo. <a href="#" onclick="doDownload(${solicitudId}, event)" style="color:var(--accent);font-weight:600;">Descargar ahora</a>`,
          true);
      } else if (data.estado === 'ERROR') {
        stopPolling();
        showAlert('filtros-alert', 'error', `❌ Error al generar el reporte: ${data.mensaje_error || 'Error desconocido'}`);
      } else if (data.estado === 'CANCELADO') {
        stopPolling();
        showAlert('filtros-alert', 'info', 'Solicitud cancelada.');
      } else if (data.estado === 'PROCESANDO') {
        showAlert('filtros-alert', 'info', progressText(data));
      }
    } catch (_) {}
  }, 4000);
}

function stopPolling() {
  if (pollingInterval) { clearInterval(pollingInterval); pollingInterval = null; }
}

function formatNumber(n) { return Number(n || 0).toLocaleString('es-CO'); }

function progressText(s) {
  const rows    = formatNumber(s.filas_procesadas || 0);
  const parts   = s.partes_generadas || 0;
  const updated = s.fecha_ultimo_progreso
    ? ` · actualizado ${s.fecha_ultimo_progreso.replace('T', ' ').slice(11, 19)}`
    : '';
  return `Procesando: ${rows} filas exportadas · ${parts || 1} parte(s)${updated}`;
}

// ── Solicitudes ───────────────────────────────────────────────────────────────
async function loadSolicitudes() {
  const tbody = document.getElementById('solicitudes-tbody');
  tbody.innerHTML = '<tr><td colspan="9" class="empty"><span class="spin">⏳</span> Cargando…</td></tr>';
  try {
    const res  = await authFetch(API + '/api/solicitudes?limit=100');
    const data = await res.json();
    if (!data.length) {
      tbody.innerHTML = '<tr><td colspan="9" class="empty">No hay solicitudes aún.</td></tr>';
      return;
    }
    tbody.innerHTML = data.map(s => {
      const badgeClass = {
        PENDIENTE: 'badge-pending', PROCESANDO: 'badge-process',
        FINALIZADO: 'badge-done',   ERROR: 'badge-error', CANCELADO: 'badge-error',
      }[s.estado] || 'badge-pending';

      const size = s.archivo_tamano
        ? (s.archivo_tamano > 1048576
            ? (s.archivo_tamano / 1048576).toFixed(1) + ' MB'
            : (s.archivo_tamano / 1024).toFixed(0) + ' KB')
        : '—';

      const fmtDate = dt => dt ? dt.replace('T', ' ').slice(0, 16) : '—';
      const progress = (s.filas_procesadas || s.partes_generadas || ['PENDIENTE','PROCESANDO'].includes(s.estado))
        ? `<strong>${formatNumber(s.filas_procesadas || 0)}</strong> filas<br>
           <span class="text-muted text-sm">${s.partes_generadas || 1} parte(s)</span>`
        : '—';

      const actionBtn = s.estado === 'FINALIZADO'
        ? `<button class="btn btn-primary btn-sm" onclick="doDownload(${s.id}, event)">⬇ Descargar</button>`
        : s.estado === 'ERROR'
        ? `<span title="${s.mensaje_error || ''}" class="text-sm" style="color:var(--danger);cursor:help;">Ver error ⓘ</span>`
        : ['PENDIENTE','PROCESANDO'].includes(s.estado)
        ? `<button class="btn btn-danger btn-sm" onclick="cancelSolicitud(${s.id}, event)">Cancelar</button>`
        : s.estado === 'CANCELADO'
        ? `<span class="text-muted text-sm">Cancelado</span>`
        : `<span class="badge ${badgeClass}">${s.estado}</span>`;

      return `<tr>
        <td>${s.id}</td>
        <td><strong>${s.reporte_nombre}</strong><br><span class="text-muted text-sm">${s.reporte_codigo}</span></td>
        <td>${(s.formato || 'xlsx').toUpperCase()}</td>
        <td><span class="badge ${badgeClass}">${s.estado}</span></td>
        <td class="nowrap">${progress}</td>
        <td class="nowrap">${fmtDate(s.fecha_solicitud)}</td>
        <td class="nowrap">${fmtDate(s.fecha_fin)}</td>
        <td>${size}</td>
        <td>${actionBtn}</td>
      </tr>`;
    }).join('');
  } catch (e) {
    if (e.message !== 'Unauthorized')
      tbody.innerHTML = '<tr><td colspan="9" class="empty">Error cargando solicitudes.</td></tr>';
  }
}

async function doDownload(solicitudId, event) {
  if (event) event.preventDefault();
  try {
    const res = await authFetch(API + '/api/solicitudes/' + solicitudId + '/descargar-email');
    if (!res.ok) { alert((await res.json()).detail || 'Error al descargar.'); return; }
    const blob = await res.blob();
    const cd   = res.headers.get('content-disposition') || '';
    const nameMatch = cd.match(/filename="?([^"]+)"?/);
    const filename  = nameMatch ? nameMatch[1] : `reporte_${solicitudId}`;
    const url = URL.createObjectURL(blob);
    const a   = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    URL.revokeObjectURL(url);
  } catch (e) {
    if (e.message !== 'Unauthorized') alert('Error al descargar el archivo.');
  }
}

async function cancelSolicitud(solicitudId, event) {
  if (event) event.preventDefault();
  if (!confirm('¿Cancelar esta solicitud?')) return;
  try {
    const res  = await authFetch(API + '/api/solicitudes/' + solicitudId + '/cancelar', { method: 'POST' });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'No se pudo cancelar.');
    showAlert('solicitudes-alert', 'info', 'Solicitud cancelada.');
    loadSolicitudes();
  } catch (e) {
    if (e.message !== 'Unauthorized') alert('Error al cancelar: ' + e.message);
  }
}

// ── Preview ───────────────────────────────────────────────────────────────────
function renderPreviewChart(data) {
  const chart = document.getElementById('preview-chart');
  if (currentReporteCodigo !== 'uso_herramientas' || !data?.rows?.length) {
    chart.className = 'hidden'; chart.innerHTML = ''; return;
  }
  const toolColumns = data.columns.filter(c => c.startsWith('Cantidad de '));
  const totals = toolColumns.map(col => ({
    label: col.replace('Cantidad de ', ''),
    total: data.rows.reduce((sum, row) => sum + (Number(row[col]) || 0), 0),
  })).filter(item => item.total > 0);

  if (!totals.length) { chart.className = 'hidden'; chart.innerHTML = ''; return; }

  const maxValue = Math.max(...totals.map(x => x.total), 1);
  const bars = totals.map(item => {
    const height = Math.max(2, Math.round((item.total / maxValue) * 130));
    const label  = item.label.length > 13 ? item.label.slice(0, 12) + '…' : item.label;
    return `<div class="bar-item" title="${item.label}: ${formatNumber(item.total)}">
      <div class="bar-value">${formatNumber(item.total)}</div>
      <div class="bar" style="height:${height}px"></div>
      <div class="bar-label">${label}</div>
    </div>`;
  }).join('');

  chart.className = 'chart-panel';
  chart.innerHTML = `<h4>Resumen visual de herramientas</h4>
    <div class="chart-subtitle">Totales calculados con las filas mostradas en la vista previa.</div>
    <div class="bar-chart">${bars}</div>`;
}

async function previewReporte() {
  const btn     = document.getElementById('btn-preview');
  const section = document.getElementById('preview-section');
  const wrap    = document.getElementById('preview-table-wrap');
  const countEl = document.getElementById('preview-count');
  const chart   = document.getElementById('preview-chart');

  btn.disabled = true;
  btn.innerHTML = '<span class="spin">⏳</span> Cargando…';
  section.classList.remove('hidden');
  wrap.innerHTML = '<div class="empty"><span class="spin">⏳</span> Consultando…</div>';
  chart.className = 'hidden'; chart.innerHTML = '';
  countEl.textContent = '';

  try {
    const res  = await authFetch(API + '/api/reportes/' + currentReporteCodigo + '/preview', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ usuario_email: getEmail(), filtros: collectFiltros(), formato: selectedFormat }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Error desconocido');

    renderPreviewChart(data);

    if (!data.rows.length) {
      wrap.innerHTML = '<div class="empty" style="padding:1.5rem">Sin resultados con los filtros actuales.</div>';
      countEl.textContent = '';
      document.getElementById('preview-title').textContent = 'Vista previa — sin resultados';
      return;
    }

    document.getElementById('preview-title').textContent = 'Vista previa';
    countEl.textContent = data.count === 50
      ? 'Mostrando las primeras 50 filas. El reporte completo puede tener más.'
      : `Mostrando ${data.count} fila${data.count !== 1 ? 's' : ''} (resultado total).`;

    const ths = data.columns.map(c => `<th title="${c}">${c}</th>`).join('');
    const trs = data.rows.map(row =>
      '<tr>' + data.columns.map(c => {
        const val     = row[c];
        const display = val === null || val === undefined ? '' : String(val);
        return `<td title="${display.replace(/"/g, '&quot;')}">${display}</td>`;
      }).join('') + '</tr>'
    ).join('');
    wrap.innerHTML = `<table><thead><tr>${ths}</tr></thead><tbody>${trs}</tbody></table>`;
  } catch (e) {
    if (e.message !== 'Unauthorized')
      wrap.innerHTML = `<div class="empty" style="padding:1.5rem;color:var(--danger)">Error: ${e.message}</div>`;
  } finally {
    btn.disabled = false;
    btn.innerHTML = '🔍 Vista previa';
  }
}

// ── Programados ───────────────────────────────────────────────────────────────
const DIAS = ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'];

function _fmtFecha(iso) {
  if (!iso) return '—';
  // Timestamps stored in Colombia time — display directly without UTC conversion
  return iso.replace('T', ' ').slice(0, 16);
}

function _fmtFrecuencia(p) {
  if (p.frecuencia === 'diario')  return 'Diario';
  if (p.frecuencia === 'semanal') return `Semanal (${DIAS[p.dia_semana ?? 0]})`;
  if (p.frecuencia === 'mensual') return `Mensual (día ${p.dia_mes})`;
  return p.frecuencia;
}

async function loadProgramados() {
  const tbody = document.getElementById('prog-tbody');
  tbody.innerHTML = '<tr><td colspan="10" class="empty"><span class="spin">⏳</span> Cargando…</td></tr>';
  try {
    const res  = await authFetch(API + '/api/programados');
    if (!res.ok) { tbody.innerHTML = '<tr><td colspan="10" class="empty">Sin acceso.</td></tr>'; return; }
    const rows = await res.json();
    if (!rows.length) {
      tbody.innerHTML = '<tr><td colspan="10" class="empty">No hay reportes programados. Crea el primero.</td></tr>';
      return;
    }
    const fmtHora = p => String(p.hora).padStart(2, '0') + ':' + String(p.minuto).padStart(2, '0');
    tbody.innerHTML = rows.map(p => `
      <tr>
        <td>${p.id}</td>
        <td>${p.nombre || '<span class="text-muted">—</span>'}</td>
        <td class="prog-reporte-cell" title="${p.reporte_nombre}">${p.reporte_nombre}</td>
        <td>${_fmtFrecuencia(p)}</td>
        <td>${fmtHora(p)}</td>
        <td><span class="prog-formato-badge">${p.formato}</span></td>
        <td class="text-sm nowrap">${_fmtFecha(p.proxima_ejecucion)}</td>
        <td class="text-sm nowrap">${_fmtFecha(p.ultima_ejecucion)}</td>
        <td>${p.activo
          ? '<span class="badge badge-done">Activo</span>'
          : '<span class="badge badge-error">Inactivo</span>'}</td>
        <td class="nowrap">
          <button class="btn btn-outline btn-sm" onclick="toggleProg(${p.id})">${p.activo ? 'Pausar' : 'Activar'}</button>
          <button class="btn btn-delete btn-sm" onclick="deleteProg(${p.id})">Eliminar</button>
        </td>
      </tr>
    `).join('');
  } catch (e) {
    if (e.message !== 'Unauthorized')
      tbody.innerHTML = '<tr><td colspan="10" class="empty">Error cargando.</td></tr>';
  }
}

async function toggleProg(id) {
  try {
    const res = await authFetch(API + '/api/programados/' + id + '/toggle', { method: 'PUT' });
    if (res.ok) loadProgramados();
  } catch (e) { if (e.message !== 'Unauthorized') alert('Error al cambiar estado.'); }
}

async function deleteProg(id) {
  if (!confirm('¿Eliminar esta programación?')) return;
  try {
    const res = await authFetch(API + '/api/programados/' + id, { method: 'DELETE' });
    if (res.ok || res.status === 204) loadProgramados();
  } catch (e) { if (e.message !== 'Unauthorized') alert('Error al eliminar.'); }
}

// ── Programados modal ─────────────────────────────────────────────────────────
let _progReporteList = [];

async function showProgModal() {
  document.getElementById('prog-modal-alert').className = 'hidden';
  document.getElementById('pm-nombre').value = '';
  document.getElementById('pm-reporte').value = '';
  document.getElementById('pm-filtros-wrap').classList.add('hidden');
  document.getElementById('pm-filtros-form').innerHTML = '';
  document.querySelectorAll('input[name="pm-frec"]').forEach(r => r.checked = false);
  updateFrecFields();
  document.querySelector('input[name="pm-fmt"][value="xlsx"]').checked = true;

  const horaEl = document.getElementById('pm-hora');
  if (!horaEl.options.length) {
    for (let h = 0; h < 24; h++) {
      const o = document.createElement('option');
      o.value = h; o.textContent = String(h).padStart(2, '0') + ':00';
      horaEl.appendChild(o);
    }
    horaEl.value = 8;
  }

  const dmEl = document.getElementById('pm-dia-mes');
  if (!dmEl.options.length) {
    for (let d = 1; d <= 31; d++) {
      const o = document.createElement('option');
      o.value = d; o.textContent = 'Día ' + d;
      dmEl.appendChild(o);
    }
  }

  if (_progReporteList.length === 0) {
    try {
      const res = await authFetch(API + '/api/reportes');
      _progReporteList = await res.json();
    } catch (_) {}
  }
  const sel = document.getElementById('pm-reporte');
  sel.innerHTML = '<option value="">— Seleccionar reporte —</option>';
  _progReporteList.forEach(r => {
    const o = document.createElement('option');
    o.value = r.codigo; o.textContent = r.nombre; o.dataset.nombre = r.nombre;
    sel.appendChild(o);
  });

  document.getElementById('prog-modal').classList.add('open');
}

function closeProgModal() {
  document.getElementById('prog-modal').classList.remove('open');
}

function updateFrecFields() {
  const frec = document.querySelector('input[name="pm-frec"]:checked')?.value;
  document.getElementById('pm-dia-semana-wrap').style.display = frec === 'semanal' ? '' : 'none';
  document.getElementById('pm-dia-mes-wrap').style.display    = frec === 'mensual' ? '' : 'none';
}

async function loadProgFiltros() {
  const sel   = document.getElementById('pm-reporte');
  const codigo = sel.value;
  const wrap  = document.getElementById('pm-filtros-wrap');
  const form  = document.getElementById('pm-filtros-form');
  if (!codigo) { wrap.classList.add('hidden'); form.innerHTML = ''; return; }
  try {
    const res  = await authFetch(API + '/api/reportes/' + codigo + '/filtros');
    const data = await res.json();
    form.innerHTML = _renderFiltros(data.filtros, 'pf_', 'data-pfiltro');
    wrap.classList.remove('hidden');
  } catch (e) {
    if (e.message !== 'Unauthorized') { wrap.classList.add('hidden'); form.innerHTML = ''; }
  }
}

function collectProgFiltros() {
  const filtros = {};
  document.querySelectorAll('#pm-filtros-form .checkbox-group[id^="pf_"]').forEach(el => {
    const nombre  = el.id.replace(/^pf_/, '');
    const checked = Array.from(el.querySelectorAll('input[type=checkbox]:checked')).map(cb => cb.value);
    filtros[nombre] = checked.length > 0 ? checked : null;
  });
  document.querySelectorAll('#pm-filtros-form input:not([type=checkbox])[data-pfiltro]').forEach(el => {
    filtros[el.dataset.pfiltro] = el.value.trim() || null;
  });
  return filtros;
}

async function saveProgramado() {
  const alertEl = document.getElementById('prog-modal-alert');
  alertEl.className = 'hidden';
  const btn = document.getElementById('pm-save-btn');
  btn.disabled = true; btn.textContent = 'Guardando…';

  const reporte_codigo = document.getElementById('pm-reporte').value;
  const reporte_nombre = document.getElementById('pm-reporte').selectedOptions[0]?.dataset.nombre || reporte_codigo;
  const frecuencia     = document.querySelector('input[name="pm-frec"]:checked')?.value;
  const hora           = parseInt(document.getElementById('pm-hora').value);
  const minuto         = parseInt(document.getElementById('pm-minuto').value);
  const formato        = document.querySelector('input[name="pm-fmt"]:checked')?.value || 'xlsx';

  if (!reporte_codigo) {
    alertEl.className = 'alert alert-error'; alertEl.textContent = 'Seleccioná un reporte.';
    btn.disabled = false; btn.textContent = 'Guardar programación'; return;
  }
  if (!frecuencia) {
    alertEl.className = 'alert alert-error'; alertEl.textContent = 'Seleccioná una frecuencia.';
    btn.disabled = false; btn.textContent = 'Guardar programación'; return;
  }

  const body = {
    nombre: document.getElementById('pm-nombre').value.trim() || null,
    reporte_codigo, reporte_nombre,
    filtros: collectProgFiltros(),
    formato, frecuencia, hora, minuto,
  };
  if (frecuencia === 'semanal') body.dia_semana = parseInt(document.getElementById('pm-dia-semana').value);
  if (frecuencia === 'mensual') body.dia_mes    = parseInt(document.getElementById('pm-dia-mes').value);

  try {
    const res = await authFetch(API + '/api/programados', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json();
      alertEl.className = 'alert alert-error'; alertEl.textContent = err.detail || 'Error al guardar.';
      return;
    }
    closeProgModal();
    loadProgramados();
  } catch (e) {
    if (e.message !== 'Unauthorized') {
      alertEl.className = 'alert alert-error'; alertEl.textContent = 'Error de conexión.';
    }
  } finally {
    btn.disabled = false; btn.textContent = 'Guardar programación';
  }
}

// ── Alert helper ──────────────────────────────────────────────────────────────
function showAlert(id, type, msg, isHtml = false) {
  const el = document.getElementById(id);
  el.className = 'alert alert-' + (type === 'success' ? 'success' : type === 'info' ? 'info' : 'error');
  if (isHtml) el.innerHTML = msg; else el.textContent = msg;
  el.classList.remove('hidden');
}

// ── Init ──────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  const token = getToken();
  const email = getEmail();
  if (token && email) {
    fetch(API + '/api/auth/me', { headers: { 'Authorization': 'Bearer ' + token } })
      .then(r => { if (r.ok) showApp(email); else { clearSession(); showLoginScreen(null); } })
      .catch(() => showLoginScreen(null));
  } else {
    showLoginScreen(null);
  }
});
