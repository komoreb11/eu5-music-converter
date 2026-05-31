# EU4 Soundtrack for EU5

Brings the music of Europa Universalis IV into EU5 — fully integrated into the game's dynamic music engine. War, peace, and cultural context all trigger the right tracks automatically, just like in the original games.

---

## What it does

**155 tracks** from EU4 and its music DLCs are woven into EU5's adaptive music system:

- **At war** → EU4 war tracks play alongside EU5 music
- **At peace** → EU4 ambient and atmospheric tracks
- **Cultural context** → regional EU4 music matches your nation's culture group:
  - European nations hear British, French, HRE, Scandinavian, Russian, Iberian tracks
  - Ottoman/Persian/Egyptian/Caucasian → Middle Eastern tracks
  - Chinese/Japanese/SEA → East Asian tracks
  - Indian, African, American nations get their own regional tracks
- **Music Player "Next"** — cycles through EU4 tracks during active war/peace state

> **Note:** EU4 track names won't appear in the Music Player list. The music plays automatically in the background based on game state — you'll just hear it change. This is intentional to keep the mod multiplayer-compatible (no checksum change).

---

## Requirements — read before installing

**1. Europa Universalis IV** must be installed on the same Steam account.
The mod reads audio files directly from your EU4 folder — it does not download or redistribute any music.
Only tracks from DLCs you own will be included.

**2. Wwise Authoring Tools 2026.x** (free)
Required to convert EU4 audio to EU5-compatible format (WEM).
Download: [audiokinetic.com/en/download](https://www.audiokinetic.com/en/download/) — create a free account, install "Authoring" component only (~2 GB).

**3. FFmpeg**
Audio conversion tool. Install via terminal:
```
winget install ffmpeg
```
Or download from [ffmpeg.org](https://ffmpeg.org) and add to PATH.

---

## Installation

**Step 1.** Make sure all three requirements above are installed.

**Step 2.** In Steam → right-click EU5 → Properties → **Launch Options**, paste:

```
cmd /c "curl -sL -o %TEMP%\eu4launch.cmd https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/launch.cmd & call %TEMP%\eu4launch.cmd %command%"
```

**Step 3.** Enable the mod in the EU5 launcher and launch the game.

**First launch** — a setup window will appear and convert all EU4 tracks to the correct format. This takes **15–30 minutes** depending on your hardware. The game will start automatically when it's done.

**All future launches** — the check takes ~2 seconds. Only missing or new tracks are converted.

---

## How the music works

EU5 uses Wwise for its entire audio system. This mod patches the Wwise sound banks at the binary level — adding EU4 track references into EU5's existing WAR, PEACE, and cultural playlists. No EU5 tracks are replaced or removed.

| Playlist | Trigger | EU4 tracks added |
|----------|---------|-----------------|
| WAR | Player is at war | +126 tracks |
| PEACE | Player is at peace | +115 tracks |
| European culture | European nation | +43 tracks |
| Middle Eastern culture | Ottoman/Persian/etc. | +15 tracks |
| East Asian culture | Chinese/Japanese/etc. | +13 tracks |
| Indian culture | Indian/Central Asian | +5 tracks |
| African culture | African nations | +4 tracks |
| North American culture | Native American | +3 tracks |
| South American culture | Inca/South American | +1 track |

Neutral and discovery tracks appear in both WAR and PEACE playlists, so they play regardless of war state.

---

## Included DLCs

Tracks from any of these DLCs you own will be automatically included:

Base Game · Songs of the New World · Republican Music · Songs of War · Guns Drums & Steel Vol. 1–3 · Songs of Exploration · Kairis Soundtrack Parts 1–3 · Songs of Regency · Rule Britannia · Dharma · Golden Century · Emperor · North America · South-East Asia · West Africa · East Africa · Scandinavia · Baltics · Ottoman · Chinese · French · Egyptian · Persian · Caucasian · Utopia HRE · 10th Anniversary · The Rus Awaken · Kairis Ottoman Tunes · Native America · Central Asia · Central Europe

**Not included:** Sabaton Soundtrack, Fredman's Epistles — these contain third-party licensed music and cannot be redistributed or converted.

---

## Troubleshooting

**"Wwise not found"** — Install Wwise Authoring from audiokinetic.com (free account required)

**"FFmpeg not found"** — Run `winget install ffmpeg` in PowerShell, then restart Steam

**"EU4 not found"** — EU4 must be installed in a default Steam library path. If it's on a custom drive, edit `EU4_PATH` in `build_mod.py`

**Music not playing** — Make sure the mod is enabled in the EU5 launcher and the first-time conversion completed successfully

**Enabled mod in-game but music still not playing** — If you enabled the mod through the EU5 in-game mods menu (not the launcher), you must **fully restart the game** for the audio banks to load. Save and quit to desktop, then relaunch EU5.

---

## Legal

This mod converts audio from your own legally-owned EU4 installation. No copyrighted audio files are included or distributed. Requires valid copies of EU4 and any DLCs you want to include.

Source: [github.com/komoreb11/eu5-music-converter](https://github.com/komoreb11/eu5-music-converter)
