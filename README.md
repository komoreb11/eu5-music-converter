# EU4 Soundtrack for EU5

Brings 179 tracks from Europa Universalis IV into EU5 — fully integrated into the game's dynamic music engine. War, peace, and cultural context all trigger the right tracks automatically, just like in the original games.

**[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3736271606)**

---

## What it does

**179 tracks** from EU4 and its music DLCs are woven into EU5's adaptive music system:

- **At war** — EU4 war tracks play alongside EU5 music
- **At peace** — EU4 ambient and atmospheric tracks
- **Cultural context** — regional EU4 music matches your nation's culture group:
  - European → British, French, HRE, Scandinavian, Russian, Iberian, Caucasian
  - Ottoman/Persian/Egyptian/Arab/Central Asian → Middle Eastern
  - Chinese/Japanese → East Asian, South-East Asia → Indian
  - Indian, African, American nations get their own regional tracks

> EU4 track names won't appear in the Music Player list. The music plays automatically based on game state. You can still skip with the **Next** button. Intentional — keeps the mod multiplayer-compatible (no checksum change).

---

## Requirements

- **Europa Universalis IV** installed on the same Steam account
- **Windows:** **FFmpeg** — `winget install ffmpeg`. No Wwise, no Python.
- **Linux / Steam Deck** (EU5 via Proton): **python3** and **FFmpeg with libvorbis** (`sudo apt install ffmpeg`, `sudo pacman -S ffmpeg`, ...). SteamOS ships python3 but not FFmpeg.

---

## Installation

**Step 1.** Install FFmpeg.

**Step 2.** Add to EU5 **Launch Options** in Steam:

```
cmd /c "curl -sfL -o %TEMP%\eu4launch.cmd https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/launch.cmd & call %TEMP%\eu4launch.cmd %command%"
```

**Step 3.** Launch EU5 → setup window converts all tracks (~2–5 min) → game starts.

**Step 4.** In-game mods menu → enable **EU4 Soundtrack for EU5** → restart.

After first conversion FFmpeg is no longer required. Keep the launch command: every launch it downloads the current setup script and rebuilds the sound banks from the tracks you have and the installed EU5 version (takes a second). Fixes are delivered this way — no Workshop update needed.

### Linux / Steam Deck

Same steps, with this **Launch Options** line instead:

```
bash -c 'f="$HOME/.cache/eu4snd_setup.sh"; mkdir -p "$HOME/.cache"; curl -sfL -o "$f.tmp" https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.sh && mv "$f.tmp" "$f"; bash "$f" "$@"' _ %command%
```

`EU4_Soundtrack_Setup.sh` does exactly what the Windows script does, then starts the game. Steam shows no console for launch options: progress and errors appear in a `zenity` dialog when available, and everything is logged to `~/.cache/eu4snd/setup.log`. Steam libraries are found via `libraryfolders.vdf` (native, Flatpak and Snap Steam); extra library paths can be given in `EU4SND_STEAM_LIBRARIES` (colon-separated).

---

## Playlist breakdown

| Playlist | Trigger | EU4 tracks |
|----------|---------|-----------|
| WAR | At war | +146 |
| PEACE | At peace | +135 |
| European culture | European/Caucasian nation | +48 |
| Middle Eastern | Ottoman/Persian/Arab/Central Asian | +19 |
| East Asian | Chinese/Japanese/etc. | +13 |
| Indian | Indian/South-East Asian | +6 |
| African | African nations | +4 |
| North American | North American nations | +1 |
| South American | Mesoamerican/South American | +4 |

Regional tracks appear in both WAR/PEACE and their cultural playlist. Only tracks with a converted WEM on the player's PC are added.

---

## Included DLCs

Base Game · Songs of the New World · Republican Music · Songs of War · Guns Drums & Steel Vol. 1–3 · Songs of Exploration · Kairis Soundtrack Parts 1–3 · Songs of Regency · Rule Britannia · Dharma · Golden Century · Emperor · North America · South-East Asia · West Africa · East Africa · Scandinavia · Baltics · Ottoman · Chinese · French · Egyptian · Persian · Caucasian · Utopia HRE · 10th Anniversary · The Rus Awaken · Kairis Ottoman Tunes · Native America · Central Asia · Central Europe

