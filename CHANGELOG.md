# Changelog

## 2.1.1 — 2026-11-20

- App icon in YouTube-red tones (red to magenta and violet), same note-and-waves design

## 2.1.0 — 2026-11-20

- **Your YouTube Music library**: liked songs (with count), history, *Shuffle my likes*, your
  playlists, saved albums and the artists you follow
- Fixed: a browser sign-in stopped working after a few minutes. Chrome rotates its Google session
  cookies and Google rejects old copies; the widget now renews the session from the browser every
  10 minutes and whenever YouTube answers as signed out
- When the session cannot be renewed, a clear notice with **Reconnect** replaces the silently empty
  library

## 2.0.1 — 2026-11-20

- New screenshots with YouTube Music (English and Arabic)
- Fixed: while a YouTube Music song played, the last radio station's tile still looked active
- Mixed Arabic and Latin song, artist and album names now line up with the interface direction

## 2.0.0 — 2026-11-20

**Aurora Radio is now Aurora Waves**: world radio, YouTube Music and your own music in one player.
Same plugin id, so it updates in place and keeps your stations and settings. New app icon and a
new home: <https://github.com/elblasy33/aurora-waves>.

- **YouTube Music** (optional, one-click setup into the widget's own folder): search songs,
  artists and albums; home feed in your language; artist, album and playlist pages; queue with
  play next, add to queue and similar-song radio; seekable progress bar; save an artist, album,
  playlist or song radio as a station; titles and covers in the media controller
- **Optional Google sign-in** through the browser you already use (or pasted request headers):
  liked songs, playlists, history, personal recommendations and *Like*
- The widget keeps its own `yt-dlp` fresh for YouTube playback
- **Discover**: zeno.fm joins Radio Browser as a second directory (many single-artist streams such as
  Warda live there); new country picker with search, **A–Z / Largest** sorting and *All countries*
  pinned on top; country names in the interface language; "Search all countries" when a country
  has no results
- **Check & repair** looks in both directories and matches stations by every spelling of the name
- Fixed: the volume slider ignored the mouse under Plasma's own style (it was 0 px tall)
- Fixed: clicking a song in an artist or album list always played the first song
- Every new text is translated to English

## 1.1.1 — 2026-11-19

- New Aurora app icon (widget, media controller and visualizers)
- The player now announces a desktop entry, so media controllers show its icon and name
- Empty or junk stream titles (" - ", "Unknown", a lone artist) no longer blank out the track
  name; the station name is shown instead

## 1.1.0 — 2026-11-19

**Egypt Radio is now Aurora Radio** and serves listeners everywhere.
New plugin id `com.github.elblasy33.auroraradio`, so remove the old widget and add Aurora Radio.

- **Discover**: search the Radio Browser directory (220+ countries) by name, country and
  genre, with your country preselected and Arabic/Latin name matching
- Welcome screen; default stations depend on the user's country
- Curated library: Egypt's official public radio (Maspero)
- Add a stream URL, a Dailymotion or YouTube page, a local file, a folder or an M3U/PLS playlist
- Fetch name, description and logo from the source; custom logos (letter, icon, image, link)
- **Check & repair**: listens to each stream to verify real audio, finds moved files and suggests
  replacement links tested for audio
- MPRIS support: media controller, visualizers, lock screen, media keys and cover art
- Responsive layouts: wide, normal, short, tiny and narrow
- English and Arabic interface with automatic text direction
- Settings for glass opacity, background, logo shape, layout, panel icon, language and more

## 1.0.0 — 2026-11-19

First version, published as *Egypt Radio* (`org.beso.egyptradio`): the Maspero stations, the glass
interface, Discover, Check & repair, MPRIS and the Arabic/English UI.
