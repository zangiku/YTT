#!/usr/bin/env bash
# Tests for ytt — offline by default: fzf, mpv and yt-dlp are stubbed, and `ytt add` / `ytt auth`
# run against a local fake YouTube API + OAuth server with a fake browser. No test reads browser
# cookies. Run: /bin/bash test.sh      (YTT_LIVE_TESTS=1 also runs real searches on YouTube)
set -u
cd "$(dirname "$0")"
Y="$PWD/ytt"
S=$(mktemp -d)
srv_pid=
trap '[ -z "$srv_pid" ] || kill "$srv_pid" 2>/dev/null; rm -rf "$S"' EXIT
export XDG_CONFIG_HOME="$S/config"

mk() { printf '#!/bin/sh\n%s\n' "$2" >"$1"; chmod +x "$1"; }
mkdir -p "$S/real" "$S/fake"
for d in real fake; do
  mk "$S/$d/mpv" 'printf "MPV %s\n" "$@"'
  # fzf stub: FZF_RC fails every call. --expect mode prints FZF_KEY then line FZF_LINE.
  # Otherwise: FZF_RC2 fails it, FZF_PICK picks that line, else the first 2 lines.
  mk "$S/$d/fzf" '[ -n "${FZF_RC:-}" ] && exit "$FZF_RC"
case " $* " in
  *" --expect="*) printf "%s\n" "${FZF_KEY:-}"; sed -n "${FZF_LINE:-1}p" ;;
  *) [ -n "${FZF_RC2:-}" ] && exit "$FZF_RC2"
     if [ -n "${FZF_PICK:-}" ]; then sed -n "${FZF_PICK}p"; else head -2; fi ;;
esac'
done
# yt-dlp stub: logs args, returns canned search results / playlists / playlist entries.
mk "$S/fake/yt-dlp" 'printf "%s\n" "$*" >>"'"$S"'/ytdlp.log"
case "$*" in
  *ytsearch*) printf "s1\t1:00\tChan\tOne\ns2\tNA\tChan\tTwo\ns3\t2:00\tChan\tThree\n" ;;
  *feed/playlists*) [ -n "${FEED_FAIL:-}" ] && exit 1; printf "PLroad\tRoad trip\nLL\tLiked videos\nPLfocus\tDeep focus\nWL\tWatch later\nRDabcdefghijk\tMix - Something\n" ;;
  *playlist?list=*) printf "vid1\t3:33\tChan\tSong one\nvid2\tNA\tChan\tLive thing\nvid3\t1:00\tChan\tSong three\n" ;;
esac'
# python3 stub (fake PATH only): stands in for the API helper. argv: -c CODE CFG CMD ARGS...
mk "$S/fake/python3" 'case "$4" in
  playlists) printf "PLmine\tMy list\nPLtwo\tOther\n" ;;
  add) shift 4; echo "ADD $*" ;;
esac'

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }
check() { # name expected-exit expected-substring -- cmd...
  local name=$1 want=$2 grep=$3; shift 4
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$grep" ] || printf '%s' "$out" | grep -qF -- "$grep"; }; then
    ok "$name"
  else
    bad "$name (exit $rc, want $want)"; printf '%s\n' "$out" | sed 's/^/     /'
  fi
}
fake() { env PATH="$S/fake:$PATH" "$@"; }