**Not included:** Sabaton Soundtrack, Fredman's Epistles — third-party licensed music.

---

## Technical details

### Conversion pipeline

```
Windows: EU4 OGG → ffmpeg (PCM pipe) → oggenc2/aoTuV -q 6 → C# WEM builder     → Wwise WEM
Linux:   EU4 OGG → ffmpeg libvorbis -q:a 6 (48 kHz stereo)  → Python WEM builder → Wwise WEM
```

ffmpeg pipes PCM directly to oggenc2 stdin — no temp WAV on disk. On Linux the OGG (or the DLC zip entry) is piped through ffmpeg in memory.

**Encoder.** The WEM builder needs Vorbis floor type 1 and codebooks that exist in `packed_codebooks_aoTuV_603.bin`. On Windows the setup script auto-downloads `oggenc2.exe` (aoTuV b6.03, ~1.4 MB) from RareWares on first run. libvorbis 1.3.7 at quality 6 (48 kHz stereo) writes a byte-identical setup header (same 44 codebooks, IDs 50–93, floor type 1), so Linux uses ffmpeg's libvorbis encoder directly. The Python WEM builder produces byte-identical output to the C# one for the same OGG.

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

EU5's music system lives in `sb_music_logic.bnk` (Wwise v150 HIRC format). `eu4_soundtrack_music.bnk` is a copy of it with patched playlists plus the EU4 objects.

**Built on the player's PC.** A prebuilt bank references all 179 WEMs: when a playlist picked a track from a DLC the player doesn't own, Wwise played silence for the track's length, and the copied EU5 objects went stale with every EU5 patch. So `EU4_Soundtrack_Setup.ps1` (`BankBuilder` C# class) builds both banks on every launch from the installed EU5 `sb_music_logic.bnk`, the WEM files present in `Media/` (duration and prefetch size come from the WEM) and the track list (`$Tracks`: event, source, DLC, mood, culture), and writes them only if they changed. Updates therefore only need a new script on GitHub — `launch.cmd` downloads it on every launch. `BankBuilder` mirrors `build_mod.py`; with all WEMs present both produce byte-identical banks. The banks shipped in the Workshop item are only a fallback.

**Playlists.** The playlist tree (`AkMusicRanSeqPlaylistItem`, 30 bytes each, pre-order) is the last field of a `MusicRanSeqCntr`, so it is located from the end of the object — no hardcoded offsets. Inserts only update item counts, never `ulNumChilds` (avoids `AK_IDNotFound` result:15 circular dependency errors).

**WAR container** (`0x290f1591`) / **PEACE container** (`0x3de374bf`)  
Verified via switch `0x1cb30afd` on state group `PlayerAtWar`: True → `0x290f1591`, False → `0x3de374bf`. EU4 leaves join the root's first child, the flat random pool of EU5 war/peace segments.

**Cultural containers** (switch `0x0e3915aa` on state group `PlayerCulturePrimary`)  
`european_sfx` → `0x172e4eba` (north german), `east_asian_sfx` → `0x2ae87b0d`, `african_sfx` → `0x2d1fe56a`, `middle_east_sfx` → `0x177dfabd`, `indian_sfx` → `0x014173a7`, `north_american_sfx` → `0x0847dcf1` (iroquois), `south_american_sfx` → `0x360b858e` (aztec; mesoamerican cultures use `south_american_gfx`). These playlists are sequences (soloist piece → handles → improvisation → ...) that restart from the top whenever the music switch returns to them (e.g. in Dynamic – All after war/peace music). So EU4 tracks are offered where the cycle starts: the first random pool (the soloist pieces) is wrapped in a new random node choosing between it and a random-step node with the EU4 tracks. EU4 gets 50%, but no more than one soloist piece per EU4 track (`weight = 50000 * min(n_eu4, n_pieces) / n_pieces`). The rest of EU5's structure stays intact.

**HIRC object IDs**  
Generated via FNV-1 hash: `event_name + "_wem"` → WEM file ID. EU4 tracks create: `mp_track`, `war_dyn_track`, `pce_dyn_track`, optionally `culture_dyn_track` — each with its own `MusicSegment` pointing to the same WEM file.

