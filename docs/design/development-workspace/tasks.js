// Keep the original sample task plan for Yab Browser.
const buildPlans = new Map([['yab', new Set(['feature'])]]);
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
    const details = directory[project] ||= {};
    details.taskPlans = [...plans];
    if (nativeSpace) window.webkit.messageHandlers.toolbar.postMessage({project, taskPlan:id});
    recordActivity('Created task plan for '+f.title);
    const link = document.createElement('button');
    link.className = 'chat-link';
    link.dataset.route = 'tasks-'+id;
    link.textContent = 'Task plan · '+f.title;
    messages.append(link);
    messages.scrollTop = messages.scrollHeight;
    if (screen === 'roadmap') render();
  }
  go('tasks-'+id);
}
function taskRows(f) {
  if (project === 'yab' && f.id === 'feature') return dockTasks.map((t,i)=>({...t,state:i===2 && accepted ? 'Done' : t.state}));
  const checks = f.checks ?? [f.goal];
  return [...checks.map(title=>({title,owner:'Codex',state:'Queued'})),
    {title:'Verify the acceptance criteria',owner:'Test agent',state:'Queued'}];
}
function roadmapTasks() {
  const plans = buildPlans.get(project);
  const entries = productLanes().flatMap(lane => lane.features)
    .filter(feature => plans?.has(feature.id))
    .flatMap(feature => taskRows(feature).map((task, index) => ({...task, feature, index})));
  const rows = entries.map(task => {
    const key = task.feature.id+':'+task.index;
    const done = directory[project]?.taskCompletion?.[key] ?? (task.state === 'Done');
    return '<tr><td><input type="checkbox" data-completion="'+key+'" aria-label="'+escapeAttribute(task.title)+'" '+(done ? 'checked' : '')+'></td>'+
      '<td>'+escapeHTML(task.title)+'</td><td><button class="task-link" data-route="'+task.feature.id+'">'+escapeHTML(task.feature.title)+'</button></td>'+
      '<td>'+escapeHTML(task.owner)+'</td><td data-task-status data-incomplete="'+escapeAttribute(task.state === 'Done' ? 'To do' : task.state)+'">'+
      (done ? 'Done' : task.state === 'Done' ? 'To do' : escapeHTML(task.state))+'</td>'+
      '<td><button class="task-link" aria-label="Discuss '+escapeAttribute(task.title)+'" data-task-feature="'+task.feature.id+'" data-task-index="'+task.index+'">'+icon('chat')+'</button></td></tr>';
  }).join('');
  const count = entries.filter(task=>(directory[project]?.taskCompletion?.[task.feature.id+':'+task.index] ?? (task.state === 'Done'))).length;
  return '<section class="block" id="roadmap-tasks"><div class="section-heading"><h2>Tasks</h2><span id="task-progress" aria-live="polite">'+count+' of '+entries.length+' done</span></div>'+
    (entries.length ? '<div class="panel roadmap-task-table"><table aria-label="Project tasks"><thead><tr><th scope="col">Done</th><th scope="col">Task</th><th scope="col">Feature</th><th scope="col">Owner</th><th scope="col">Status</th><th scope="col"><span class="task-sr-only">Discuss</span></th></tr></thead><tbody>'+rows+'</tbody></table></div>' : '<p class="body-copy">No tasks yet.</p>')+
    (entries.some(task=>task.state==='Ready for code review') ? '<p class="task-review">'+action('Review changes','data-route="review"')+'</p>' : '')+'</section>';
}
function escapeAttribute(value) {
  return escapeHTML(value).replaceAll('"','&quot;');
}
document.addEventListener('change', event => {
  const input = event.target;
  const task = input.dataset.completion;
  if (!task) return;
  const details = directory[project] ||= {};
  (details.taskCompletion ||= {})[task] = input.checked;
  if (nativeSpace) window.webkit.messageHandlers.toolbar.postMessage({project, task, checked:input.checked});
  else localStorage.setItem('development-directory',JSON.stringify(directory));
  const state = input.closest('tr').querySelector('[data-task-status]');
  state.textContent = input.checked ? 'Done' : state.dataset.incomplete;
  const rows = document.querySelectorAll('#roadmap-tasks input[data-completion]');
  document.querySelector('#task-progress').textContent = [...rows].filter(row=>row.checked).length+' of '+rows.length+' done';
});
