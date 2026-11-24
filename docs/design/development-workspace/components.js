// These components render trusted prototype controls. Badge values and headings are plain text.
function tabHeader(symbol, title, badges = [], controls = '') {
  return '<header class="tab-heading">'+icon(symbol)+'<h1>'+escapeHTML(title)+'</h1>'+
    badges.map(b=>'<span class="ui-badge">'+escapeHTML(b)+'</span>').join('')+
    (controls ? '<div class="header-actions">'+controls+'</div>' : '')+'</header>';
}
function sectionBlock(title, body, tools = '') {
  return '<section class="block"><div class="section-heading"><h2>'+escapeHTML(title)+'</h2>'+tools+'</div>'+body+'</section>';
}