# --- basics
check "help"             0 "usage: ytt"          -- "$Y" -h
check "no args"          2 "usage: ytt"          -- "$Y"
check "bad flag"         2 "usage: ytt"          -- "$Y" -z x
check "-n 0"             2 "positive integer"    -- fake "$Y" -n 0 x
check "-n abc"           2 "positive integer"    -- fake "$Y" -n abc x
check "url: audio"       0 "MPV --no-video"      -- fake "$Y" https://youtu.be/dQw4w9WgXcQ
check "url: video+ipc"   0 "MPV --input-ipc-server=/tmp/x" -- fake env YT_IPC=/tmp/x "$Y" -v https://youtu.be/x
out=$(fake "$Y" https://youtu.be/x --ytdl-raw-options-append=exec=touch 2>&1)
if printf '%s\n' "$out" | grep -qxF 'MPV --' \
   && [ "$(printf '%s\n' "$out" | tail -1)" = "MPV --ytdl-raw-options-append=exec=touch" ] \
   && [ "$(printf '%s\n' "$out" | grep -nxF 'MPV --' | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -nF 'youtu.be/x' | cut -d: -f1)" ]; then
  ok "url: words after the URL are files, not mpv options"
else
  bad "url: '--' missing before URLs"; printf '%s\n' "$out" | sed 's/^/     /'
fi
check "cap: default 200" 0 "MPV --ytdl-raw-options-append=playlist-end=200" -- fake "$Y" https://youtu.be/x
check "cap: YTT_MAX"     0 "playlist-end=5"      -- fake env YTT_MAX=5 "$Y" https://youtu.be/x
check "cap: bad YTT_MAX" 2 "positive integer"    -- fake env YTT_MAX=abc "$Y" https://youtu.be/x
check "fzf esc"          0 ""                    -- fake env YTT_BROWSER=x FZF_RC=130 "$Y" -p
check "fzf no match"     0 ""                    -- fake env YTT_BROWSER=x FZF_RC=1 "$Y" -p
check "fzf broken"       2 "use ssh -t"          -- fake env YTT_BROWSER=x FZF_RC=2 "$Y" -p

# --- search (stubbed yt-dlp)
check "search: 2 picks"  0 "MPV https://www.youtube.com/watch?v=s2" -- fake "$Y" -n 5 lofi hip hop
grep -qF 'ytsearch5:lofi hip hop' "$S/ytdlp.log" && ok "search: query + count passed" || bad "search: query not passed"
check "search: -- term"  0 "watch?v=s1"          -- fake "$Y" -n 3 -- -rick astley
grep -qF 'ytsearch3:-rick astley' "$S/ytdlp.log" && ok "search: -- keeps '-term'" || bad "search: -- term lost"
n=$(fake "$Y" -n 5 lofi 2>&1 | grep -c 'watch?v=')
[ "$n" = 2 ] && ok "multi-select queues 2" || bad "multi-select queued $n"

# --- login
check "login: unset"     1 "no login set"        -- "$Y" login
check "-p: no login"     1 "needs your login"    -- fake "$Y" -p
check "login: set"       0 "Profile 2"           -- "$Y" login 'chrome:Profile 2'
check "login: show"      0 "chrome:Profile 2"    -- "$Y" login
check "login: unquoted"  0 "'chrome:Profile 2'"  -- "$Y" login chrome:Profile 2
[ "$(stat -f %Lp "$XDG_CONFIG_HOME/ytt")" = 700 ] && [ "$(stat -f %Lp "$XDG_CONFIG_HOME/ytt/browser")" = 600 ] \
  && ok "login: dir 700, file 600" || bad "login: modes $(stat -f %Lp "$XDG_CONFIG_HOME/ytt") / $(stat -f %Lp "$XDG_CONFIG_HOME/ytt/browser")"
check "login: comma refused"   2 "may only use"      -- "$Y" login 'chrome:a,exec=touch'
check "login: quote refused"   2 "may only use"      -- "$Y" login 'chrome:"x"'
check "login: old value kept"  0 "chrome:Profile 2"  -- "$Y" login
chmod 755 "$XDG_CONFIG_HOME/ytt"; rm -f "$XDG_CONFIG_HOME/ytt/browser"
echo orig >"$S/victim2"; ln -s "$S/victim2" "$XDG_CONFIG_HOME/ytt/browser"
check "login: over a planted symlink" 0 "Profile 2" -- "$Y" login 'chrome:Profile 2'
if [ "$(cat "$S/victim2")" = orig ] && [ ! -L "$XDG_CONFIG_HOME/ytt/browser" ] \
   && [ "$(stat -f %Lp "$XDG_CONFIG_HOME/ytt")" = 700 ] && [ "$(stat -f %Lp "$XDG_CONFIG_HOME/ytt/browser")" = 600 ]; then
  ok "login: symlink replaced, target untouched, 700/600"
else
  bad "login: wrote through symlink or wrong modes"
fi

# --- playlists (stubbed yt-dlp)
check "-p: WL on top, enter plays list" 0 "MPV https://www.youtube.com/playlist?list=WL" -- fake env FZF_LINE=1 "$Y" -p
check "-p: Liked second" 0 "playlist?list=LL"    -- fake env FZF_LINE=2 "$Y" -p
check "-p: own playlist" 0 "playlist?list=PLroad" -- fake env FZF_LINE=3 "$Y" -p
check "-p: mpv gets cookies" 0 "MPV --ytdl-raw-options-append=cookies-from-browser=chrome:Profile 2" -- fake env FZF_LINE=3 "$Y" -p
check "-p: mpv gets cap" 0 "MPV --ytdl-raw-options-append=playlist-end=200" -- fake env FZF_LINE=3 "$Y" -p
check "-p: mix opens from seed video" 0 "watch?v=abcdefghijk&list=RDabcdefghijk" -- fake env FZF_LINE=5 "$Y" -p
check "-p: → drills in"  0 "MPV https://www.youtube.com/watch?v=vid1" -- fake env FZF_KEY=right FZF_LINE=4 "$Y" -p
grep -q -- '--playlist-end 200' "$S/ytdlp.log" && ok "-p: → fetch is capped" || bad "→ fetch not capped"
out=$(fake env FZF_KEY=right FZF_LINE=4 "$Y" -p 2>&1)
if printf '%s' "$out" | grep -q 'watch?v=vid2' && ! printf '%s' "$out" | grep -q 'playlist?list='; then
  ok "-p: → plays picked videos, not the list"
else
  bad "-p: → output:"; printf '%s\n' "$out" | sed 's/^/     /'
fi
check "-p: → then Esc"   0 ""                    -- fake env FZF_KEY=right FZF_LINE=4 FZF_RC2=130 "$Y" -p
fake env FZF_KEY=right FZF_LINE=4 FZF_RC2=130 "$Y" -p 2>&1 | grep -q MPV && bad "→ then Esc started mpv" || ok "→ then Esc starts no mpv"
check "-p: YTT_BROWSER wins" 0 "cookies-from-browser=safari" -- fake env YTT_BROWSER=safari FZF_LINE=1 "$Y" -p
grep -q -- '--cookies-from-browser safari' "$S/ytdlp.log" && ok "-p: yt-dlp gets cookies" || bad "yt-dlp not given cookies"
check "-p: feed fails"   1 "couldn't read your playlists" -- fake env FEED_FAIL=1 "$Y" -p
check "-p: comma in YTT_BROWSER refused" 2 "may only use" -- fake env YTT_BROWSER='chrome:a,exec=touch' "$Y" -p
fake env FZF_LINE=1 "$Y" -v -p 2>&1 | grep -q -- --no-video && bad "-v -p still passes --no-video" || ok "-v -p drops --no-video"

# --- add: URL parsing and wiring (stubbed API helper)
U1="https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLx&t=42s"
U2="https://youtu.be/9bZkp7q19f0?si=abc"
U3="https://www.youtube.com/shorts/aqz-KE-bpKQ"
U4="https://music.youtube.com/watch?feature=share&v=kJQP7kiw5Fk"
check "add: URL forms, dedup"  0 "ADD PLmine dQw4w9WgXcQ 9bZkp7q19f0 aqz-KE-bpKQ kJQP7kiw5Fk" -- fake env FZF_PICK=2 "$Y" add "$U1" "$U2" "$U3" "$U4" "$U1"
check "add: bare id + embed"   0 "ADD PLmine dQw4w9WgXcQ M7lc1UVf-VE" -- fake env FZF_PICK=2 "$Y" add dQw4w9WgXcQ https://www.youtube.com/embed/M7lc1UVf-VE
check "add: m. and nocookie"   0 "ADD PLmine dQw4w9WgXcQ M7lc1UVf-VE" -- fake env FZF_PICK=2 "$Y" add "https://m.youtube.com/watch?v=dQw4w9WgXcQ" "https://www.youtube-nocookie.com/embed/M7lc1UVf-VE"
check "add: look-alikes rejected" 1 "no video URLs" -- fake env FZF_PICK=2 "$Y" add "https://evil.example/?v=dQw4w9WgXcQ" "https://evil.example/youtu.be/dQw4w9WgXcQ" "https://www.youtube.com/watch?v=dQw4w9WgXcQextra" "https://notyoutube.com/watch?v=dQw4w9WgXcQ"
check "add: Liked is first"    0 "ADD LL dQw4w9WgXcQ" -- fake env FZF_PICK=1 "$Y" add "$U1"
check "add: skips non-video"   0 "skipping 'https://example.com/x'" -- fake env FZF_PICK=2 "$Y" add https://example.com/x "$U2"
check "add: playlist-only URL" 1 "no video URLs" -- fake env FZF_PICK=2 "$Y" add "https://www.youtube.com/playlist?list=PLabc"
check "add: pasted on stdin"   0 "ADD PLtwo 9bZkp7q19f0 aqz-KE-bpKQ" -- fake env FZF_PICK=3 /bin/bash -c 'printf "%s %s\n\nignored\n" "$1" "$2" | "$0" add' "$Y" "$U2" "$U3"
check "add: esc in picker"     0 "" -- fake env FZF_RC=130 "$Y" add "$U1"

# --- the real API helper against a local fake YouTube API + OAuth server
cat >"$S/server.py" <<'PY'
import http.server, json, os, sys, urllib.parse
log, reject = open(sys.argv[1], "a"), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def reply(self, code, obj=None):
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers()
        if obj is not None: self.wfile.write(json.dumps(obj).encode())
    def parts(self):
        u = urllib.parse.urlparse(self.path); return u.path, dict(urllib.parse.parse_qsl(u.query))
    def authed(self):
        if self.headers.get("Authorization") == "Bearer tok" and not os.path.exists(reject): return True
        self.reply(401, {"error": {"message": "bad token", "errors": [{"reason": "authError"}]}}); return False
    def do_GET(self):
        path, q = self.parts()
        if path == "/steal": log.write("GET /steal\n"); log.flush()
        if not self.authed(): return
        if path.endswith("/playlists"):
            if "pageToken" in q: self.reply(200, {"items": [{"id": "PL2", "snippet": {"title": "Two\tTabbed\nTitle"}}]})
            else: self.reply(200, {"items": [{"id": "PL1", "snippet": {"title": "One"}}], "nextPageToken": "p2"})
        elif path.endswith("/playlistItems"):
            self.reply(200, {"items": [{"id": "x"}] if q.get("videoId") == "dupdupdupdu" else []})
    def do_POST(self):
        path, q = self.parts()
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        log.write(f"POST {path} {json.dumps(q, sort_keys=True)} {body}\n"); log.flush()
        if path.endswith("/token"):
            f = dict(urllib.parse.parse_qsl(body))
            if f.get("grant_type") == "authorization_code":
                if f.get("code") != "goodcode": return self.reply(400, {"error": "invalid_grant"})
                return self.reply(200, {"access_token": "tok", "refresh_token": "newrefresh", "expires_in": 3600})
            return self.reply(200, {"access_token": "tok", "expires_in": 3600})
        if not self.authed(): return
        if path.endswith("/videos/rate"): self.reply(204)
        elif path.endswith("/playlistItems"):
            vid = json.loads(body)["snippet"]["resourceId"]["videoId"]
            if vid == "redirectred":  # a redirect must never be followed with the bearer token
                self.send_response(307)
                self.send_header("Location", f"http://127.0.0.1:{self.server.server_port}/steal")
                self.end_headers()
            elif vid == "quotaquotaq": self.reply(403, {"error": {"message": "quota", "errors": [{"reason": "quotaExceeded"}]}})
            else: self.reply(200, {"snippet": {"title": "Title of " + vid}})
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_port, flush=True)
srv.serve_forever()
PY
# Fake browser: records the auth URL's params, then hits the loopback callback like Google would —
# after three requests that must be refused (wrong state, wrong path, neither code nor error).
cat >"$S/browser.py" <<'PY'
import json, sys, urllib.error, urllib.parse, urllib.request
q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(sys.argv[1]).query))
json.dump(dict(q, _netloc=urllib.parse.urlparse(sys.argv[1]).netloc), open(sys.argv[2], "w"))
redir, st = q["redirect_uri"], q["state"]
def get(url):
    try:
        with urllib.request.urlopen(url, timeout=10) as r: return r.status
    except urllib.error.HTTPError as e: return e.code
