// Build plans live for the duration of the design review.
const buildPlans = new Map([['yab', new Set(['feature'])]]);
const currentPlan = new Map([['yab', 'feature']]);
const dockTasks = [
  {title:'Aggregate transfers across windows', owner:'Codex', state:'Done'},
  {title:'Verify progress with concurrent downloads', owner:'Test agent', state:'Done'},
  {title:'Clear the indicator after cancellation', owner:'Codex', state:'Ready for code review'}
];
function buildButton(f) {
  if (f.state === 'Shipped') return '';
  const built = buildPlans.get(project)?.has(f.id);
  return action(built ? 'View tasks' : 'Build', 'data-build="'+f.id+'"', !built);
}
function openBuild(id) {
  const plans = buildPlans.get(project) ?? new Set();
  if (!plans.has(id)) {
    plans.add(id);
    buildPlans.set(project,plans);
    const f = productLanes().flatMap(l=>l.features).find(f=>f.id===id);
    const link = document.createElement('button');
    link.className = 'chat-link';
    link.dataset.route = 'tasks-'+id;
    link.textContent = 'Task plan · '+f.title;
    messages.append(link);
    messages.scrollTop = messages.scrollHeight;
  }
  currentPlan.set(project,id);
  go('tasks-'+id);
}
function taskRows(f) {
  if (project === 'yab' && f.id === 'feature') return dockTasks.map((t,i)=>({...t,state:i===2 && accepted ? 'Done' : t.state}));
  const checks = f.checks ?? [f.goal];
  return [...checks.map(title=>({title,owner:'Codex',state:'Queued'})),
    {title:'Verify the acceptance criteria',owner:'Test agent',state:'Queued'}];
}
function tasksPage() {
  const plans = buildPlans.get(project);
  if (!plans?.size) return toolSurface('Tasks','<p class="body-copy">Choose a roadmap feature to build its task plan.</p>'+action('Open roadmap','data-route="roadmap"'));
  const id = screen.startsWith('tasks-') ? screen.slice(6) : currentPlan.get(project);
  currentPlan.set(project,id);
  const features = productLanes().flatMap(l=>l.features).filter(f=>plans.has(f.id));
  const f = features.find(f=>f.id===id);
  const rows = taskRows(f);
  const ready = rows.filter(t=>t.state==='Ready for code review');
  const done = rows.filter(t=>t.state==='Done').length;
  const picker = features.length > 1 ? '<select id="plan-picker" aria-label="Feature task plan">'+features.map(option=>'<option value="'+option.id+'" '+(option.id===id?'selected':'')+'>'+option.title+'</option>').join('')+'</select>' : '';
  return '<section class="page tasks-page"><div class="crumb">Tasks '+icon('right')+' Feature build '+picker+'</div><header><h1>'+f.title+'</h1><div class="meta">'+done+' of '+rows.length+' tasks complete · <button class="spec-link" data-route="'+id+'">Open spec '+icon('right')+'</button></div></header>'+
    '<div class="task-progress" aria-hidden="true">'+rows.map(t=>'<i class="'+(t.state==='Done'?'done':t.state==='Queued'?'queued':'ready')+'"></i>').join('')+'</div>'+
    '<section class="block"><h2>Task breakdown</h2><div class="list">'+rows.map((t,i)=>'<div class="task-line"><span class="task-marker">'+icon(t.state==='Done'?'checked':t.state==='Queued'?'list':'diff')+'</span><div><b>'+t.title+'</b><small>'+t.owner+' · '+t.state+'</small></div><button class="task-discuss" data-task-index="'+i+'" aria-label="Discuss '+t.title+'">'+icon('chat')+'</button></div>').join('')+'</div></section>'+
    '<section class="block"><h2>Ready for code review</h2>'+(ready.length ? '<div class="panel handoff"><div><b>'+ready[0].title+'</b><small>Codex · 2 files · 2 checks passed</small></div>'+action('Review changes','data-route="review"',true)+'</div>' : '<p class="body-copy">'+(done===rows.length?'All changes accepted.':'No changes ready for review yet.')+'</p>')+'</section></section>';
}
document.addEventListener('change',e=>{
  if (e.target.id==='plan-picker') go('tasks-'+e.target.value);
});
