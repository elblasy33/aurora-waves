# Publishing on the KDE Store

Plasma's **Get New Widgets** dialog downloads from [store.kde.org](https://store.kde.org).

**Store product:** <https://store.kde.org/p/2382242> (category *Plasma 6 Applets*, id 706), first
published as *Aurora Radio*. Version 2.0.0 keeps the same plugin id
(`com.github.elblasy33.auroraradio`), so **update this product and rename it** instead of creating
a new one: existing users then get 2.0.0 as an ordinary update and keep their stations. A second
product with the same plugin id would confuse *Get New Widgets*.

New products and edits show on the website at once; Plasma's *Get New Widgets* catches up a few
hours later.

## Steps for 2.0.0

1. `./build.sh` → `dist/aurora-waves-2.0.0.plasmoid`
2. Create the GitHub release `v2.0.0` in `elblasy33/aurora-waves` and attach the `.plasmoid`.
3. On the store product → **Edit**:
   - **Title:** `Aurora Waves`
   - **Summary** and **Description:** copy them from below.
   - **Link / homepage:** `https://github.com/elblasy33/aurora-waves`
   - **Logo:** `docs/store/icon-256.png`
   - **Files:** upload `aurora-waves-2.0.0.plasmoid` (version `2.0.0`); keep or archive the old file.
   - **Screenshots:** a YouTube Music screenshot first, then the images in `docs/screenshots/`.
4. Later versions: bump `Version` in `package/metadata.json`, add a `CHANGELOG.md` entry,
   run `./build.sh`, upload the new file to the same product.

## Store text

**Summary**

> World radio, YouTube Music and your own music in one frosted-glass player.

**Description**

> A frosted-glass music player for KDE Plasma 6 that brings three sources together.
>
> 📻 World radio
> • Tens of thousands of live stations in 220+ countries (Radio Browser and zeno.fm), by name,
>   country (A–Z or by size) and genre. Arabic searches also find Latin spellings.
> • Add any stream URL or Dailymotion / YouTube live page; one-click name and logo.
> • Check & repair listens to every station to confirm real audio and suggests tested replacements.
>
> 🎵 YouTube Music (optional)
> • Search songs, artists and albums; home feed in your language; artist, album and playlist pages.
> • Queue with play next, add to queue and similar-song radio; seek; save anything as a station.
> • Optional sign-in through the browser you already use: liked songs, playlists, history and
>   personal recommendations. Everything works without an account.
> • One-click setup into the widget's own folder (no root, no system changes); keeps itself updated.
>
> 📁 Your music
> • Local files, folders and M3U/PLS playlists with shuffle, pause and seek.
>
> Plus: MPRIS (media controller, visualizers, lock screen, media keys, cover art), responsive
> layouts for any panel or desktop size, English and Arabic with automatic text direction.
>
> Requires: mpv, ffmpeg, python3-gi; python3-pip for YouTube Music; yt-dlp for live video pages.
>
> Not affiliated with Google or YouTube. YouTube Music support uses the open-source ytmusicapi and
> yt-dlp projects, for personal listening.
>
> أمواج أورورا: إذاعات العالم ويوتيوب ميوزك وموسيقاك في مشغّل زجاجي واحد.