enc = urllib.parse.urlencode
codes = [get(redir + "?" + enc({"code": "evil", "state": "wrong"})),
         get(redir.replace("/callback", "/other") + "?" + enc({"code": "evil", "state": st})),
         get(redir + "?" + enc({"state": st})),
         get(redir + "?" + enc({"code": "goodcode", "state": st}))]
print(" ".join(map(str, codes)), flush=True)
PY
mk "$S/browser" "( python3 '$S/browser.py' \"\$1\" '$S/authparams.json' >'$S/browser.log' 2>&1 & )"

python3 "$S/server.py" "$S/api.log" "$S/reject_all" >"$S/port" &
srv_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do [ -s "$S/port" ] && break; sleep 0.2; done
base="http://127.0.0.1:$(cat "$S/port")"
C="$XDG_CONFIG_HOME/ytt"
# The client file's endpoints point elsewhere on purpose: ytt must ignore them.
printf '{"installed":{"client_id":"cid","client_secret":"cs","auth_uri":"https://evil.example/auth","token_uri":"https://evil.example/token"}}' >"$S/client_secret.json"
tok() { printf '{"access_token":"%s","refresh_token":"r","expires_at":%s}' "$1" "$2" >"$C/token.json"; }
live() { env PATH="$S/real:$PATH" YTT_TEST_BASE="$base" "$@"; }   # real python3 helper

