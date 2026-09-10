# ytt — YouTube in the terminal, without a browser

One bash script: **yt-dlp** reads YouTube, **fzf** picks, **mpv** plays (audio-only by default).
Search anonymously, browse **your own playlists** by title, and **add videos** you find to them.

Why not ytfzf: it's unmaintained (last release Jan 2024), has no Homebrew formula, and scrapes
YouTube's HTML itself instead of delegating to yt-dlp — the part that breaks when YouTube changes.

## Install

```sh
brew install yt-dlp fzf mpv          # python3 (for `ytt add`) ships with macOS
git clone https://github.com/zangiku/YTT && ln -sf "$PWD/YTT/ytt" ~/.local/bin/ytt
```

## Use

```sh
ytt lofi hip hop            # search, Tab to multi-select, Enter to play (audio)
ytt -v some talk            # same, with video
ytt -n 10 quick search      # fewer results
ytt https://youtu.be/...    # play a URL, playlist, or channel directly
ytt -p                      # your playlists (Watch Later + Liked pinned on top)
                            #   enter: play the whole list · →: open it and pick videos
ytt add <url> [url...]      # add videos to one of your playlists
ytt add                     #   …or paste URLs, then an empty line
```

Every list is capped at 200 videos (`YTT_MAX=500 ytt -p` to change) — a 5,000-video Watch Later
otherwise takes minutes to load.

Remote control: `YT_IPC="$TMPDIR/mpvsock" ytt …`, then
`echo '{"command":["cycle","pause"]}' | socat - "$TMPDIR/mpvsock"`. Keep the socket in a
private directory — anything that can open it controls mpv, and mpv can run programs.

## Browsing your playlists (`-p`)

yt-dlp can't log in to YouTube with a password; it borrows your browser's login cookies, read
fresh each run. ytt never writes cookies to disk.

```sh
ytt login 'chrome:Profile 2'   # browser[:profile] signed in to your YouTube account
ytt login                      # show the current setting
```

- First run on macOS: allow yt-dlp to use **Chrome Safe Storage** — click **Always Allow**.
- Find a Chrome profile's folder name at `chrome://version` → *Profile Path*.
- `YTT_BROWSER=safari ytt -p` overrides once (Safari needs Full Disk Access for your terminal).
- Search stays anonymous; only `-p` sends your cookies.

## Adding videos (`ytt add`) — one-time setup, free

yt-dlp only reads. Adding uses the official YouTube Data API, which needs your own (free) API
client. No billing account is required; the free quota allows about 200 adds a day.

1. [console.cloud.google.com](https://console.cloud.google.com) → create a project (e.g. `ytt`).
2. **APIs & Services → Library** → *YouTube Data API v3* → **Enable**.
3. **Google Auth Platform** (OAuth consent screen) → *Get started*: app name `ytt`, your email,
   audience **External**.
4. **Audience → Publish app** (status *In production*). In *Testing*, Google expires your
   approval every 7 days. Unverified is fine for personal use: at approval you'll see "Google
   hasn't verified this app" → *Advanced* → *Go to ytt*. (Or stay in Testing, add yourself as a
   test user, and re-run `ytt auth` weekly.)
5. **Clients → Create client** → application type **Desktop app** → download the JSON.
6. Run `ytt auth ~/Downloads/client_secret_….json` and approve in the browser.
   ytt copies the client file and the approval token into `~/.config/ytt/` (mode 600);
   you can delete the download.

Limits that come from YouTube, not ytt:
- **Watch Later can't be added to** by any app (YouTube removed API access in 2016).
- **Liked videos**: picking it *likes* the videos, which is how they get there.
- Only playlists you own are offered as targets. Videos already in the list are skipped.

To revoke: [myaccount.google.com/permissions](https://myaccount.google.com/permissions), then
`rm ~/.config/ytt/token.json`.

## Keeping it working

The one recurring failure is a stale yt-dlp: `brew upgrade yt-dlp`.

## Over SSH (a headless machine)

Audio plays out of the **remote** machine's speakers. Use `ytt` without `-v`, inside
`ssh -t <host> 'tmux new -A -s ytt'` so playback survives the laptop closing.

- `-p` needs a browser logged in to YouTube **on that machine**.
- `ytt auth` can't finish over plain SSH: Google redirects your browser to `127.0.0.1` on the
  machine that *opened* the page. Approve on a machine with a browser, then copy the approval:
  `scp ~/.config/ytt/{client,token}.json <host>:.config/ytt/` and `chmod 600` them there.

## Tests

`/bin/bash test.sh` — offline: stubs fzf, mpv and yt-dlp (so tests never read your cookies) and
runs `ytt add` / `ytt auth` against a local fake YouTube API + OAuth server with a fake browser.
`YTT_LIVE_TESTS=1 /bin/bash test.sh` also runs real searches.
