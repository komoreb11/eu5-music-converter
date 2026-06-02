# EU4 Soundtrack for EU5

Brings 155 tracks from Europa Universalis IV into EU5 — fully integrated into the game's dynamic music engine. War, peace, and cultural context all trigger the right tracks automatically, just like in the original games.

**[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3736271606)**

---

## What it does

**155 tracks** from EU4 and its music DLCs are woven into EU5's adaptive music system:

- **At war** — EU4 war tracks play alongside EU5 music
- **At peace** — EU4 ambient and atmospheric tracks
- **Cultural context** — regional EU4 music matches your nation's culture group:
  - European nations hear British, French, HRE, Scandinavian, Russian, Iberian tracks
  - Ottoman/Persian/Egyptian/Caucasian → Middle Eastern tracks
  - Chinese/Japanese/SEA → East Asian tracks
  - Indian, African, American nations get their own regional tracks

> EU4 track names won't appear in the Music Player list. The music plays automatically in the background based on game state. You can still skip to the next track using the **Next** button. This is intentional to keep the mod multiplayer-compatible (no checksum change).

---

## Requirements

- **Europa Universalis IV** installed on the same Steam account
- **FFmpeg** — `winget install ffmpeg`

No Wwise, no Python, no manual steps beyond the launch option.

---

## Installation

**Step 1.** Install FFmpeg.

**Step 2.** Add to EU5 **Launch Options** in Steam:

```
cmd /c "curl -sL -o %TEMP%\eu4launch.cmd https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/launch.cmd & call %TEMP%\eu4launch.cmd %command%"
```

**Step 3.** Launch EU5 → setup window converts all tracks (~2–5 min) → game starts.

**Step 4.** In-game mods menu → enable **EU4 Soundtrack for EU5** → restart.

After first conversion the launch command and FFmpeg are no longer required. Keep them to automatically pick up any new EU4 tracks added to your game folder.

---

## Included DLCs

Base Game · Songs of the New World · Republican Music · Songs of War · Guns Drums & Steel Vol. 1–3 · Songs of Exploration · Kairis Soundtrack Parts 1–3 · Songs of Regency · Rule Britannia · Dharma · Golden Century · Emperor · North America · South-East Asia · West Africa · East Africa · Scandinavia · Baltics · Ottoman · Chinese · French · Egyptian · Persian · Caucasian · Utopia HRE · 10th Anniversary · The Rus Awaken · Kairis Ottoman Tunes · Native America · Central Asia · Central Europe

**Not included:** Sabaton Soundtrack, Fredman's Epistles — third-party licensed music.

---

## Playlist breakdown

| Playlist | Trigger | EU4 tracks |
|----------|---------|-----------|
| WAR | At war | +126 |
| PEACE | At peace | +115 |
| European culture | European nation | +43 |
| Middle Eastern culture | Ottoman/Persian/etc. | +15 |
| East Asian culture | Chinese/Japanese/etc. | +13 |
| Indian culture | Indian/Central Asian | +5 |
| African culture | African nations | +4 |
| North American culture | Native American | +3 |
| South American culture | Inca/South American | +1 |

Regional tracks appear in both WAR/PEACE and their cultural playlist — they play ~2× as often for matching cultures.

---

## Troubleshooting

**"FFmpeg not found"** — Run `winget install ffmpeg` in PowerShell, then restart Steam

**"EU4 not found"** — EU4 must be installed via Steam. The script searches all Steam library paths and the Windows registry automatically.

**Music not playing** — Make sure the mod is enabled and the game was restarted after enabling it

---

## Technical details

### Audio conversion pipeline

```
EU4 OGG → ffmpeg (decode PCM) → oggenc2/aoTuV (floor type 1) → C# WEM builder → Wwise WEM
```

**Why not direct OGG→WEM?**  
Standard libvorbis produces floor type 0. Wwise requires floor type 1 (aoTuV encoding). The script auto-downloads `oggenc2.exe` (aoTuV b6.03).

### WEM format (Wwise v150, external packed codebooks)

```
RIFF/WAVE
├── fmt  (66 bytes) — codec 0xFFFF, Wwise fmt extra with seek table info
├── hash (16 bytes)
└── data
    ├── seek_table    — uint32[] packet offsets every ~2048 bytes
    ├── size_prefix   — uint16 setup size
    ├── wwise_setup   — codebook IDs (10-bit) + floor/residue/mapping/mode
    └── audio_packets — [size(2)][modified_vorbis_packet]
```

**Setup conversion** (std Vorbis → Wwise):
- Codebooks matched against `packed_codebooks_aoTuV_603.bin` → 10-bit IDs
- `floor_type`, `mapping_type`, mode `windowtype`/`transformtype`: omitted (Wwise hardcodes)
- `residue_type`: 16 bits → 2 bits
- `mapping_count_m1`: 6 bits in both (despite Vorbis spec saying 4)

**Audio packet conversion** (std → Wwise modified):
- Remove 1-bit packet type prefix
- For long-mode packets: remove 2 window type bits (prev/next)

### Sound bank patching

`eu4_soundtrack_music.bnk` loads after EU5's `sb_music_logic.bnk` ("last loaded wins"):
- **WAR** (`0x3de374bf`) / **PEACE** (`0x290f1591`): EU4 segments added to StepRandom
- **Cultural playlists** (7 containers): regional tracks by `stg_local_context_culture` state

### Music system modes

EU5's `mus_systemType` controls playback:
- `dynamic_cinematic` — WAR/PEACE only (most varied, recommended)
- `dynamic_all` — WAR/PEACE + cultural (cultural tends to dominate for Europeans)
- `dynamic_cultural` — cultural only

---

## Files

| File | Purpose |
|------|---------|
| `EU4_Soundtrack_Setup.ps1` | Windows setup script (no Wwise required) |
| `launch.cmd` | Steam launch wrapper |
| `build_mod.py` | Developer tool — builds `eu4_soundtrack_music.bnk` |
| `loading_screen/sound/banks/windows/eu4_soundtrack_music.bnk` | Wwise HIRC bank |
| `loading_screen/sound/banks/windows/SoundbanksInfo.json` | Wwise bank manifest |

---

## Legal

Converts audio from the user's own legally-owned EU4 installation. No audio files included or distributed. Requires EU4 + DLCs.