check "api: bad client file"   1 "Desktop-app" -- live /bin/bash -c 'echo "{\"web\":{}}" >"$1/x.json"; "$0" auth "$1/x.json"' "$Y" "$S"
check "auth: full loopback flow" 0 "approved" -- live env BROWSER="$S/browser" "$Y" auth "$S/client_secret.json"
sleep 0.3
[ "$(cat "$S/browser.log")" = "400 400 400 200" ] && ok "auth: only the real callback is accepted" || bad "auth: browser saw '$(cat "$S/browser.log")'"
grep -q '"refresh_token": "newrefresh"' "$C/token.json" && ok "auth: token saved" || bad "auth: token not saved"
if python3 - "$S/authparams.json" "$S/api.log" <<'PY'
import base64, hashlib, json, sys, urllib.parse
q = json.load(open(sys.argv[1]))
body = [l for l in open(sys.argv[2]) if "authorization_code" in l][-1].rstrip("\n").split(" ", 3)[3]
f = dict(urllib.parse.parse_qsl(body))
ch = base64.urlsafe_b64encode(hashlib.sha256(f["code_verifier"].encode()).digest()).rstrip(b"=").decode()
ok = (ch == q["code_challenge"] and q["code_challenge_method"] == "S256" and q["scope"].endswith("/youtube")
      and f["redirect_uri"] == q["redirect_uri"] and q["redirect_uri"].endswith("/callback")
      and q["_netloc"].startswith("127.0.0.1:"))  # auth page came from our endpoint, not the client file's
