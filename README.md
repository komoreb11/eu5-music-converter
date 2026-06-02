# EU4 Soundtrack for EU5

Brings 179 tracks from Europa Universalis IV into EU5 — fully integrated into the game's dynamic music engine. War, peace, and cultural context all trigger the right tracks automatically, just like in the original games.

**[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3736271606)**

---

## What it does

**179 tracks** from EU4 and its music DLCs are woven into EU5's adaptive music system:

- **At war** — EU4 war tracks play alongside EU5 music
- **At peace** — EU4 ambient and atmospheric tracks
- **Cultural context** — regional EU4 music matches your nation's culture group:
  - European → British, French, HRE, Scandinavian, Russian, Iberian
  - Ottoman/Persian/Egyptian/Caucasian → Middle Eastern
  - Chinese/Japanese/SEA → East Asian
  - Indian, African, American nations get their own regional tracks

> EU4 track names won't appear in the Music Player list. The music plays automatically based on game state. You can still skip with the **Next** button. Intentional — keeps the mod multiplayer-compatible (no checksum change).

---

## Requirements

- **Europa Universalis IV** installed on the same Steam account
- **FFmpeg** — `winget install ffmpeg`

No Wwise, no Python.

---

## Installation

**Step 1.** Install FFmpeg.

**Step 2.** Add to EU5 **Launch Options** in Steam:

```
cmd /c "curl -sL -o %TEMP%\eu4launch.cmd https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/launch.cmd & call %TEMP%\eu4launch.cmd %command%"
```

**Step 3.** Launch EU5 → setup window converts all tracks (~2–5 min) → game starts.

**Step 4.** In-game mods menu → enable **EU4 Soundtrack for EU5** → restart.

After first conversion the launch command and FFmpeg are no longer required.

---

## Playlist breakdown

| Playlist | Trigger | EU4 tracks |
|----------|---------|-----------|
| WAR | At war | +146 |
| PEACE | At peace | +135 |
| European culture | European nation | +43 |
| Middle Eastern | Ottoman/Persian/etc. | +19 |
| East Asian | Chinese/Japanese/etc. | +15 |
| Indian | Indian/Central Asian | +5 |
| African | African nations | +4 |
| North American | Native American | +4 |
| South American | Inca/South American | +1 |

Regional tracks appear in both WAR/PEACE and their cultural playlist — ~2× playback frequency for matching cultures.

---

## Included DLCs

Base Game · Songs of the New World · Republican Music · Songs of War · Guns Drums & Steel Vol. 1–3 · Songs of Exploration · Kairis Soundtrack Parts 1–3 · Songs of Regency · Rule Britannia · Dharma · Golden Century · Emperor · North America · South-East Asia · West Africa · East Africa · Scandinavia · Baltics · Ottoman · Chinese · French · Egyptian · Persian · Caucasian · Utopia HRE · 10th Anniversary · The Rus Awaken · Kairis Ottoman Tunes · Native America · Central Asia · Central Europe

**Not included:** Sabaton Soundtrack, Fredman's Epistles — third-party licensed music.

---

## Technical details

### Conversion pipeline

```
EU4 OGG → ffmpeg (PCM pipe) → oggenc2/aoTuV (OGG floor1) → C# WEM builder → Wwise WEM
```

ffmpeg pipes PCM directly to oggenc2 stdin — no temp WAV on disk.

**Why aoTuV specifically?**  
Standard libvorbis (all quality levels) produces **Vorbis floor type 0**. Wwise's decoder only supports **floor type 1** (aoTuV encoding). The setup script auto-downloads `oggenc2.exe` (aoTuV b6.03, ~1.4 MB) from RareWares on first run.

**packed_codebooks_aoTuV_603.bin**  
598 pre-encoded Vorbis codebooks from the ww2ogg project. aoTuV at quality 6 produces codebooks that map 1:1 into this library (IDs 50–93 for 48 kHz stereo). Each codebook stored as Wwise inline format (4-bit dims, 14-bit entries). The C# lookup table matches each OGG codebook against the library by canonical byte comparison. Downloaded from `hcs64/ww2ogg` on first run (~74 KB), validated by exact file size.

---

### WEM file format (Wwise v150)

EU5 uses **Wwise Modified Vorbis** with **external packed codebooks**. No `vorb` chunk — all metadata in the `fmt` extra (48 bytes).

#### RIFF layout

