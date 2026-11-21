// These components render trusted prototype controls. Badge values and headings are plain text.
function tabHeader(symbol, title, badges = [], controls = '') {
  return '<header class="tab-heading">'+icon(symbol)+'<h1>'+escapeHTML(title)+'</h1>'+
    badges.map(b=>'<span class="ui-badge">'+escapeHTML(b)+'</span>').join('')+
    (controls ? '<div class="header-actions">'+controls+'</div>' : '')+'</header>';
}
function sectionBlock(title, body, tools = '') {
  return '<section class="block"><div class="section-heading"><h2>'+escapeHTML(title)+'</h2>'+tools+'</div>'+body+'</section>';
}
function progressChart(rows) {
  return '<div class="task-progress" role="img" aria-label="'+rows.filter(t=>t.state==='Done').length+' of '+rows.length+' tasks complete">'+rows.map(t=>'<i class="'+(t.state==='Done'?'done':t.state==='Queued'?'queued':'ready')+'"></i>').join('')+'</div>';
}
const collectionViews = new Map();
function taskCollection(rows, featureId) {
  const key = project+'/'+featureId;
  if (!collectionViews.has(key)) collectionViews.set(key,{
    active:'list', views:{
      list:{layout:'List', sort:'Spec order'}, table:{layout:'Table', sort:'Spec order'}
    }
  });
  const collection = collectionViews.get(key);
  const view = collection.views[collection.active];
  const options = (values,value)=>values.map(v=>'<option '+(v===value?'selected':'')+'>'+v+'</option>').join('');
  const tools = '<details class="view-menu"><summary>View options</summary><div><label>Layout<select data-view-setting="layout">'+options(['List','Table'],view.layout)+'</select></label><label>Sort<select data-view-setting="sort">'+options(['Spec order','Owner'],view.sort)+'</select></label></div></details>';
  const items = rows.map((t,index)=>({...t,index}));
  if (view.sort==='Owner') items.sort((a,b)=>a.owner.localeCompare(b.owner));
  const chat = t=>'<button class="task-discuss" data-task-index="'+t.index+'" aria-label="Discuss '+t.title+'">'+icon('chat')+'</button>';
  let body;
  if (view.layout==='Table') {
    body='<div class="list collection-table"><table><thead><tr><th>Task</th><th>Agent</th><th>Status</th><th></th></tr></thead><tbody>'+items.map(t=>'<tr><td>'+t.title+'</td><td>'+t.owner+'</td><td>'+t.state+'</td><td>'+chat(t)+'</td></tr>').join('')+'</tbody></table></div>';
  } else {
    body='<div class="list">'+items.map(t=>'<div class="task-line"><span class="task-marker">'+icon(t.state==='Done'?'checked':t.state==='Queued'?'list':'diff')+'</span><div><b>'+t.title+'</b><small>'+t.owner+' · '+t.state+'</small></div>'+chat(t)+'</div>').join('')+'</div>';
  }
  return sectionBlock('Task breakdown',body,tools);
}
document.addEventListener('change',event=>{
  const setting = event.target.dataset.viewSetting;
  if (!setting) return;
  const c = collectionViews.get(project+'/'+currentPlan.get(project));
  if (setting==='layout') c.active=event.target.value.toLowerCase();
  else c.views[c.active].sort=event.target.value;
  render();
  const menu=document.querySelector('.view-menu');
  menu.open=true;
  menu.querySelector('[data-view-setting="'+setting+'"]').focus();
});