sys.exit(0 if ok else 1)
PY
then ok "auth: PKCE verifier matches challenge; redirect consistent"; else bad "auth: PKCE / redirect mismatch"; fi
[ "$(stat -f %Lp "$C/client.json")" = 600 ] && ok "auth: client file is 600" || bad "auth: client file mode $(stat -f %Lp "$C/client.json")"

rm -f "$C/token.json"
check "api: not approved"      1 "not approved yet" -- live "$Y" add dQw4w9WgXcQ
tok tok 9999999999
check "api: paginated list, add" 0 "added  dQw4w9WgXcQ  Title of dQw4w9WgXcQ" -- live env FZF_PICK=3 "$Y" add dQw4w9WgXcQ
grep -q '"playlistId": "PL2"' "$S/api.log" && ok "api: page-2 playlist (tabbed title) picked" || bad "api: PL2 not targeted"
check "api: already there"     0 "already there  dupdupdupdu" -- live env FZF_PICK=2 "$Y" add dupdupdupdu
check "api: Liked = like"      0 "liked  dQw4w9WgXcQ" -- live env FZF_PICK=1 "$Y" add dQw4w9WgXcQ
grep -q 'POST /videos/rate {"id": "dQw4w9WgXcQ", "rating": "like"}' "$S/api.log" && ok "api: rate=like sent" || bad "api: no rate call"
tok old 0
check "api: refreshes expired token" 0 "added  9bZkp7q19f0" -- live env FZF_PICK=2 "$Y" add 9bZkp7q19f0
grep -q '"access_token": "tok"' "$C/token.json" && ok "api: refreshed token saved" || bad "api: token not saved"
[ "$(stat -f %Lp "$C/token.json")" = 600 ] && ok "api: token file is 600 (was 644)" || bad "api: token file mode $(stat -f %Lp "$C/token.json")"
chmod 755 "$C"
tok old 0
live env FZF_PICK=2 "$Y" add 9bZkp7q19f0 >/dev/null 2>&1
[ "$(stat -f %Lp "$C")" = 700 ] && ok "api: config dir re-tightened to 700" || bad "api: config dir mode $(stat -f %Lp "$C")"
ls -A "$C" | grep -q '^\.tmp-' && bad "api: temp file left behind" || ok "api: no temp files left"
tok stale 9999999999
check "api: 401 → refresh once → retry" 0 "added  dQw4w9WgXcQ" -- live env FZF_PICK=2 "$Y" add dQw4w9WgXcQ
touch "$S/reject_all"
check "api: 401 after refresh stops" 1 "rejected the approval" -- live env FZF_PICK=2 "$Y" add dQw4w9WgXcQ
rm -f "$S/reject_all"
printf '{}' >"$C/token.json"
check "api: token without refresh" 1 "no refresh token" -- live "$Y" add dQw4w9WgXcQ
printf 'garbage' >"$C/token.json"
check "api: corrupt token"     1 "unreadable" -- live "$Y" add dQw4w9WgXcQ
printf '{"refresh_token":"r","access_token":"a","expires_at":null}' >"$C/token.json"
check "api: null expires_at"   1 "malformed" -- live "$Y" add dQw4w9WgXcQ
tok tok 9999999999; chmod 000 "$C/token.json"
check "api: unreadable token"  1 "Permission denied" -- live "$Y" add dQw4w9WgXcQ
chmod 600 "$C/token.json"; tok old 0; chmod 000 "$C/client.json"
check "api: unreadable client" 1 "can't read" -- live env FZF_PICK=2 "$Y" add dQw4w9WgXcQ
chmod 600 "$C/client.json"
rm -f "$C/token.json"; tok old 0; mv "$C/token.json" "$S/victim"; ln -s "$S/victim" "$C/token.json"
before=$(cat "$S/victim")
check "api: refresh via symlinked token" 0 "added  9bZkp7q19f0" -- live env FZF_PICK=2 "$Y" add 9bZkp7q19f0
[ ! -L "$C/token.json" ] && [ "$(cat "$S/victim")" = "$before" ] && ok "api: symlink replaced, its target untouched" || bad "api: wrote through symlink"
tok tok 9999999999
check "api: quota"             1 "quota used up" -- live env FZF_PICK=2 "$Y" add quotaquotaq
check "api: redirect not followed" 1 "HTTP 307" -- live env FZF_PICK=2 "$Y" add redirectred
grep -q '/steal' "$S/api.log" && bad "api: followed a redirect with the token" || ok "api: token never sent to a redirect target"
check "api: test base must be loopback" 1 "must be http://127.0.0.1" -- env PATH="$S/real:$PATH" YTT_TEST_BASE=https://evil.example "$Y" add dQw4w9WgXcQ
grep -q 'evil.example' "$S/api.log" "$S/authparams.json" && bad "api: client-file endpoint used" || ok "api: client-file endpoints ignored"

# --- opt-in: real searches against YouTube (needs yt-dlp + network)
if [ "${YTT_LIVE_TESTS:-}" = 1 ]; then
  real() { env PATH="$S/real:/opt/homebrew/bin:$PATH" "$@"; }
  check "live: search"   0 "MPV https://www.youtube.com/watch?v=" -- real "$Y" -n 5 lofi hip hop
  check "live: -- term"  0 "MPV https://www.youtube.com/watch?v=" -- real "$Y" -n 3 -- -rick astley
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
