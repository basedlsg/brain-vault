#!/usr/bin/osascript -l JavaScript
// Apple Notes delta-sync JXA — called by sync-apple-notes.sh.
// Reads all notes whose modificationDate > since (Unix ms). Writes:
//   - new notes as archive/apple-notes/<date>-<slug>.md
//   - modified notes (matched by frontmatter sqlite_pk) by overwriting their .md
// Returns JSON: {scanned, written_new, updated, skipped, max_mod_seen}

ObjC.import('Foundation');

function run(argv) {
  const dest = argv[0];
  const sinceMs = parseInt(argv[1]); // 0 means everything

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
  function escYaml(s) { return ((s || '') + '').replace(/"/g, '\\"').replace(/\n/g, ' '); }
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

  // Build an index of existing notes by their (id, name+date) so we can find
  // and overwrite the ones that match a Notes.app note we're processing.
  // Apple Notes IDs are CoreData URIs like x-coredata://...
  // We store these in frontmatter as 'apple_note_id'.
  var existingByName = {};
  try {
    var contents = fm.contentsOfDirectoryAtPathError(dest, $());
    if (contents && contents.js) {
      var arr = contents.js;
      for (var j = 0; j < arr.length; j++) {
        var name = arr[j].js;
        if (name.endsWith('.md')) {
          existingByName[name] = true;
        }
      }
    }
  } catch (e) {}

  var scanned = 0, writtenNew = 0, updated = 0, skipped = 0;
  var maxModMs = sinceMs;

  for (var i = 0; i < allNotes.length; i++) {
    try {
      var n = allNotes[i];
      var modDate = n.modificationDate();
      var modMs = modDate ? modDate.getTime() : 0;
      if (modMs <= sinceMs) {
        scanned++;
        continue;
      }
      scanned++;
      if (modMs > maxModMs) maxModMs = modMs;

      var name = n.name();
      var created = n.creationDate();
      var folder = '(none)';
      var acct = '(none)';
      try { folder = n.container().name(); } catch (e) {}
      try { acct = n.container().container().name(); } catch (e) { acct = folder; }
      var body = n.body();
      var bodyMd = htmlToMd(body);
      if (!bodyMd && (!name || name.length < 3)) {
        skipped++;
        continue;
      }

      var noteId = '';
      try { noteId = n.id(); } catch (e) {}

      var isoC = isoDate(created);
      var isoM = isoDate(modDate);
      var slug = slugify(name);
      var fname = isoC + '-' + slug + '.md';
      var path = dest + '/' + fname;

      // If we already have it (same filename), we'll overwrite — assume same note updated.
      // For collisions with truly different notes that happen to share date+slug, add suffix.
      var isOverwrite = fm.fileExistsAtPath(path);

      if (!isOverwrite) {
        var seq = 0;
        while (fm.fileExistsAtPath(path)) {
          seq++;
          fname = isoC + '-' + slug + '-' + seq + '.md';
          path = dest + '/' + fname;
          if (seq > 50) break;
        }
      }

      var md =
        '---\n' +
        'type: apple-note\n' +
        'source: apple-notes\n' +
        'original_date: ' + isoC + '\n' +
        'modification_date: ' + isoM + '\n' +
        'imported_at: ' + new Date().toISOString() + '\n' +
        'apple_note_id: "' + (noteId ? noteId.replace(/"/g, '\\"') : '') + '"\n' +
        'account: "' + escYaml(acct) + '"\n' +
        'folder: "' + escYaml(folder) + '"\n' +
        'title: "' + escYaml(name) + '"\n' +
        '---\n\n' +
        '# ' + (name || 'Untitled') + '\n\n' +
        bodyMd + '\n';

      var ns = $.NSString.alloc.initWithUTF8String(md);
      var data = ns.dataUsingEncoding($.NSUTF8StringEncoding);
      var ok = data.writeToFileAtomically(path, true);
      if (ok) {
        if (isOverwrite) updated++;
        else writtenNew++;
      } else {
        skipped++;
      }

      if ((writtenNew + updated) % 10 === 0 && (writtenNew + updated) > 0) {
        stderr('  [delta] scanned ' + scanned + ', new ' + writtenNew + ', updated ' + updated + '\n');
      }
    } catch (e) {
      skipped++;
    }
  }

  return JSON.stringify({scanned: scanned, writtenNew: writtenNew, updated: updated, skipped: skipped, maxModMs: maxModMs});
}
