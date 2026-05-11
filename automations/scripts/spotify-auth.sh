#!/bin/zsh
# Spotify OAuth setup — runs the one-time auth flow and saves the
# refresh_token to ~/.brain-secrets. After this, sync-spotify.sh can pull
# your recently-played tracks forever without re-auth.
#
# Prereq: register an app at https://developer.spotify.com/dashboard
# - Redirect URI: http://127.0.0.1:7892/callback
# - Note the client_id and client_secret
#
# Usage:
#   spotify-auth.sh             # interactive — opens browser, runs callback server
#   spotify-auth.sh --check     # just verify existing tokens work

set -euo pipefail

VAULT="/Users/carlos/Brain/OBSIDIAN"
SECRETS="$HOME/.brain-secrets"
PORT=7892
REDIRECT_URI="http://127.0.0.1:$PORT/callback"
SCOPES="user-read-recently-played user-top-read user-read-playback-state user-library-read"

[[ -f "$SECRETS" ]] && { set -a; source "$SECRETS"; set +a; }

CHECK_ONLY=""
[[ "${1:-}" == "--check" ]] && CHECK_ONLY="yes"

# === CHECK mode ===
if [[ -n "$CHECK_ONLY" ]]; then
  if [[ -z "${SPOTIFY_REFRESH_TOKEN:-}" ]]; then
    echo "Not authed. Run without --check to start."
    exit 1
  fi
  # Try refreshing
  resp=$(curl -sS -X POST https://accounts.spotify.com/api/token \
    -u "$SPOTIFY_CLIENT_ID:$SPOTIFY_CLIENT_SECRET" \
    -d "grant_type=refresh_token" \
    -d "refresh_token=$SPOTIFY_REFRESH_TOKEN")
  if echo "$resp" | jq -e '.access_token' >/dev/null 2>&1; then
    echo "✓ Refresh token works."
    exit 0
  else
    echo "✗ Refresh failed:"
    echo "$resp" | jq
    exit 1
  fi
fi

# === Interactive auth ===

# Ensure we have credentials
if [[ -z "${SPOTIFY_CLIENT_ID:-}" || -z "${SPOTIFY_CLIENT_SECRET:-}" ]]; then
  cat <<'EOM'

You need to register a Spotify app first (2 minutes, one-time):

  1. Open https://developer.spotify.com/dashboard
  2. Click "Create app"
  3. App name: anything (e.g. "Brain Vault")
  4. App description: "Personal Spotify history sync"
  5. Redirect URI: http://127.0.0.1:7892/callback
  6. Check "Web API" under API/SDKs
  7. Click Save
  8. On the app page, click "Settings" — copy Client ID and Client Secret

Then paste them into ~/.brain-secrets:

  SPOTIFY_CLIENT_ID="..."
  SPOTIFY_CLIENT_SECRET="..."

Re-run this script.

EOM
  exit 1
fi

# Generate state token for CSRF protection
STATE=$(openssl rand -hex 16)
AUTH_URL="https://accounts.spotify.com/authorize?response_type=code&client_id=$SPOTIFY_CLIENT_ID&scope=$(echo "$SCOPES" | sed 's/ /%20/g')&redirect_uri=$(echo "$REDIRECT_URI" | sed 's|:|%3A|g; s|/|%2F|g')&state=$STATE"

echo "→ Starting local callback server on port $PORT..."
echo "→ Opening Spotify auth in your browser..."
echo
echo "If browser doesn't open automatically, visit:"
echo "  $AUTH_URL"
echo

# Start callback server in background
CALLBACK_OUT=$(mktemp)
trap "rm -f $CALLBACK_OUT" EXIT

/usr/bin/python3 - "$PORT" "$STATE" "$CALLBACK_OUT" <<'PYEOF' &
import sys, http.server, urllib.parse, threading

