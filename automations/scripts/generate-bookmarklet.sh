#!/bin/zsh
# Generate the web capture bookmarklet — one tap from your bookmarks bar
# saves the current page + any selection to your Brain webhook.
#
# Special-cases chatgpt.com / claude.ai: extracts the full conversation.
# Writes a setup HTML at $VAULT/automations/bookmarklet.html — open it
# in Safari/Brave and drag the link to your bookmarks bar.

set -euo pipefail

VAULT="/Users/carlos/Brain/OBSIDIAN"
[[ -f "$HOME/.brain-secrets" ]] && { set -a; source "$HOME/.brain-secrets"; set +a; }

TOKEN="${BRAIN_WEBHOOK_TOKEN:-}"
[[ -z "$TOKEN" ]] && { echo "ERROR: BRAIN_WEBHOOK_TOKEN not in ~/.brain-secrets" >&2; exit 1; }

WEBHOOK_URL="http://192.168.110.137:7891/capture"

read -r -d '' JS <<'BMJS' || true
(function(){
var WEBHOOK="__WEBHOOK_URL__";
var TOKEN="__TOKEN__";
var url=window.location.href;
var title=document.title||"(no title)";
var sel=(window.getSelection?window.getSelection().toString():"")||"";
var domain=window.location.hostname.replace(/^www\./,"");
var body="";
var source="bookmarklet";
if(domain==="chatgpt.com"||domain==="chat.openai.com"){
  source="bookmarklet-chatgpt";
  var msgs=document.querySelectorAll("[data-message-author-role]");
  var parts=[];
  msgs.forEach(function(m){
    var role=m.getAttribute("data-message-author-role");
    var content=(m.innerText||"").trim();
    if(content)parts.push("**"+role.toUpperCase()+":**\n\n"+content);
  });
  body=parts.join("\n\n---\n\n");
  if(!body)body=(document.body.innerText||"").slice(0,15000);
}else if(domain==="claude.ai"){
  source="bookmarklet-claude";
  var turns=document.querySelectorAll(".font-claude-message,.font-user-message");
  var ps=[];
  turns.forEach(function(t){var c=(t.innerText||"").trim();if(c)ps.push(c);});
  body=ps.join("\n\n---\n\n");
  if(!body)body=(document.body.innerText||"").slice(0,15000);
}else{
  if(sel.length>20){body=sel;}else{
    var article=document.querySelector("article")||document.querySelector("main")||document.body;
    body=(article.innerText||"").slice(0,8000);
  }
}
var payload={text:"# "+title+"\n\n**URL:** "+url+"\n\n"+body,source:source,tags:["web-capture",domain]};
fetch(WEBHOOK,{method:"POST",headers:{"Authorization":"Bearer "+TOKEN,"Content-Type":"application/json"},body:JSON.stringify(payload)})
.then(function(r){return r.json();})
.then(function(d){
  var note=document.createElement("div");
  note.style.cssText="position:fixed;top:20px;right:20px;background:#1a1a1a;color:#fff;padding:14px 20px;border-radius:6px;font:14px -apple-system;z-index:999999;box-shadow:0 4px 12px rgba(0,0,0,.3);";
  note.textContent=d.ok?("✓ Saved to Brain: "+d.filename):("✗ "+(d.error||"error"));
  document.body.appendChild(note);
  setTimeout(function(){note.remove();},3000);
})
.catch(function(e){alert("Brain capture failed: "+e.message+"\n\nIs the webhook server running? Are you on the home network?");});
})();
BMJS

JS=${JS/__WEBHOOK_URL__/$WEBHOOK_URL}
JS=${JS/__TOKEN__/$TOKEN}

ENCODED_JS=$(printf '%s' "$JS" | /usr/bin/python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.stdin.read(),safe=""))')
BOOKMARKLET="javascript:$ENCODED_JS"

SETUP_PAGE="$VAULT/automations/bookmarklet.html"
cat > "$SETUP_PAGE" <<HTML
<!DOCTYPE html>
<html><head>
<title>Brain capture bookmarklet</title>
<style>
body{font:16px/1.6 -apple-system,sans-serif;max-width:680px;margin:40px auto;padding:0 20px;color:#222;background:#fafafa;}
h1{margin-bottom:8px;}
.lead{color:#666;margin-bottom:32px;}
.bookmarklet{display:inline-block;padding:12px 22px;background:#000;color:#fff;text-decoration:none;border-radius:6px;font-weight:600;}
.bookmarklet:hover{background:#333;}
.box{background:#fff;border:1px solid #ddd;border-radius:6px;padding:20px;margin:24px 0;}
code{background:#f0f0f0;padding:2px 6px;border-radius:3px;font:13px Menlo,monospace;}
ol li{margin:8px 0;}
</style></head>
<body>
<h1>Brain capture bookmarklet</h1>
<p class="lead">One tap from any Safari or Brave page → saves URL + title + selection (or full conversation, if on ChatGPT or Claude) to your vault inbox.</p>

<div class="box">
  <strong>Drag this to your bookmarks bar:</strong>
  <p><a class="bookmarklet" href="$BOOKMARKLET">🧠 Capture to Brain</a></p>
</div>

<h2>How it works</h2>
<ol>
  <li>On any web page in Safari or Brave, click <strong>🧠 Capture to Brain</strong> in your bookmarks bar.</li>
  <li>If you have text selected, that's what gets saved. Otherwise it grabs the article content (up to 8KB).</li>
  <li>On <code>chatgpt.com</code> or <code>claude.ai</code>, it extracts the full visible conversation instead.</li>
  <li>A black confirmation chip appears top right when saved.</li>
</ol>

<h2>Where things land</h2>
<ul>
  <li>Webhook receives the POST → writes to <code>OBSIDIAN/inbox/YYYY-MM-DD-HHMMSS-slug.md</code>.</li>
  <li>The note has <code>source: bookmarklet</code> (or <code>bookmarklet-chatgpt</code> / <code>bookmarklet-claude</code>) so synthesis can recognize it.</li>
  <li>Tags include the domain (e.g. <code>x.com</code>, <code>youtube.com</code>) for later grouping.</li>
</ul>

<h2>If it fails</h2>
<p>Most likely cause: you're not on the home Wi-Fi (192.168.110.x). The webhook only listens on the LAN. To capture from anywhere, set up Tailscale and edit this HTML to point at your tailnet hostname.</p>
</body></html>
HTML

echo "Bookmarklet HTML written to: $SETUP_PAGE"
echo
echo "Open it now:"
echo "  open '$SETUP_PAGE'"
echo
echo "Then drag the dark button to your bookmarks bar."
echo
echo "Bookmarklet size: $(echo -n "$BOOKMARKLET" | wc -c | xargs) chars"
