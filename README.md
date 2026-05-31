# 🎵 EU4 Soundtrack for EU5

Adds **155 tracks** from Europa Universalis IV to EU5, fully integrated into the dynamic war/peace/culture music system. Multiplayer compatible.

## ✨ What it does

| Feature | Details |
|---------|---------|
| 🗡️ War music | EU4 war tracks play automatically during conflicts |
| ☮️ Peace music | EU4 ambient tracks during peacetime |
| 🎭 Cultural music | Regional tracks match your nation's culture (European, East Asian, Ottoman, etc.) |
| ⏭️ Next button | Cycles EU4 tracks in the Music Player |
| 🌐 Multiplayer | Checksum unchanged — works in multiplayer |

> **Note:** EU4 track names don't appear in the Music Player UI (to preserve checksum compatibility). Music plays automatically based on game state.

## 🚀 Quick Setup

### 1. Add Steam launch option

In Steam → EU5 → Properties → **Launch Options**, paste:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr 'https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.ps1' -OutFile '$env:TEMP\eu4snd.ps1'; & '$env:TEMP\eu4snd.ps1' -LaunchCmd '%COMMAND%'"
```

### 2. Install required tools (one-time)

| Tool | Required for | Download |
|------|-------------|----------|
| **FFmpeg** | Audio conversion | `winget install ffmpeg` or [ffmpeg.org](https://ffmpeg.org) |
| **Wwise Authoring** | WEM encoding | [audiokinetic.com](https://www.audiokinetic.com/en/download/) — free account, install "Authoring" only |

### 3. Launch EU5

On **first launch** (~15-30 min): script converts EU4 audio files automatically.  
On **subsequent launches** (~2 sec): checks for new/missing tracks only.

## 📦 Included tracks (155 total)

Requires EU4 + DLCs you own. Missing DLCs are skipped automatically.

- Base game (23 tracks)
- Guns, Drums & Steel Vol. 1–3
- Kairis Soundtrack Parts 1–3
- 10th Anniversary, Utopia HRE
- Regional packs: Ottoman, Chinese, French, British, Scandinavian, Baltic, Persian, Egyptian, Caucasian, African, American, Indian, Central Asian, Central European, Rus Awaken

**Not included:** Sabaton (third-party license), Fredman's Epistles

## 🔧 Manual run

```powershell
# Download and run directly
irm https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.ps1 | iex
```

Or clone the repo and run `EU4_Soundtrack_Setup.ps1` manually.

## 📜 Legal

This mod reads audio from **your own EU4 installation** and converts it locally. No copyrighted files are distributed. Requires legal copies of EU4 and its DLCs.
