let selected = null;
let configuredServices = [];
const $ = (s) => document.querySelector(s);

async function loadProjects() {
  const projects = await fetch('/api/projects').then(r => r.json());
  $('#projects').innerHTML = '';
  for (const p of projects) {
    const button = document.createElement('button');
    button.className = 'project' + (selected?.id === p.id ? ' selected' : '');
    button.innerHTML = `<strong>${escapeHtml(p.name)}</strong><small>${escapeHtml(p.relative + '/' + p.file)}</small>`;
    button.onclick = () => selectProject(p);
    $('#projects').append(button);
  }
  if (!projects.length) $('#projects').innerHTML = '<p class="muted">compose.yamlが見つかりません</p>';
}

async function selectProject(p) {
  selected = p; $('#empty').hidden = true; $('#detail').hidden = false;
  $('#name').textContent = p.name; $('#path').textContent = p.relative + '/' + p.file;
  await loadProjects(); await loadConfig(); await loadStatus();
}

async function loadConfig() {
  if (!selected) return;
  const response = await fetch(`/api/projects/${selected.id}/config`);
  if (!response.ok) { $('#output').textContent = await response.text(); configuredServices = []; return; }
  configuredServices = (await response.json()).services || [];
}

async function loadStatus() {
  if (!selected) return;
  const data = await fetch(`/api/projects/${selected.id}/status`).then(r => r.json());
  const rows = String(data.output || '').trim().split('\n').filter(Boolean).flatMap(line => {
    try { const parsed = JSON.parse(line); return Array.isArray(parsed) ? parsed : [parsed]; } catch { return []; }
  });
  $('#state').textContent = rows.length ? `${rows.filter(x => /running/i.test(x.State || '')).length}/${rows.length} 起動中` : '停止中';
  $('#state').className = 'badge ' + (rows.some(x => /running/i.test(x.State || '')) ? 'running' : '');
  const byService = Object.fromEntries(rows.map(x => [x.Service || x.Name, x]));
  $('#services').innerHTML = configuredServices.length ? configuredServices.map(name => {
    const x = byService[name] || {};
    const state = /running/i.test(x.State || '') ? '起動中' : (x.State || x.Status || '停止中');
    return `<label class="service"><span class="service-name"><input type="checkbox" name="service" value="${escapeHtml(name)}"><strong>${escapeHtml(name)}</strong></span><span>${escapeHtml(state)}</span><small>${escapeHtml(x.Publishers?.map(p => p.PublishedPort).filter(Boolean).join(', ') || '')}</small></label>`;
  }).join('') : '<p class="muted">サービスを読み込めませんでした</p>';
}

async function runAction(action) {
  if (!selected) return;
  const out = $('#output'); out.textContent = '処理を開始しています…\n'; setBusy(true);
  try {
    const services = [...document.querySelectorAll('input[name="service"]:checked')].map(x => x.value);
    const response = await fetch('/api/actions', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({projectId:selected.id, action, services})});
    if (!response.ok) throw new Error(await response.text());
    await readStream(response, out); await loadStatus();
  } catch (e) { out.textContent += `\nエラー: ${e.message}\n`; }
  finally { setBusy(false); }
}

async function followLogs() {
  if (!selected) return;
  const out = $('#output'); out.textContent = ''; setBusy(true);
  try { const response = await fetch(`/api/projects/${selected.id}/logs`); if (!response.ok) throw new Error(await response.text()); await readStream(response, out); }
  catch (e) { out.textContent += `\nエラー: ${e.message}\n`; }
  finally { setBusy(false); }
}

async function readStream(response, out) {
  const reader = response.body.getReader(), decoder = new TextDecoder();
  while (true) { const {value, done} = await reader.read(); if (done) break; out.textContent += decoder.decode(value, {stream:true}); out.scrollTop = out.scrollHeight; }
}
function setBusy(value) { document.querySelectorAll('.actions button').forEach(b => b.disabled = value); }
function escapeHtml(v) { const d=document.createElement('div'); d.textContent=String(v); return d.innerHTML; }
document.querySelectorAll('[data-action]').forEach(b => b.onclick = () => runAction(b.dataset.action));
$('#refresh').onclick = async () => { await loadProjects(); await loadStatus(); };
$('#logs').onclick = followLogs; $('#clear').onclick = () => $('#output').textContent = '';
loadProjects();
