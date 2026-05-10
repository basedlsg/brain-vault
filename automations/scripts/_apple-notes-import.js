#!/usr/bin/osascript -l JavaScript
// Apple Notes JXA importer — called by import-apple-notes-chunked.sh
// Usage: osascript -l JavaScript _apple-notes-import.js <dest> <startIdx> <endIdx>

ObjC.import('Foundation');

function run(argv) {
  const dest = argv[0];
  const startIdx = parseInt(argv[1]);
  const endIdx = parseInt(argv[2]);

  const Notes = Application('Notes');
  const allNotes = Notes.notes();
  const fm = $.NSFileManager.defaultManager;

  function pad(n) { return String(n).padStart(2, '0'); }
  function isoDate(d) {
    if (!d) return 'unknown';
    return pad(d.getFullYear()) + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate());
  }
  function slugify(s, n) {
    var slug = ((s || 'untitled') + '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
    return slug.slice(0, n || 50) || 'untitled';
  }
  function escYaml(s) {
    return ((s || '') + '').replace(/"/g, '\\"').replace(/\n/g, ' ');
  }
  function htmlToMd(html) {
    if (!html) return '';
    var t = html;
    var ents = {'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&#39;':"'",'&nbsp;':' '};
    for (var k in ents) t = t.split(k).join(ents[k]);
    t = t.replace(/<br\s*\/?>/gi, '\n');
    t = t.replace(/<\/?(p|div|h[1-6]|li|ul|ol)[^>]*>/gi, '\n');
    t = t.replace(/<h1[^>]*>(.*?)<\/h1>/gi, '\n# $1\n');
    t = t.replace(/<h2[^>]*>(.*?)<\/h2>/gi, '\n## $1\n');
    t = t.replace(/<h3[^>]*>(.*?)<\/h3>/gi, '\n### $1\n');
    t = t.replace(/<(b|strong)[^>]*>(.*?)<\/\1>/gi, '**$2**');
    t = t.replace(/<(i|em)[^>]*>(.*?)<\/\1>/gi, '*$2*');
    t = t.replace(/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/gi, '[$2]($1)');
    t = t.replace(/<[^>]+>/g, '');
    t = t.replace(/\n{3,}/g, '\n\n').trim();
    return t;
  }

  function stderr(msg) {
    var d = $.NSString.alloc.initWithUTF8String(msg).dataUsingEncoding($.NSUTF8StringEncoding);
    $.NSFileHandle.fileHandleWithStandardError.writeData(d);
  }

  var written = 0, errored = 0, skipped = 0;

  for (var i = startIdx; i < endIdx && i < allNotes.length; i++) {
    try {
      var n = allNotes[i];
      var name = n.name();
      var created = n.creationDate();
      var modified = n.modificationDate();
      var folder = '(none)';
      var acct = '(none)';
      try { folder = n.container().name(); } catch (e) {}
      try { acct = n.container().container().name(); } catch (e) { acct = folder; }
      var body = n.body();

      // Skip empty / very short
      var bodyMd = htmlToMd(body);
      if (!bodyMd && (!name || name.length < 3)) {
        skipped++;
        continue;
      }

      var isoC = isoDate(created);
      var isoM = isoDate(modified);
      var slug = slugify(name);
      var fname = isoC + '-' + slug + '.md';
      var path = dest + '/' + fname;
      var seq = 0;
      while (fm.fileExistsAtPath(path)) {
        seq++;
        fname = isoC + '-' + slug + '-' + seq + '.md';
        path = dest + '/' + fname;
        if (seq > 50) { errored++; break; }
      }
      if (seq > 50) continue;

      var md =
        '---\n' +
        'type: apple-note\n' +
        'source: apple-notes\n' +
        'original_date: ' + isoC + '\n' +
        'modification_date: ' + isoM + '\n' +
        'imported_at: ' + new Date().toISOString() + '\n' +
        'account: "' + escYaml(acct) + '"\n' +
        'folder: "' + escYaml(folder) + '"\n' +
        'title: "' + escYaml(name) + '"\n' +
        '---\n\n' +
        '# ' + (name || 'Untitled') + '\n\n' +
        bodyMd + '\n';

      var ns = $.NSString.alloc.initWithUTF8String(md);
      var data = ns.dataUsingEncoding($.NSUTF8StringEncoding);
      var ok = data.writeToFileAtomically(path, true);
      if (ok) written++;
      else errored++;

      var processed = i - startIdx + 1;
      if (processed % 25 === 0) {
        stderr('  [jxa] processed ' + processed + '/' + (endIdx - startIdx) + ' (idx ' + i + ', written ' + written + ')\n');
      }
    } catch (e) {
      errored++;
    }
  }

  return JSON.stringify({startIdx: startIdx, endIdx: endIdx, written: written, errored: errored, skipped: skipped});
}
