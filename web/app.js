let configuredServices = [];
let actionInProgress = false;
const $ = (selector) => document.querySelector(selector);

async function loadProject() {
  const response = await fetch('/api/project');
  if (!response.ok) throw new Error(await response.text());

  const project = await response.json();
  configuredServices = project.services || [];
  $('#name').textContent = project.name;
  $('#path').textContent = project.file;
  $('#services').innerHTML = configuredServices.map(service => {
    const disabled = service.selectable ? '' : ' disabled';
    const label = service.self ? '<small>Compose Pilot（通常は操作対象外）</small>' : '';
    return `<label class="service${service.self ? ' self-service' : ''}"><span class="service-name"><input type="checkbox" name="service" value="${escapeHtml(service.name)}"${disabled}><strong>${escapeHtml(service.name)}</strong></span><span data-state="${escapeHtml(service.name)}">未確認</span>${label}<small data-ports="${escapeHtml(service.name)}"></small></label>`;
  }).join('');
  $('#error').hidden = true;
  $('#detail').hidden = false;
  await loadStatus();
}

async function loadStatus() {
  const response = await fetch('/api/status');
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || '状態を取得できませんでした');

  const rows = String(data.output || '').trim().split('\n').filter(Boolean).flatMap(line => {
    try { const parsed = JSON.parse(line); return Array.isArray(parsed) ? parsed : [parsed]; } catch { return []; }
  });
  $('#state').textContent = rows.length ? `${rows.filter(x => /running/i.test(x.State || '')).length}/${rows.length} 起動中` : '停止中';
  $('#state').className = 'badge ' + (rows.some(x => /running/i.test(x.State || '')) ? 'running' : '');
  const byService = Object.fromEntries(rows.map(x => [x.Service || x.Name, x]));
  for (const service of configuredServices) {
    const item = byService[service.name] || {};
    const state = /running/i.test(item.State || '') ? '起動中' : (item.State || item.Status || '停止中');
    const stateNode = document.querySelector(`[data-state="${CSS.escape(service.name)}"]`);
    const portsNode = document.querySelector(`[data-ports="${CSS.escape(service.name)}"]`);
    if (stateNode) stateNode.textContent = state;
    if (portsNode) portsNode.textContent = item.Publishers?.map(port => port.PublishedPort).filter(Boolean).join(', ') || '';
  }
}

async function runAction(action) {
  if (actionInProgress) return;
  const selected = [...document.querySelectorAll('input[name="service"]:checked')].map(input => input.value);
  const includesSelf = configuredServices.some(service => service.self && selected.includes(service.name));
  if (includesSelf && !window.confirm('Compose Pilot自身が停止または再作成され、画面との接続が切れる可能性があります。実行しますか？')) return;

  actionInProgress = true;
  const out = $('#output'); out.textContent = '処理を開始しています…\n'; setBusy(true);
  try {
    const response = await fetch('/api/actions', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({action, services:selected})});
    if (!response.ok) throw new Error(await response.text());
    await readStream(response, out); await loadStatus();
  } catch (error) { out.textContent += `\nエラー: ${error.message}\n`; }
  finally { actionInProgress = false; setBusy(false); }
}

async function followLogs() {
  const out = $('#output'); out.textContent = ''; setBusy(true);
  try {
    const response = await fetch('/api/logs');
    if (!response.ok) throw new Error(await response.text());
    await readStream(response, out);
  } catch (error) { out.textContent += `\nエラー: ${error.message}\n`; }
  finally { setBusy(false); }
}

async function readStream(response, out) {
  const reader = response.body.getReader(), decoder = new TextDecoder();
  while (true) {
    const {value, done} = await reader.read();
    if (done) break;
    out.textContent += decoder.decode(value, {stream:true});
    out.scrollTop = out.scrollHeight;
  }
}

function setBusy(value) { document.querySelectorAll('.actions button').forEach(button => button.disabled = value); }
function escapeHtml(value) { const element=document.createElement('div'); element.textContent=String(value); return element.innerHTML; }

document.querySelectorAll('[data-action]').forEach(button => button.onclick = () => runAction(button.dataset.action));
$('#refresh').onclick = async () => { try { await loadProject(); } catch (error) { showLoadError(error); } };
$('#logs').onclick = followLogs;
$('#clear').onclick = () => $('#output').textContent = '';

function showLoadError(error) {
  $('#detail').hidden = true;
  $('#error').hidden = false;
  $('#error').textContent = `設定を読み込めませんでした: ${error.message}`;
}

loadProject().catch(showLoadError);
