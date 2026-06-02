# EU4 Soundtrack for EU5

Brings 155 tracks from Europa Universalis IV into EU5's dynamic music system — without Wwise, without redistributing any audio.

**[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3736271606)**

---

## Requirements

- **Europa Universalis IV** installed on the same Steam account
- **FFmpeg** — `winget install ffmpeg`

That's it. No Wwise, no Python, no manual steps beyond the launch option.

---

## Installation

Add to EU5 **Launch Options** in Steam:

```
cmd /c "curl -sL -o %TEMP%\eu4launch.cmd https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/launch.cmd & call %TEMP%\eu4launch.cmd %command%"
```

First launch converts all EU4 tracks (~2–5 min). Game starts automatically when done.

---

## How it works — technical details

### Audio conversion pipeline

```
EU4 OGG → ffmpeg (decode to PCM WAV) → oggenc2/aoTuV (re-encode floor type 1) → C# WEM builder → Wwise WEM
```

**Why not direct OGG→WEM?**  
Standard libvorbis produces Vorbis floor type 0. Wwise requires floor type 1 (aoTuV encoding). The script auto-downloads `oggenc2.exe` (aoTuV b6.03) from RareWares.

**Why not Wwise anymore?**  
Previous v1 used WwiseConsole.exe for conversion (2GB install, account required). v2 replaces it entirely by reverse-engineering the WEM format.

### WEM format (Wwise v150, external packed codebooks)

EU5 uses **Wwise Modified Vorbis** with **external packed codebooks** (`packed_codebooks_aoTuV_603.bin`). The WEM structure:

```
RIFF/WAVE
├── fmt  (66 bytes) — codec 0xFFFF, Wwise fmt extra with seek table info
├── hash (16 bytes) — unused
└── data
    ├── seek_table    — uint32[] packet offsets every ~2048 bytes
    ├── size_prefix   — uint16 setup size
    ├── wwise_setup   — codebook IDs (10-bit each) + floor/residue/mapping/mode
    └── audio_packets — [size(2)][modified_vorbis_packet]
```

**Setup conversion** (std Vorbis → Wwise):
- Codebooks: match each std Vorbis codebook against `packed_codebooks_aoTuV_603.bin` → write 10-bit ID
- `time_type` fields: omitted in Wwise (hardcoded 0)
- `floor_type` fields: omitted in Wwise (hardcoded 1)
- `residue_type`: 16 bits → 2 bits
- `mapping_type`: omitted (hardcoded 0)
- `mode windowtype/transformtype`: omitted (hardcoded 0)
- `mapping_count_m1`: 6 bits in both std Vorbis and Wwise (despite spec saying 4)

**Audio packet conversion** (std Vorbis → Wwise modified):
- Remove 1-bit packet type prefix (always 0)
- For long-mode packets: remove 2 window type bits (prev/next)
- Wwise derives window types from adjacent packet mode numbers at decode time

### Sound bank patching

EU5's music system is in `sb_music_logic.bnk` (Wwise v150 HIRC format). The mod creates `eu4_soundtrack_music.bnk` loaded after EU5's bank ("last loaded wins"):

- **WAR container** (`0x3de374bf`): +126 EU4 segments added to StepRandom
- **PEACE container** (`0x290f1591`): +115 EU4 segments added to StepRandom  
- **Cultural playlists** (7 containers): regional EU4 tracks matched by `stg_local_context_culture` state

Each EU4 track creates HIRC objects: MusicTrack → MusicSegment → inserted into playlist StepRandom leaf items. The patch avoids updating `ulNumChilds` to prevent `result:15` circular dependency errors.

### Media bank

`eu4_soundtrack_media.bnk` contains prefetch data (first 8192 bytes of each WEM). Required for seamless streaming — without it Wwise can't find packet boundaries after the prefetch boundary.

Prefetch is rebuilt automatically when new WEMs are generated (`$done > 0`).

### Determinism

The conversion is deterministic: same EU4 source + same oggenc2 version → identical WEM files across machines. Users with identical DLC sets produce bit-for-bit identical WEMs.

### Music system modes

EU5's `mus_systemType` state group controls playback:
- `dynamic_all` — WAR/PEACE + cultural playlists simultaneously (cultural tends to dominate)
- `dynamic_cinematic` — WAR/PEACE only (most varied, recommended)
- `dynamic_cultural` — cultural only

---

## Multiplayer compatibility

All files in `loading_screen/` are excluded from EU5's checksum. No checksum change, fully multiplayer-compatible.

---

## Files

| File | Purpose |
|------|---------|
| `EU4_Soundtrack_Setup.ps1` | Main Windows setup script (v2, no Wwise) |
| `launch.cmd` | Steam launch wrapper — downloads and runs setup script |
| `build_mod.py` | Developer tool — builds `eu4_soundtrack_music.bnk` from scratch |
| `loading_screen/sound/banks/windows/eu4_soundtrack_music.bnk` | Wwise HIRC bank with EU4 track routing |
| `loading_screen/sound/banks/windows/SoundbanksInfo.json` | Wwise bank manifest |

---

## Legal

Converts audio from the user's own legally-owned EU4 installation. No audio files distributed. Requires EU4 + DLCs.