```
RIFF/WAVE
├── fmt  (66 bytes)
│   └── extra (48 bytes) — Wwise-specific metadata
├── hash (16 bytes)      — unused, zeroed
└── data
    ├── seek_table       — uint32[] byte offsets, one entry per ~2048 audio bytes
    ├── [uint16 setup_size]
    ├── wwise_setup      — codebook IDs + stripped floor/residue/mapping/mode
    └── audio_packets    — [uint16 size][modified vorbis packet] × N
```

#### fmt extra fields (48 bytes)

| Offset | Size | Field |
|--------|------|-------|
| 0 | 6 | Version marker (`00 00 02 31 00 00`) |
| 6 | 4 | `dwTotalPCMFrames` |
| 10 | 4 | `dwLoopStartPacketOffset` (= audio_start) |
| 14 | 4 | `dwLoopEndPacketOffset` (= data_end) |
| 18 | 2+2 | Loop extras (0) |
| 22 | 4 | `dwSeekTableSize` = `_setup_packet_offset` for ww2ogg |
| 26 | 4 | `dwVorbisDataOffset` = `_first_audio_packet_offset` for ww2ogg |
| 30 | 2 | `uMaxPacketSize` |
| 32 | 2 | `uLastGranuleExtra` |
| 34 | 4 | `dwDecodeAllocSize` = `(1 << bs1) * ch * 2` |
| 38 | 4 | `dwDecodeX64AllocSize` = `(1 << bs1) * ch * 4` |
| 42 | 4 | Reserved |
| 46 | 1+1 | `uBlockSizes[0/1]` = small/large block exponents |

**Seek table placement:** stored *before* the setup in the data chunk. `dwSeekTableSize` doubles as `_setup_packet_offset` for the ww2ogg reader — setup is at `data[seek_sz]`, audio at `data[seek_sz + 2 + setup_sz]`. Without a seek table, Wwise cannot find packet boundaries after the 8 KB prefetch boundary → only prefetch plays.

---

### Setup packet conversion (std Vorbis → Wwise)

All differences between Wwise WEM setup and standard Vorbis setup:

| Field | Std Vorbis | Wwise |
|-------|-----------|-------|
| `time_type` per entry | 16 bits | **absent** (hardcoded 0) |
| `floor_type` per floor | 16 bits | **absent** (hardcoded 1) |
| `subclass_books` | `book+1`, 0=none | same (ww2ogg passes through verbatim) |
| `residue_type` | 16 bits | **2 bits** |
| `mapping_type` | 16 bits | **absent** (hardcoded 0) |
| `mapping_count_m1` | **6 bits** (not 4 as spec says) | 6 bits |
| `mode windowtype` | 16 bits | **absent** (hardcoded 0) |
| `mode transformtype` | 16 bits | **absent** (hardcoded 0) |

After codebook IDs, the remaining setup bits are copied verbatim with these transformations applied. One quirk: the std Vorbis spec says `mapping_count_m1` is 4 bits, but libvorbis/aoTuV actually writes 6 bits — empirically confirmed.

---

### Modified Vorbis audio packets

Each Wwise audio packet differs from std Vorbis by having 1–3 bits removed from the start:

| Packet type | Std Vorbis | Wwise |
|-------------|-----------|-------|
| Short mode | `[0][mode_num]...` | `[mode_num]...` (1 bit removed) |
| Long mode | `[0][mode_num][prev_win][next_win]...` | `[mode_num]...` (3 bits removed) |

The `0` is the audio packet type bit (always 0). `prev_win`/`next_win` are previous/next window type bits used for overlapped windowing — Wwise derives these from adjacent packet mode numbers at decode time instead of storing them explicitly.

**Mode detection:** `mode_bits = ilog(mode_count - 1)`. Long/short determined by `mode_blockflag[mode_num]` from the setup.

---

### Sound bank patching

EU5's music system lives in `sb_music_logic.bnk` (Wwise v150 HIRC format, 3402 objects). The mod creates `eu4_soundtrack_music.bnk` loaded after EU5's bank via `SoundbanksInfo.json` — Wwise "last loaded wins" semantics for duplicate object IDs.

**WAR container** (`0x3de374bf`) / **PEACE container** (`0x290f1591`)  
Each EU4 track adds a `MusicTrack` + `MusicSegment` pair as a leaf in the `MusicRandSeqCntr` StepRandom list. The patch only updates `numPlaylistItems` and the StepRandom leaf array — deliberately avoids updating `ulNumChilds` to prevent `AK_IDNotFound` (result:15) circular dependency errors.

