// Sample product plan for the design review. Slugs also identify specs in chat.
const browserLanes = [
  {name:'Downloads', goal:'Follow a transfer from the first byte to the last.', icon:'download', features:[
    {id:'downloads-preview', title:'Downloads preview', state:'Shipped', goal:'See recent transfers without leaving the current tab.', checks:['Show the newest transfer first.', 'Open a completed file from its row.']},
    {id:'feature', title:'Dock download progress', state:'In review', goal:'Track active transfers from the macOS Dock.'},
    {id:'retry-downloads', title:'Retry interrupted downloads', state:'Suggested', goal:'Restart an interrupted transfer from its Downloads row.', why:'The Dock shows when a transfer stops, but the Downloads row offers no way to try again.', checks:['Offer Retry on failed transfers.', 'Reuse the original URL and destination.', 'Update the existing row when the retry starts.']}
  ]},
  {name:'Navigation', goal:'Keep everyday controls within reach.', icon:'layout', features:[
    {id:'header-controls', title:'Compact header controls', state:'Planned', goal:'Keep the project title and controls on one line.', checks:['Truncate a long title before hiding navigation.', 'Keep the active tool visible at narrow widths.']},
    {id:'recent-spaces', title:'Jump to the last Space', state:'Suggested', goal:'Return to the previous Space with one shortcut.', why:'Working across two Spaces currently requires reopening the switcher each time.', checks:['Offer the previous Space in the command field.', 'Restore the selected tab when switching back.']}
  ]},
  {name:'Library', goal:'Find a saved page and pick up where you left off.', icon:'bookmark', features:[
    {id:'saved-pages', title:'Saved pages', state:'Shipped', goal:'Collect bookmarked pages in the Library.', checks:['Show the page title and domain.', 'Open the saved URL when selected.']},
    {id:'library-search', title:'Search saved pages', state:'Suggested', goal:'Find a bookmark by its title or domain.', why:'A long collection is hard to scan when only part of a title is familiar.', checks:['Match partial titles and domains.', 'Restore the full list when the query is cleared.']}
  ]}
];
function productLanes() {
  if (project === 'yab') return browserLanes;
  const p = projects[project];
  return [{name:p.area, goal:p.goal, icon:'roadmap', features:[{id:'feature',title:p.feature,state:'Planned',goal:p.goal}]}];
}
function featureState(f) {
  return project === 'yab' && f.id === 'feature' && accepted ? 'Accepted' : f.state;
}
function roadmap() {
  const lanes = productLanes();
  const features = lanes.flatMap(l => l.features);
  const suggestions = features.filter(f => f.state === 'Suggested').length;
  return '<section class="page product-map"><header><h1>Roadmap</h1><p class="meta">'+lanes.length+' '+(lanes.length === 1 ? 'lane' : 'lanes')+' · '+features.length+' '+(features.length === 1 ? 'feature' : 'features')+' · '+suggestions+' suggested</p></header>'+
    lanes.map(l => '<section class="product-lane"><h2>'+icon(l.icon)+l.name+'</h2><p>'+l.goal+'</p><div class="milestones">'+l.features.map(f =>
      '<button data-route="'+f.id+'" class="milestone '+(f.state === 'Suggested' ? 'suggestion' : '')+'"><small>'+featureState(f)+'</small><b>'+f.title+'</b><span>'+f.goal+'</span></button>').join('')+'</div></section>').join('')+'</section>';
}
function selectedFeature() {
  return productLanes().flatMap(l => l.features).find(f => f.id === screen);
}
function roadmapCrumb(name) {
  return '<div class="crumb"><button data-route="roadmap">Roadmap</button>'+icon('right')+name+'</div>';
}
function productSpec(f) {
  const lane = productLanes().find(l => l.features.includes(f));
  return '<article class="page doc">'+roadmapCrumb(lane.name)+'<header><h1>'+f.title+'</h1><p class="meta">'+featureState(f)+'</p></header><section class="block"><h2>Feature definition</h2><p class="body-copy">'+f.goal+'</p></section>'+
    (f.why ? '<section class="block"><h2>Why suggest this?</h2><p class="body-copy">'+f.why+'</p></section>' : '')+
    '<section class="block"><h2>Acceptance criteria</h2>'+f.checks.map(c=>'<div class="check-row">'+icon('list')+c+'</div>').join('')+'</section><div class="block">'+action(icon('chat')+' Discuss feature','data-action="discuss"',true)+'</div></article>';
}
