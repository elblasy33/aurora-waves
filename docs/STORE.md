# Publishing on the KDE Store

Plasma's **Get New Widgets** dialog downloads from [store.kde.org](https://store.kde.org).

**Aurora Waves is published as a new store product.** The old *Aurora Radio* product
(<https://store.kde.org/p/2382242>) is not the place for it.

The plugin id stays `com.github.elblasy33.auroraradio`, so whoever installs Aurora Waves over an
old Aurora Radio keeps their stations and settings. Because both products would then install the
same widget, once Aurora Waves is live either **delete the old product** or edit its description
to "Moved to Aurora Waves" with a link to the new page, so nobody installs the two side by side.

New products and edits show on the website at once; Plasma's *Get New Widgets* catches up a few
hours later.

## Steps

1. `./build.sh` → `dist/aurora-waves-<version>.plasmoid` (also attached to every
   [GitHub release](https://github.com/elblasy33/aurora-waves/releases)).
2. Sign in at <https://store.kde.org> → **Add Product**:
   - **Category:** *Plasma 6 Extensions → Plasma 6 Applets* (Widgets)
   - **Title:** `Aurora Waves`
   - **Summary** and **Description:** copy them from below.
   - **License:** GPL-2.0-or-later
   - **Link / homepage:** `https://github.com/elblasy33/aurora-waves`
   - **Logo:** `docs/store/icon-512.png`
   - **Files:** the `.plasmoid`, with its version number
   - **Screenshots** (in this order, all in `docs/screenshots/`):
     `waves-player-en.png`, `waves-home-en.png`, `waves-artist-en.png`, `waves-search-en.png`,
     `waves-queue-en.png`, `en-disc.png`, `waves-player-ar.png`, `sizes.png`
3. Put the new store link in the README (badge) and in the repository homepage.
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