**Cultural containers** (7 containers keyed by `stg_local_context_culture` state)  
Regional EU4 tracks are added to the matching culture's `MusicRandSeqCntr`. EU5 has containers for European (68 tracks) and East Asian (27 tracks); the mod adds containers for other regions. Per-culture containers (aztec, iroquois, etc.) have 3–4 EU5 tracks each.

**HIRC object IDs**  
Generated via FNV-1 hash: `event_name + "_wem"` → WEM file ID. EU4 tracks create: `mp_track`, `war_dyn_track`, `pce_dyn_track`, optionally `culture_dyn_track` — each with its own `MusicSegment` pointing to the same WEM file.

**MusicTrack template**  
Copied from EU5 track `0x13771d69` (111 bytes, `numPlaylistItem=1`). Previous template (`0x25153c8e`, 155 bytes, `numPlaylistItem=2`) caused crashes — second playlist item had null sourceID triggering `AK::WriteBytesMem` access violation.

---

### Media bank (prefetch)

`eu4_soundtrack_media.bnk` contains DIDX + DATA chunks: the first 8192 bytes of each WEM file stored inline. Wwise plays this while initiating streaming from disk. Without matching prefetch, Wwise cannot seamlessly transition → only prefetch audio plays then silence.

The setup script rebuilds `media.bnk` from current WEM files whenever new WEMs are generated (`$done > 0`). `media.bnk` is **not** synced from GitHub — rebuilt locally to always match local WEM content. Supports mixed v1 (Wwise) + v2 (aoTuV) WEM files transparently.

---

### EU5 music system internals

EU5's Wwise state group `mus_systemType` controls which playlists are active:

| State | Behavior |
|-------|----------|
| `dynamic_cinematic` | WAR/PEACE only — most varied, recommended |
| `dynamic_all` | WAR/PEACE + cultural simultaneously (cultural dominates for Europeans: 68+43 tracks) |
| `dynamic_cultural` | Cultural only |
| `dynamic_full` | All systems |
| `static_cinematic` / `static_cultural` | Static playlists |

The `MusicDensity` slider (0.0/0.5/1.0) exists in Jomini engine code but is **disabled** in EU5's GUI — always 1.0 (continuous music).

EU5 uses `stg_local_context_culture` state for cultural routing. This state is set per-player based on culture. Non-European/East Asian cultures have no EU5 cultural container → fall through to WAR/PEACE only.

---

### Checksum safety

All mod files are in `loading_screen/` — excluded from EU5's checksum manifest. Fully multiplayer-compatible.

---

## Troubleshooting

**"FFmpeg not found"** — `winget install ffmpeg`, then restart Steam

**"EU4 not found"** — EU4 must be installed via Steam. The script searches all Steam library paths via `libraryfolders.vdf` and the Windows registry (`Steam App 236850`).

**"packed_codebooks.bin download failed"** — Check internet connection. The file (~74 KB) is downloaded from `github.com/hcs64/ww2ogg`

**Only prefetch plays (brief audio then silence)** — Delete all `.wem` files from the mod's `Media/` folder and re-run the script. media.bnk needs to be rebuilt from current WEMs.

**Music not playing** — Make sure the mod is enabled and the game was restarted after enabling it

---

## Legal

Converts audio from the user's own legally-owned EU4 installation. No audio files included or distributed. Requires EU4 + DLCs.

---

## Changelog

**v1.2** — 179 tracks
- Added 24 previously missing tracks across 13 DLCs: Republican Music, Songs of War, Guns Drums & Steel Vol. 1–2, Songs of Exploration, Kairis Soundtrack, Songs of Regency, Egyptian, Persian, Caucasian, Native America, Central Asia, Central Europe
- Removed Wwise project from repository
- Rebuilt HIRC bank with updated track list

**v1.1** — 155 tracks, no Wwise
- Eliminated Wwise Authoring requirement — full OGG→WEM conversion implemented in C#
- Auto-download of required tools (oggenc2/aoTuV, packed_codebooks, libFLAC) on first run
- ffmpeg pipes PCM directly to oggenc2 — no temp WAV on disk
- media.bnk rebuilt automatically after conversion
- Auto-detection of Steam library and Workshop mod path

**v1.0** — 155 tracks
- Initial release — required Wwise Authoring + FFmpeg