**MusicTrack template**  
Copied from EU5 track `0x13771d69` (111 bytes, `numPlaylistItem=1`). Previous template (`0x25153c8e`, 155 bytes, `numPlaylistItem=2`) caused crashes — second playlist item had null sourceID triggering `AK::WriteBytesMem` access violation.

---

### Media bank (prefetch)

`eu4_soundtrack_media.bnk` contains DIDX + DATA chunks: the first 8192 bytes of each WEM file stored inline. Wwise plays this while initiating streaming from disk. Without matching prefetch, Wwise cannot seamlessly transition → only prefetch audio plays then silence.

The setup script rebuilds `media.bnk` from the current WEM files on every launch and writes it only if it changed. DIDX entries are sorted by media ID, like in all EU5 media banks. Truncated WEMs and old Wwise-authored WEMs (v1.0) are converted again.

---

### EU5 music system internals

EU5's Wwise state group `mus_systemType` controls which playlists are active:

| State | Behavior |
|-------|----------|
| `dynamic_cinematic` | WAR/PEACE only — most varied, recommended |
| `dynamic_all` | WAR/PEACE + cultural simultaneously |
| `dynamic_cultural` | Cultural only |
| `dynamic_full` | All systems |
| `static_cinematic` / `static_cultural` | Static playlists |

The `MusicDensity` slider (0.0/0.5/1.0) exists in Jomini engine code but is **disabled** in EU5's GUI — always 1.0 (continuous music).

EU5 routes cultural music by the `PlayerCulturePrimary` state (`*_sfx` values from `main_menu/music/audio_culture_types`, matched by each culture's `*_gfx` tag). Every base-game culture group has its own container; D008 adds `d008_byzantine_sfx` → `0x312d1324`.

---

### Checksum safety

All mod files are in `loading_screen/` — excluded from EU5's checksum manifest. Fully multiplayer-compatible.

---

## Troubleshooting

**"FFmpeg not found"** — `winget install ffmpeg`, then restart Steam

**"EU4 not found"** — EU4 must be installed via Steam. The script searches all Steam library paths via `libraryfolders.vdf` and the Windows registry (`Steam App 236850`).

**"packed_codebooks.bin download failed"** — Check internet connection. The file (~74 KB) is downloaded from `github.com/hcs64/ww2ogg`

**Only prefetch plays (brief audio then silence) / silent gaps** — Keep the launch option and start the game once: the script rebuilds both banks from the WEM files present.

**Music not playing** — Make sure the mod is enabled and the game was restarted after enabling it

---

## Legal

Converts audio from the user's own legally-owned EU4 installation. No audio files included or distributed. Requires EU4 + DLCs.

---

## Changelog

**v1.3** — fixes, delivered by the setup script (no Workshop update)
- WAR/PEACE playlist IDs were swapped in `build_mod.py`: EU4 war tracks played at peace and vice versa
- Sound banks are built on the player's PC from the installed EU5 bank and the WEMs actually present: no silence for missing DLCs / failed conversions, no stale copy of EU5's music objects after game patches
- Cultural playlists were corrupted by fixed-offset inserts into nested sequences (EU4 tracks played back to back, EU5 items reparented); inserts now parse the playlist tree, and EU4 tracks are an alternative to the soloist piece at the start of the cultural cycle
- media.bnk is rebuilt whenever it doesn't match the WEMs (v1.2 update restored a 155-entry media.bnk → 24 new tracks silent); DIDX sorted by ID
- Regional routing checked against the `tags` of all EU5 cultures (`indian_sfx` has priority 110): Aztec/Mayan themes and Fine Day for Sacrifice → aztec (`south_american_sfx`) instead of iroquois; Caucasian tracks → european (georgian/armenian cultures have `european_gfx`) instead of middle_east; Hordes → middle_east (uzbek/tatar/nogai) instead of indian; South-East Asia tracks → indian (khmer/thai/burmese/malay) instead of east_asian
- WEM conversion writes to `.part` first, truncated WEMs are converted again; the job uses the detected ffmpeg path; tools, ffmpeg and EU4 are only required when there is something to convert
- `launch.cmd`: `curl -f` + temp file, so an HTTP error can't replace the cached setup script

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
