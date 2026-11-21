/* Local review fixture. Every action below updates this page in memory. */
const iconPaths = {
  search: '<circle cx="10" cy="10" r="6.5"/><path d="m15 15 5 5"/>',
  terminal: '<rect x="2" y="4" width="20" height="16" rx="3"/><path d="m6 9 3 3-3 3m6 0h5"/>',
  bookmark: '<path d="M6 3h12v18l-6-4-6 4Z"/>',
  history: '<path d="M3 11a9 9 0 1 1 2 7M3 5v6h6m3-4v6l4 2"/>',
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
const views = ['overview','roadmap','tasks','feature','review','preview','terminal'];
const content = document.querySelector('#content');
const draft = document.querySelector('#draft');
let selectedFile = 0;
let accepted = false;
let screen;
const projects = {
  yab: { name: 'Yab Browser' },
  sunday: { name: 'Sunday', color: '#f1c27b', feature: 'Single-screen sign-in', area: 'Onboarding', goal: 'Let a returning user enter their email and continue from a single screen.' },
  webistory: { name: 'Webistory', color: '#8bc3e6', feature: 'Floating time tracker', area: 'Time tracking', goal: 'Start and stop the current project timer without leaving the active app.' },
  agada: { name: 'Agada', color: '#a6ceaa', feature: 'Dish picker', area: 'Orders', goal: 'Choose dishes and quantities while reviewing an order.' }
};
let project;
let space;
let lastProject = 'yab';
const messages = document.querySelector('#messages');
const context = document.querySelector('#context');
const chats = new Map();
const lastView = new Map();
const scroll = {};
const initialMessages = messages.innerHTML;

function restoreChat(id) {
  if (project === id) return;
  if (project) {
    chats.set(project, {messages: messages.innerHTML, top: messages.scrollTop,
      draft: draft.value, context: context.innerHTML, hidden: context.hidden});
  }
  project = id;
  const item = projects[id];
  const previous = chats.get(id);
  const starter = id === 'yab' ? initialMessages :
    '<div class="day">Today</div><p class="bubble you">What is next for '+item.name+'?</p>'+
    '<p class="bubble them">The next feature is '+item.feature+'. '+item.goal+'</p>'+
    '<button class="chat-link" data-route="feature">'+icon('roadmap')+item.feature+icon('right')+'</button>';
  messages.innerHTML = previous?.messages ?? starter;
  messages.scrollTop = previous?.top ?? 0;
  draft.value = previous?.draft ?? '';
  send.disabled = !draft.value.trim();
  context.innerHTML = previous?.context ?? '';
  context.hidden = previous?.hidden ?? true;
  document.querySelector('#project-title').textContent = item.name;
  document.querySelector('#chat-mark').innerHTML = projectMark(id);
}
function projectMark(id) {
  if (id === 'yab') return '<img src="'+appMark+'" alt="">';
  return '<span style="color:'+projects[id].color+'">'+icon('folder')+'</span>';
}
function projectList() {
  const list = document.querySelector('#project-list');
  if (space === 'Work') {
    list.innerHTML = '<div class="project-entry" aria-current="page">'+icon('layout')+' Home</div>';
    return;
  }
  const query = document.querySelector('#project-search').value.trim().toLowerCase();
  const rows = Object.entries(projects).filter(([,p])=>p.name.toLowerCase().includes(query));
  list.innerHTML = rows.map(([id,p])=>'<button class="project-entry" data-project="'+id+'"'+
    (id === project ? ' aria-current="page"' : '')+'>'+projectMark(id)+p.name+'</button>').join('') ||
    '<small style="padding:8px">No matching projects</small>';
}
function otherProject() {
  const item = projects[project];
  if (screen === 'feature') return '<article class="page">'+roadmapCrumb(item.area)+'<h1>'+item.feature+'</h1><section class="block doc"><h2>Feature definition</h2><p class="body-copy">'+item.goal+'</p></section><div class="block btns">'+buildButton(selectedFeature())+action(icon('chat')+' Discuss feature','data-action="discuss"')+'</div></article>';
  if (screen === 'review') return '<section class="page"><h1>Code review</h1><p class="body-copy">No changes awaiting review in '+item.name+'.</p></section>';
  return '<section class="page"><header class="head"><div class="well">'+projectMark(project)+'</div><h1>'+item.name+'</h1></header><section class="block"><div class="section-heading"><h2>On the roadmap</h2></div><div class="list"><button class="row" data-route="feature"><span class="well small">'+icon('roadmap')+'</span><span><b>'+item.feature+'</b><small>'+item.area+'</small></span><span class="trail">Planned</span>'+icon('right')+'</button></div></section></section>';
}
function pathFor(id, view) {
  return id === 'yab' ? view : id + '/' + view;
}
function chooseProject(id) {
  document.body.classList.remove('sidebar-open','chat-open');
  document.querySelector('#project-search').value = '';
  projectList();
  location.hash = pathFor(id,lastView.get(id) ?? 'overview');
}
function chooseSpace(name) {
  document.querySelector('#spaces').hidePopover();
  if (name === 'Development') chooseProject(lastProject);
  else { document.body.classList.remove('sidebar-open','chat-open'); location.hash = 'work'; }
}
document.querySelector('#project-search').addEventListener('input',projectList);

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
    ${roadmapCrumb('Downloads')}
    <header class="detail-intro"><div><h1>Dock download progress</h1><div class="meta">${status()} · Owner: Codex</div></div></header>
    <div class="feature-doc"><div class="doc"><section><h2>Feature definition</h2><p class="body-copy">See the progress of active downloads from the macOS Dock, even when Yab is in the background. When the last download stops, the plain Yab icon returns.</p></section>
    <section><h2>Acceptance criteria</h2>${checks.map(c=>'<div class="check-row">'+icon('checked')+'<span>'+c+'</span></div>').join('')}</section>
    <section><h2>Latest decision</h2><p class="body-copy">Cancellation clears the bar immediately. If another download is running, its progress stays visible.</p><small style="margin-top:8px">You and Project manager · Yesterday</small></section>
    <div class="btns">${buildButton(selectedFeature())}${action(accepted ? 'View changes' : 'Review changes','data-route="review"',true)}${action(icon('chat')+' Discuss feature','data-action="discuss"')}</div></div>
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
const previewURLs = new Map();
const terminalHistory = new Map();
function toolSurface(title, body) {
  return '<section class="page"><header class="head"><h1>'+title+'</h1></header>'+body+'</section>';
}
function preview() {
  return toolSurface('Preview','<form id="preview-form" class="panel tool-form"><label for="app-url">App URL</label><div><input id="app-url" type="url" required placeholder="http://localhost:3000"><button class="btn primary">Open in browser ↗</button></div></form>');
}
function terminal() {
  const history = terminalHistory.get(project) ?? [];
  return toolSurface('Terminal','<div class="panel terminal-surface"><small>'+projects[project].name+' · Demo shell</small><pre>'+escapeHTML(history.join('\n'))+'</pre><form id="terminal-form"><label for="command">❯</label><input id="command" aria-label="Demo terminal command" autocomplete="off" placeholder="Type help"></form></div>');
}
document.addEventListener('submit', event => {
  event.preventDefault();
  if (event.target.id === 'preview-form') {
    const input = document.querySelector('#app-url');
    const url = new URL(input.value);
    if (!['http:', 'https:'].includes(url.protocol)) {
      input.setCustomValidity('Enter an HTTP or HTTPS address.');
      input.reportValidity();
      return;
    }
    previewURLs.set(project,url.href);
    window.open(url.href,'_blank','noopener,noreferrer');
  }
  if (event.target.id === 'terminal-form') {
    const command = document.querySelector('#command').value.trim();
    if (!command) return;
    const history = terminalHistory.get(project) ?? [];
    const result = command === 'help' ? 'help   pwd   clear' : command === 'pwd' ? '~/Projects/'+projects[project].name : 'Demo shell: type help for available commands.';
    terminalHistory.set(project,command === 'clear' ? [] : [...history,'❯ '+command,result]);
    render();
    document.querySelector('#command').focus();
  }
});
document.addEventListener('input', event => {
  if (event.target.id === 'app-url') {
    event.target.setCustomValidity('');
    previewURLs.set(project,event.target.value);
  }
});
const renderers = {overview,feature,review};
function render() {
  const parts = location.hash.slice(1).split('/');
  if (project && space === 'Development' && screen) scroll[pathFor(project,screen)] = content.scrollTop;
  space = parts[0] === 'work' ? 'Work' : 'Development';
  const dev = space === 'Development';
  document.querySelector('.body').hidden = !dev;
  document.querySelector('#work-home').hidden = dev;
  document.querySelector('.filter').hidden = !dev;
  document.querySelector('#space-name').textContent = space;
  document.querySelector('#space-switch > span:first-child').innerHTML = icon(dev ? 'terminal' : 'folder');
  document.querySelector('#sidebar-heading').textContent = dev ? 'Projects' : 'Tabs';
  document.querySelectorAll('#spaces [data-space]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.space === space)));
  if (!dev) {
    document.querySelector('#compact-title').textContent = document.title = 'Work';
    projectList();
    return;
  }
  const id = Object.hasOwn(projects,parts[0]) ? parts[0] : 'yab';
  restoreChat(id);
  lastProject = project;
  screen = parts.at(-1);
  const taskRoute = screen.startsWith('tasks-') && buildPlans.get(project)?.has(screen.slice(6));
  if (!views.includes(screen) && !selectedFeature() && !taskRoute) screen = 'overview';
  lastView.set(project,screen);
  projectList();
  document.querySelector('#compact-title').textContent = projects[id].name;
  if (screen === 'tasks' || taskRoute) content.innerHTML = tasksPage();
  else if (screen === 'roadmap') content.innerHTML = roadmap();
  else if (screen !== 'feature' && selectedFeature()) content.innerHTML = productSpec(selectedFeature());
  else if (screen === 'preview') {
    content.innerHTML = preview();
    document.querySelector('#app-url').value = previewURLs.get(project) ?? '';
  } else if (screen === 'terminal') content.innerHTML = terminal();
  else content.innerHTML = id === 'yab' ? renderers[screen]() : otherProject();
  document.querySelectorAll('nav [data-route]').forEach(b=>{
    if (b.dataset.route === (taskRoute ? 'tasks' : selectedFeature() ? 'roadmap' : screen)) b.setAttribute('aria-current','page');
    else b.removeAttribute('aria-current');
  });
  content.scrollTop = scroll[pathFor(project,screen)] || 0;
  document.title = ((taskRoute && 'Tasks') || (selectedFeature() && selectedFeature().title) || ({tasks:'Tasks',roadmap:'Roadmap',overview:'Project overview',feature:'Roadmap feature detail',review:'Code review',preview:'Preview',terminal:'Terminal'})[screen])+' · '+projects[id].name;
}
function go(route) {
  document.body.classList.remove('chat-open');
  if (route===screen) return;
  location.hash = pathFor(project,route);
}
function discuss(label, route) {
  const chip = document.querySelector('#context');
  chip.hidden = false;
  chip.replaceChildren();
  const reference = document.createElement('span');
  reference.textContent = label;
  if (route) reference.dataset.spec = route;
  chip.append(reference);
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
  if (!context.hidden) {
    const reference = context.firstElementChild;
    const link = document.createElement(reference.dataset.spec ? 'button' : 'small');
    if (reference.dataset.spec) link.dataset.route = reference.dataset.spec;
    link.className = 'sent-context';
    link.textContent = reference.textContent;
    bubble.prepend(link);
    context.hidden = true;
  }
  messages.append(bubble); bubble.scrollIntoView({block:'nearest'});
  draft.value=''; send.disabled=true;
}
document.addEventListener('click',e=>{
  const b=e.target.closest('button');
  if (!b || b.disabled) return;
  if (b.dataset.space) chooseSpace(b.dataset.space);
  if (b.dataset.project) chooseProject(b.dataset.project);
  if (b.dataset.route) go(b.dataset.route);
  if (b.dataset.build) openBuild(b.dataset.build);
  if (b.dataset.taskIndex !== undefined) {
    const id = currentPlan.get(project);
    const f = productLanes().flatMap(l=>l.features).find(f=>f.id===id);
    discuss(taskRows(f)[Number(b.dataset.taskIndex)].title, 'tasks-'+id);
  }
  if (b.dataset.file!==undefined) { selectedFile=Number(b.dataset.file); render(); document.querySelector('[data-file="'+selectedFile+'"]').focus({preventScroll:true}); }
  switch(b.dataset.action) {
    case 'sidebar':
      document.body.classList.toggle(matchMedia('(max-width:920px)').matches ? 'sidebar-open' : 'rail-closed');
      break;
    case 'chat': document.body.classList.toggle('chat-open'); break;
    case 'discuss': discuss(selectedFeature().title, screen); break;
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
