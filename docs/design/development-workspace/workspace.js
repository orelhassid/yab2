/* Local review fixture. Every action below updates this page in memory. */
const iconPaths = {
  sidebar: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16"/>',
  left: '<path d="m14 5-7 7 7 7"/>', right: '<path d="m9 5 7 7-7 7"/>',
  arrow: '<path d="M3 12h17m-6-6 6 6-6 6"/>', down: '<path d="m6 9 6 6 6-6"/>',
  plus: '<path d="M12 4v16M4 12h16"/>', up: '<path d="M12 19V5m-6 6 6-6 6 6"/>',
  folder: '<path d="M3 7V5a1 1 0 0 1 1-1h5l2 3h9a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1Z"/>',
  reload: '<path d="M20 8a8 8 0 1 0 .4 7M20 3v5h-5"/>',
  branch: '<circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="6" r="2"/><path d="M6 7v10m0-2c0-5 12 0 12-7"/>',
  chat: '<path d="M5 4h12a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3h-6l-6 4v-4a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3Z"/><path d="M7 9h8m-8 4h5"/>',
  roadmap: '<rect x="2" y="4" width="8" height="7" rx="2"/><rect x="14" y="13" width="8" height="7" rx="2"/><path d="M6 11v3a3 3 0 0 0 3 3h5"/>',
  diff: '<rect x="3" y="3" width="18" height="18" rx="3"/><path d="M6 8h6M9 5v6m3 5h6"/>',
  check: '<path d="m4 12 5 5L20 6"/>', checked: '<circle cx="12" cy="12" r="9"/><path d="m7.5 12 3 3 6-6"/>',
  file: '<path d="M5 3h9l5 5v13H5Zm9 0v6h5"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v4h16v-4"/>',
  close: '<path d="m5 5 14 14M19 5 5 19"/>',
  layout: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M3 10h18m-12 0v10"/>',
  commit: '<circle cx="12" cy="12" r="4"/><path d="M2 12h6m8 0h6"/>',
  list: '<path d="M9 6h12M9 12h12M9 18h12M3 6h1m-1 6h1m-1 6h1"/>'
};
function icon(name) {
  return '<svg class="i" aria-hidden="true" viewBox="0 0 24 24">' + iconPaths[name] + '</svg>';
}
for (const el of document.querySelectorAll('[data-icon]')) el.innerHTML = icon(el.dataset.icon);
const appMark = '../../../Icon/Mark.png';
const views = ['overview','feature','review'];
const content = document.querySelector('#content');
const draft = document.querySelector('#draft');
let selectedFile = 0;
let accepted = false;
let screen;
const scroll = {};
function escapeHTML(value) {
  return value.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
}
function action(label, target, primary = false) {
  return '<button class="btn ' + (primary ? 'primary' : '') + '" ' + target + '>' + label + '</button>';
}
function scene() {
  const tile = (label, bar) => '<div class="tile-state"><div class="dock-tile"><img alt="" src="' + appMark + '">' + (bar ? '<i class="track"></i>' : '') + '</div>' + label + '</div>';
  return '<div class="dock-scene" aria-label="Dock icon before and after cancellation"><div class="dock-preview">' + tile('Downloading',true) + icon('arrow') + tile('Canceled',false) + '</div></div>';
}
function status() {
  return '<span class="label ' + (accepted ? 'success' : '') + '"><i class="dot"></i>' + (accepted ? 'Accepted' : 'Ready for review') + '</span>';
}
function overview() {
  return `<section class="page">
    <header class="head"><img class="project-icon" src="${appMark}" alt=""><div><h1>Yab Browser</h1><div class="meta">${icon('folder')} orelhassid/yab2 <span>·</span> ${icon('branch')} main</div></div></header>
    <div class="section-heading"><h2>${accepted ? 'Recently accepted' : 'Needs your review'}</h2></div>
    <div class="feature-hero"><div class="feature-copy">${status()}<h2>Dock download progress</h2><p>Clear the Dock indicator when the last active download is canceled.</p>
      <div class="btns">${action(accepted ? 'View changes' : 'Review changes','data-route="review"',true)}${action('Open feature','data-route="feature"')}</div></div>${scene()}</div>
    <section class="block"><div class="section-heading"><h2>On the roadmap</h2></div><div class="list">
      <button class="row" data-route="feature"><span class="well small">${icon('download')}</span><span><b>Downloads</b><small>Dock download progress</small></span><span class="trail">${accepted ? '3 of 3 tasks' : '2 of 3 tasks'}</span>${icon('right')}</button>
      <div class="row"><span class="well small">${icon('layout')}</span><span><b>Navigation</b><small>Compact header controls</small></span><span class="trail">Planned</span></div>
    </div></section>
    <section class="block"><div class="section-heading"><h2>Since your last visit</h2></div><ul class="timeline">
    ${accepted ? '<li><time>Just now</time>' + icon('checked') + 'You accepted Dock download progress</li>' : ''}
    <li><time>10:42 AM</time>${icon('checked')} Dock progress checks passed</li>
    <li><time>10:39 AM</time>${icon('diff')} Codex updated the cancellation behavior</li>
    <li><time>Yesterday</time>${icon('roadmap')} You added cancellation to the feature scope</li></ul></section></section>`;
}
function feature() {
  const checks = ['Combine active downloads across windows into one indicator.',
    'Keep the bar visible while at least one download is active.',
    'Restore the plain icon when the final download ends or is canceled.'];
  return `<article class="page">
    <div class="crumb">Product ${icon('right')} Roadmap ${icon('right')} Downloads</div>
    <header class="detail-intro"><div><h1>Dock download progress</h1><div class="meta">${status()} · Owner: Codex</div></div></header>
    <div class="feature-doc"><div class="doc"><section><h2>Feature definition</h2><p class="body-copy">See the progress of active downloads from the macOS Dock, even when Yab is in the background. When the last download stops, the plain Yab icon returns.</p></section>
    <section><h2>Acceptance criteria</h2>${checks.map(c=>'<div class="check-row">'+icon('checked')+'<span>'+c+'</span></div>').join('')}</section>
    <section><h2>Latest decision</h2><p class="body-copy">Cancellation clears the bar immediately. If another download is running, its progress stays visible.</p><small style="margin-top:8px">You and Project manager · Yesterday</small></section>
    <div class="btns">${action(accepted ? 'View changes' : 'Review changes','data-route="review"',true)}${action(icon('chat')+' Discuss feature','data-action="discuss"')}</div></div>
    <div class="info-side">${scene()}<section class="panel"><h3>Downloads roadmap</h3><ol class="lane"><li class="done"><i></i>Downloads preview</li><li class="current"><i></i>Dock download progress</li><li><i></i>Retry interrupted downloads</li></ol></section></div>
    </div></article>`;
}
// Representative hunks for the review design, using the names from Yab's Dock implementation.
const files = [
  {title:'DockProgress.swift', path:'Sources/Fast', hunk:'@@ report(_:_:)', start:41, lines:[
    [' ','func report(_ window: ObjectIdentifier,'],[' ','            _ downloads: [Bytes]) {'],
    ['-','    guard !downloads.isEmpty else { return }'],['-','    windows[window] = downloads'],
    ['+','    windows[window] = downloads.isEmpty'],['+','        ? nil : downloads'],
    [' ','    show(Self.fraction(windows.values.flatMap { $0 }))'],[' ','}']]},
  {title:'DockProgressTests.swift', path:'Tests/FastTests', hunk:'@@ windowsAddUpAndTheBarGoesWithTheLast()', start:47, lines:[
    [' ','dock.report(first, [])'],[' ','#expect(dock.shown == 0.7)'],
    ['+','dock.report(second, [])'],['+','#expect(dock.shown == nil)'],['+','#expect(NSApp.dockTile.contentView == nil)']]}
];
function stats(file) {
  const count = sign => file.lines.filter(l=>l[0]===sign).length;
  return '<span class="add-text">+'+count('+')+'</span> <span class="del-text">−'+count('-')+'</span>';
}
function review() {
  const f = files[selectedFile];
  let before = f.start, after = f.start;
  const rows = f.lines.map(([sign,code])=>{
    const oldLine = sign==='+' ? '' : before++;
    const newLine = sign==='-' ? '' : after++;
    const type = sign==='+' ? 'add' : sign==='-' ? 'del' : '';
    return '<div class="code-line '+type+'"><span class="number">'+oldLine+'</span><span class="number">'+newLine+'</span><span class="sign">'+sign+'</span>'+escapeHTML(code)+'</div>';
  }).join('');
  return `<section class="page">
    <div class="crumb">Code ${icon('right')} Review ${icon('right')} <button data-route="feature">Downloads</button></div>
    <div class="detail-intro"><div><h1>Review changes</h1><div class="review-meta"><button class="crumb" style="margin:0;padding:0;color:var(--blue)" data-route="feature">Dock download progress</button> · Codex</div></div>
    ${action(accepted ? icon('check')+' Accepted' : 'Accept changes','data-action="accept" '+(accepted ? 'disabled' : ''),true)}</div>
    <div class="review-meta">${icon('branch')} dock-progress ${icon('arrow')} main <span>·</span> 2 files <span class="add-text">+5</span><span class="del-text">−2</span></div>
    <div class="review-grid"><div class="file-list panel"><h3>Changed files</h3>
    ${files.map((file,i)=>'<button class="file" data-file="'+i+'" aria-pressed="'+(i===selectedFile)+'">'+icon('file')+file.title+'</button>').join('')}</div>
    <section class="diff panel"><div class="file-top">${icon('file')} <span>${f.path}/<b>${f.title}</b></span><span class="stats">${stats(f)}</span></div>
    <div class="code-scroll"><div class="code-lines"><div class="hunk">${f.hunk}</div>${rows}</div></div>
    <div class="diff-footer">${action(icon('chat')+' Discuss change','data-action="discuss-file"')}</div></section></div>
    <section class="block"><div class="section-heading"><h2>Verification</h2></div><details class="checks-box panel" open><summary><span class="success-text">${icon('checked')}</span> 2 checks passed</summary><ul><li>Another download in progress keeps its bar.</li><li>Canceling the last download clears the Dock tile.</li></ul></details></section></section>`;
}
const renderers = {overview,feature,review};
function render() {
  screen = location.hash.slice(1);
  if (!views.includes(screen)) screen = 'overview';
  content.innerHTML = renderers[screen]();
  document.querySelectorAll('nav [data-route]').forEach(b=>{
    if (b.dataset.route===screen) b.setAttribute('aria-current','page');
    else b.removeAttribute('aria-current');
  });
  content.scrollTop = scroll[screen] || 0;
  document.title = ({overview:'Project overview',feature:'Roadmap feature detail',review:'Code review'})[screen]+' · Yab Browser';
}
function go(route) {
  document.body.classList.remove('chat-open');
  if (route===screen) return;
  scroll[screen] = content.scrollTop;
  location.hash = route;
}
function discuss(label) {
  const chip = document.querySelector('#context');
  chip.hidden = false;
  chip.textContent = label;
  const close = document.createElement('button');
  close.textContent = '×'; close.dataset.action = 'remove-context'; close.ariaLabel = 'Remove context';
  chip.append(close);
  if (matchMedia('(max-width:720px)').matches) document.body.classList.add('chat-open');
  draft.focus();
}
const send = document.querySelector('#send');
draft.addEventListener('input',()=>{send.disabled = !draft.value.trim()});
function addMessage() {
  if (!draft.value.trim()) return;
  const bubble = document.createElement('p');
  bubble.className = 'bubble you';
  bubble.textContent = draft.value.trim();
  const messages = document.querySelector('#messages');
  messages.append(bubble); bubble.scrollIntoView({block:'nearest'});
  draft.value=''; send.disabled=true;
}
document.addEventListener('click',e=>{
  const b=e.target.closest('button');
  if (!b || b.disabled) return;
  if (b.dataset.route) go(b.dataset.route);
  if (b.dataset.file!==undefined) { selectedFile=Number(b.dataset.file); render(); document.querySelector('[data-file="'+selectedFile+'"]').focus({preventScroll:true}); }
  switch(b.dataset.action) {
    case 'chat': document.body.classList.toggle('chat-open'); break;
    case 'discuss': discuss('Dock download progress'); break;
    case 'discuss-file': discuss(files[selectedFile].title); break;
    case 'remove-context': document.querySelector('#context').hidden=true; draft.focus(); break;
    case 'send': addMessage(); break;
    case 'accept': {
      accepted = true;
      const card = document.querySelector('.run-card');
      card.querySelector('b').textContent = 'Changes accepted';
      card.querySelector('small').textContent = 'View reviewed diff · 2 files';
      render();
      break;
    }
  }
});
window.addEventListener('hashchange',render);
render();
