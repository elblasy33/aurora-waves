# Publishing on the KDE Store

Plasma's **Get New Widgets** dialog downloads from [store.kde.org](https://store.kde.org).

**Store page:** <https://store.kde.org/p/2382242> (category *Plasma 6 Applets*, id 706).
New products show on the website at once. Plasma's *Get New Widgets* reads a separate API
that catches up a few hours later.

## Steps

1. Build the package with `./build.sh`. It writes `dist/aurora-radio-<version>.plasmoid`.
2. Create a GitHub release for the version (for example tag `v1.1.1`) and attach the
   `.plasmoid` file.
3. Sign in at <https://store.kde.org>, then go to **Add Product**:
   - **Category:** *Plasma 6 Extensions → Plasma 6 Applets* (Widgets)
   - **Title:** `Aurora Radio`
   - **Summary** and **Description:** copy them from below.
   - **License:** GPL-2.0-or-later
   - **Link:** this repository
   - **Files:** upload the `.plasmoid`
   - **Screenshots:** the images in `docs/screenshots/`. Upload `en-main.png` first.
4. For each new version: bump `Version` in `package/metadata.json`, add an entry to
   `CHANGELOG.md`, run `./build.sh`, then upload the new file to the same store product.

## Store text

**Summary**

> Live radio from around the world in a frosted-glass widget: discover stations, play your music, MPRIS.

**Description**

> A frosted-glass radio player for KDE Plasma 6.
>
> • Discover tens of thousands of stations in 220+ countries (Radio Browser) by name, country
>   and genre, with your country preselected. Arabic searches also find Latin spellings.
> • Add any stream URL, a Dailymotion or YouTube live page, local files, folders or M3U/PLS playlists.
> • One-click "fetch from source" for the station name, description and logo; custom logos.
> • Check & repair: actually listens to each station to confirm there is audio, finds moved files and
>   suggests tested replacement links.
> • MPRIS: shows in the media controller, audio visualizers, lock screen and media keys, with cover art.
> • Responsive layouts for any panel or desktop size; English and Arabic, with automatic text direction.
> • Curated library of Egypt's official public radio (Maspero).
>
> Requires: mpv, yt-dlp, ffmpeg, python3-gi (imagemagick optional).
>
> راديو أورورا: إذاعات العالم بث مباشر بواجهة زجاجية، مع ملفاتك ودعم متحكم الوسائط.