PORT = int(sys.argv[1])
EXPECTED_STATE = sys.argv[2]
OUT_FILE = sys.argv[3]

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != '/callback':
            self.send_response(404); self.end_headers(); return
        qs = urllib.parse.parse_qs(parsed.query)
        code = qs.get('code', [''])[0]
        state = qs.get('state', [''])[0]
        error = qs.get('error', [''])[0]
        if error:
            body = f"<h1>Error</h1><p>{error}</p>"
            ok = False
        elif state != EXPECTED_STATE:
            body = "<h1>State mismatch</h1><p>Possible CSRF. Try again.</p>"
            ok = False
        elif not code:
            body = "<h1>No code returned</h1>"
            ok = False
        else:
            body = "<h1>Auth successful</h1><p>You can close this tab. Back to your terminal.</p>"
            ok = True
            with open(OUT_FILE, 'w') as f:
                f.write(code)
        self.send_response(200 if ok else 400)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(body.encode())
        threading.Thread(target=lambda: (__import__('time').sleep(0.5), self.server.shutdown())).start()

server = http.server.HTTPServer(('127.0.0.1', PORT), Handler)
server.serve_forever()
PYEOF

CB_PID=$!
sleep 1

# Open browser
open "$AUTH_URL"

# Wait for callback to write the code
echo "→ Waiting for you to authorize in the browser..."
for i in {1..120}; do
  if [[ -s "$CALLBACK_OUT" ]]; then break; fi
  sleep 1
done

# Kill server if still alive
kill $CB_PID 2>/dev/null || true
wait 2>/dev/null || true

CODE=$(cat "$CALLBACK_OUT" 2>/dev/null)
if [[ -z "$CODE" ]]; then
  echo "✗ Timed out waiting for callback. Re-run when ready."
  exit 1
fi

echo "→ Got auth code. Exchanging for tokens..."

TOKEN_RESP=$(curl -sS -X POST https://accounts.spotify.com/api/token \
  -u "$SPOTIFY_CLIENT_ID:$SPOTIFY_CLIENT_SECRET" \
  -d "grant_type=authorization_code" \
  -d "code=$CODE" \
  -d "redirect_uri=$REDIRECT_URI")

if ! echo "$TOKEN_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
  echo "✗ Token exchange failed:"
  echo "$TOKEN_RESP" | jq
  exit 1
fi

REFRESH=$(echo "$TOKEN_RESP" | jq -r '.refresh_token')
ACCESS=$(echo "$TOKEN_RESP" | jq -r '.access_token')

# Save refresh token to secrets
if grep -q "^SPOTIFY_REFRESH_TOKEN" "$SECRETS" 2>/dev/null; then
  /usr/bin/sed -i '' "s|^SPOTIFY_REFRESH_TOKEN=.*|SPOTIFY_REFRESH_TOKEN=\"$REFRESH\"|" "$SECRETS"
else
  echo "" >> "$SECRETS"
  echo "# Spotify (saved by spotify-auth.sh)" >> "$SECRETS"
  echo "SPOTIFY_REFRESH_TOKEN=\"$REFRESH\"" >> "$SECRETS"
fi
chmod 600 "$SECRETS"

echo
echo "✓ Auth complete. SPOTIFY_REFRESH_TOKEN written to ~/.brain-secrets"
echo "  You can now run: sync-spotify.sh"
echo "  Daily auto-sync is scheduled via launchd."

# Quick verification
echo
echo "→ Testing /me/player/recently-played..."
recent=$(curl -sS -H "Authorization: Bearer $ACCESS" \
  "https://api.spotify.com/v1/me/player/recently-played?limit=3")
if echo "$recent" | jq -e '.items' >/dev/null 2>&1; then
  echo "✓ API works. Your 3 most recently played:"
  echo "$recent" | jq -r '.items[] | "  • \(.track.name) — \(.track.artists[0].name)"'
else
  echo "API call returned:"
  echo "$recent" | jq | head -20
fi
