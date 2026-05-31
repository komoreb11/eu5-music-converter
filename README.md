# EU4 Soundtrack for EU5

Adds **155 tracks** from Europa Universalis IV to EU5, fully integrated into the dynamic music system.

## Features

- **War music** — EU4 war tracks play automatically during conflicts
- **Peace music** — EU4 ambient tracks during peacetime
- **Cultural music** — Regional tracks match your nation's culture (European, East Asian, Ottoman, etc.)
- **Next button** — cycles EU4 tracks in the Music Player during war/peace
- **Multiplayer compatible** — checksum unchanged

> EU4 track names are not shown in the Music Player UI (to preserve checksum compatibility). Music plays automatically.

---

## Installation

### Requirements
| Tool | How to install |
|------|---------------|
| Wwise Authoring 2026.x | [audiokinetic.com](https://www.audiokinetic.com/en/download/) — free account, "Authoring" only |
| FFmpeg | `winget install ffmpeg` or [ffmpeg.org](https://ffmpeg.org) |
| Europa Universalis IV | Must own on Steam + any music DLCs |

### Steam Launch Option

In Steam → EU5 → Properties → **Launch Options**:

```
cmd /c "curl -sL -o %TEMP%\eu4launch.cmd https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/launch.cmd & call %TEMP%\eu4launch.cmd %command%"
```

**First launch:** converts all EU4 audio files (15–30 min). Subsequent launches: instant check (~2 sec).

---

## How it works

EU5 uses Wwise for audio. This mod patches the Wwise sound banks to add EU4 tracks to three systems:

| System | Trigger | EU4 tracks added |
|--------|---------|-----------------|
| WAR playlist | Player at war | +126 segments |
| PEACE playlist | Player at peace | +115 segments |
| Cultural playlists | Nation's culture group | +84 segments |

The Next button in the Music Player cycles through all tracks in the active WAR or PEACE playlist.

---

## Track list by system

### WAR + PEACE (universal — all nations)
40 war tracks + 29 peace tracks + 86 neutral/discovery = **155 total**

Base game orchestral, GDS remixes, Kairis, Songs of War, Songs of Regency, 10th Anniversary, and more.

### Cultural playlists (by culture group)

| Culture | Tracks | Sources |
|---------|--------|---------|
| **European** | 43 | British Isles, French, HRE, Scandinavian, Baltic, Russian, Iberian, Central Europe |
| **Middle Eastern** | 15 | Ottoman, Persian, Egyptian, Caucasian, Kairis Ottoman |
| **East Asian** | 13 | Chinese, South-East Asian, Kairis Parts 1-3 |
| **Indian** | 5 | Dharma, Central Asia |
| **African** | 4 | West African, East African |
| **North American** | 3 | North America, Native America, Kairis |
| **South American** | 1 | Native America (Inca) |

---

## DLC coverage

Tracks included from (only DLCs you own are converted):

Base Game · Songs of the New World · Republican Music · Songs of War · Guns Drums & Steel Vol.1-3 · Songs of Exploration · Kairis Soundtrack Parts 1-3 · Songs of Regency · Rule Britannia · Dharma · Golden Century · Emperor · North America · South-East Asia · West Africa · East Africa · Scandinavia · Baltics · Ottoman · Chinese · French · Egyptian · Persian · Caucasian · Utopia HRE · 10th Anniversary · The Rus Awaken · Kairis Ottoman Tunes · Native America · Central Asia · Central Europe

**Not included:** Sabaton (third-party license), Fredman's Epistles (third-party license)

---

## Legal

This mod converts audio from **your own EU4 installation** locally. No copyrighted files are distributed. Requires legal copies of EU4 and DLCs.

## Source

[github.com/komoreb11/eu5-music-converter](https://github.com/komoreb11/eu5-music-converter)
