# Privacy Policy for ytt

Last updated: 2026-09-12

ytt is a command-line program that runs entirely on your own computer. It is not a hosted
service. There is no ytt server, and the author receives no data from it.

## What ytt accesses

- **YouTube, through Google's API.** If you run `ytt auth`, you approve ytt to read and modify
  *your own* YouTube playlists. ytt uses this only to list your playlists and to add videos that
  you choose.
- **Your browser's YouTube cookies.** If you run `ytt -p`, ytt asks yt-dlp to read the YouTube
  cookies of the browser profile you name, so YouTube shows your own playlists. The cookies are
  read at that moment and sent only to YouTube.

## What ytt stores

- Your Google approval (an OAuth client file and a token) in `~/.config/ytt/`, readable only by
  your user account (mode 600).
- The name of the browser profile to read cookies from, in the same directory.

Nothing else is stored. ytt writes no cookie files, keeps no history of what you play, search
for, or add, and contains no analytics or telemetry.

## What ytt sends, and where

Requests go to Google and YouTube only — `accounts.google.com`, `oauth2.googleapis.com`,
`www.googleapis.com`, and YouTube itself. The endpoints are fixed in the source code, and ytt
does not follow redirects for requests that carry your credentials. Nothing is sent to the
author or to any third party.

## Removing your data

- Withdraw ytt's access at https://myaccount.google.com/permissions
- Delete the stored files: `rm -rf ~/.config/ytt`

Removing the program removes everything it kept; there is nothing held elsewhere to delete.

## Required disclosures

ytt's use of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

ytt uses YouTube API Services. By using ytt you also agree to the
[YouTube Terms of Service](https://www.youtube.com/t/terms) and the
[Google Privacy Policy](https://policies.google.com/privacy).

## Contact

Questions or problems: https://github.com/zangiku/YTT/issues
