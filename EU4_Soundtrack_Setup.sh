#!/usr/bin/env bash
# EU4 Soundtrack for EU5 - Linux / Steam Deck setup & launcher (EU5 via Proton)
#
# Converts missing EU4 tracks to WEM, rebuilds the mod's sound banks, then starts the game.
# Same logic as EU4_Soundtrack_Setup.ps1 (Windows). Needs python3 and ffmpeg (with libvorbis).
#
# Steam launch option (self-updating from GitHub):
#   bash -c 'f="$HOME/.cache/eu4snd_setup.sh"; mkdir -p "$HOME/.cache"; curl -sfL -o "$f.tmp" https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.sh && mv "$f.tmp" "$f"; bash "$f" "$@"' _ %command%

if ! command -v python3 >/dev/null 2>&1; then
    msg="EU4 Soundtrack: python3 not found. Install Python 3 to use the mod setup."
    echo "[X]  $msg" >&2
    command -v zenity >/dev/null 2>&1 && zenity --error --title="EU4 Soundtrack" --text="$msg" 2>/dev/null
    exit 1
fi

python3 - <<'PYEOF'
import os, sys, re, struct, zipfile, subprocess, shutil, urllib.request, multiprocessing
import concurrent.futures as cf

# --- UI ----------------------------------------------------
# Steam shows no console for launch options: everything goes to a log file too,
# and zenity (if available) shows progress and errors.
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "eu4snd")
os.makedirs(CACHE, exist_ok=True)
LOG = open(os.path.join(CACHE, "setup.log"), "w", encoding="utf-8")
HAS_GUI = bool(shutil.which("zenity") and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")))
_progress = None

def say(prefix, msg):
    line = f"{prefix} {msg}" if prefix else msg
    print(line, flush=True)
    LOG.write(line + "\n"); LOG.flush()

def status(msg): say("[EU4 Soundtrack]", msg)
def ok(msg):     say("[OK]", msg)
def warn(msg):   say("[!] ", msg)

def progress(percent, text):
    global _progress
    if not HAS_GUI: return
    try:
        if _progress is None:
            _progress = subprocess.Popen(["zenity", "--progress", "--title=EU4 Soundtrack", "--auto-close", "--no-cancel",
                                          "--width=420", "--text=" + text], stdin=subprocess.PIPE, text=True,
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _progress.stdin.write(f"{int(percent)}\n# {text}\n"); _progress.stdin.flush()
    except Exception:
        pass

def close_progress():
    global _progress
    if _progress is not None:
        try:
            _progress.stdin.write("100\n"); _progress.stdin.close(); _progress.wait(timeout=5)
        except Exception:
            pass
        _progress = None

def fail(msg):
    close_progress()
    say("[X] ", msg)
    if HAS_GUI:
        subprocess.run(["zenity", "--error", "--title=EU4 Soundtrack", "--width=420", "--text=" + msg],
                       stderr=subprocess.DEVNULL)
    sys.exit(1)

# --- TRACK LIST --------------------------------------------
# EventName, SourceOgg, DlcDir, mood, culture - same order and data as build_mod.TRACKS
TRACKS = [
    ("MusicPlayer_eu4_maintheme", "maintheme.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_dehominisdignitate", "dehominisdignitate.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_kingscourt", "kingscourt.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_kingsinthenorth", "kingsinthenorth.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_machiavelli", "machiavelli.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_nighttime", "nighttime.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_thestonemasons", "thestonemasons.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_moodevent_thesnowiscoming", "moodevent_thesnowiscoming.ogg", "", "neutral", ""),
    ("MusicPlayer_eu4_amongthepoor", "amongthepoor.ogg", "", "peace", ""),
    ("MusicPlayer_eu4_commerceinthepeninsula", "commerceinthepeninsula.ogg", "", "peace", ""),
    ("MusicPlayer_eu4_eire", "eire.ogg", "", "peace", "european"),
    ("MusicPlayer_eu4_inthestreets", "inthestreets.ogg", "", "peace", ""),
    ("MusicPlayer_eu4_mood_landinsight", "mood_landinsight.ogg", "", "peace", ""),
    ("MusicPlayer_eu4_openseas", "openseas.ogg", "", "peace", ""),
    ("MusicPlayer_eu4_thesoundofsummer", "thesoundofsummer.ogg", "", "peace", ""),
    ("MusicPlayer_eu4_battleoflepanto", "battleoflepanto.ogg", "", "war", ""),
    ("MusicPlayer_eu4_event_war_battleofbreitenfeld", "event_war_battleofbreitenfeld.ogg", "", "war", ""),
    ("MusicPlayer_eu4_mykingdom", "mykingdom.ogg", "", "war", ""),
    ("MusicPlayer_eu4_rideforthvictoriously", "rideforthvictoriously.ogg", "", "war", ""),
    ("MusicPlayer_eu4_thestageisset", "thestageisset.ogg", "", "war", ""),
    ("MusicPlayer_eu4_war_offtowar", "war_offtowar.ogg", "", "war", ""),
    ("MusicPlayer_eu4_mood_discovery", "mood_discovery.ogg", "", "discovery", ""),
    ("MusicPlayer_eu4_theageofdiscovery", "theageofdiscovery.ogg", "", "discovery", ""),
    ("MusicPlayer_eu4_thegrandarmada", "music/thegrandarmada.ogg", "dlc013_songs_of_the_new_world", "peace", "european"),
    ("MusicPlayer_eu4_thehunt", "music/thehunt.ogg", "dlc013_songs_of_the_new_world", "neutral", ""),
    ("MusicPlayer_eu4_travelthenewworld", "music/travelthenewworld.ogg", "dlc013_songs_of_the_new_world", "discovery", ""),
    ("MusicPlayer_eu4_pdxmascarol", "music/pdxmascarol.ogg", "dlc014_songs_of_yuletide", "neutral", ""),
    ("MusicPlayer_eu4_rmp_a_new_way", "music/A_new_way.ogg", "dlc026_republican_music", "neutral", ""),
    ("MusicPlayer_eu4_rmp_diplomatic_awakening", "music/Diplomatic_Awakening.ogg", "dlc026_republican_music", "peace", ""),
    ("MusicPlayer_eu4_rmp_falalalan", "music/Falalalan.ogg", "dlc026_republican_music", "neutral", ""),
    ("MusicPlayer_eu4_rmp_introductions", "music/Introductions.ogg", "dlc026_republican_music", "neutral", ""),
    ("MusicPlayer_eu4_rmp_piano_concerto", "music/Piano_Concerto_No_1000.ogg", "dlc026_republican_music", "neutral", ""),
    ("MusicPlayer_eu4_sow_castles", "music/sow_castles.ogg", "dlc030_songs_of_war", "neutral", ""),
    ("MusicPlayer_eu4_sow_distress", "music/sow_distress.ogg", "dlc030_songs_of_war", "war", ""),
    ("MusicPlayer_eu4_sow_george_whitehead", "music/sow_george_whitehead.ogg", "dlc030_songs_of_war", "war", ""),
    ("MusicPlayer_eu4_sow_lautunno", "music/sow_lautunno.ogg", "dlc030_songs_of_war", "war", ""),
    ("MusicPlayer_eu4_sow_the_siege", "music/sow_the_siege.ogg", "dlc030_songs_of_war", "war", ""),
    ("MusicPlayer_eu4_gds_battleoflepanto", "music/031_battleoflepanto.ogg", "dlc031_guns_drums_and_steel", "war", ""),
    ("MusicPlayer_eu4_gds_kingscourt", "music/031_kingscourt.ogg", "dlc031_guns_drums_and_steel", "neutral", ""),
    ("MusicPlayer_eu4_gds_maintheme", "music/031_maintheme.ogg", "dlc031_guns_drums_and_steel", "neutral", ""),
    ("MusicPlayer_eu4_gds_rideforthvictoriously", "music/031_rideforthvictoriously.ogg", "dlc031_guns_drums_and_steel", "war", ""),
    ("MusicPlayer_eu4_gds_thestageisset", "music/031_thestageisset.ogg", "dlc031_guns_drums_and_steel", "war", ""),
    ("MusicPlayer_eu4_soe_asettlement", "music/soe_asettlement.ogg", "dlc036_songs_of_exploration", "peace", ""),
    ("MusicPlayer_eu4_soe_asettlement2", "music/soe_asettlement2.ogg", "dlc036_songs_of_exploration", "peace", ""),
    ("MusicPlayer_eu4_soe_canzonelabavara", "music/soe_canzonelabavara.ogg", "dlc036_songs_of_exploration", "neutral", ""),
    ("MusicPlayer_eu4_soe_redsun", "music/soe_redsun.ogg", "dlc036_songs_of_exploration", "peace", ""),
    ("MusicPlayer_eu4_soe_theconqueror", "music/soe_theconqueror.ogg", "dlc036_songs_of_exploration", "peace", ""),
    ("MusicPlayer_eu4_gds_eire", "music/037_eire.ogg", "dlc037_guns_drums_and_steel_volume_2", "peace", "european"),
    ("MusicPlayer_eu4_gds_mykingdom", "music/037_mykingdom.ogg", "dlc037_guns_drums_and_steel_volume_2", "war", ""),
    ("MusicPlayer_eu4_gds2_commerceinthepeninsula", "music/037_commerceinthepeninsula.ogg", "dlc037_guns_drums_and_steel_volume_2", "neutral", ""),
    ("MusicPlayer_eu4_gds2_theageofdiscovery", "music/037_theageofdiscovery.ogg", "dlc037_guns_drums_and_steel_volume_2", "peace", ""),
    ("MusicPlayer_eu4_gds2_thestonemasons", "music/037_thestonemasons.ogg", "dlc037_guns_drums_and_steel_volume_2", "neutral", ""),
    ("MusicPlayer_eu4_kairis_emperors_road", "music/Emperors_Road.ogg", "dlc044_kairis_soundtrack", "neutral", "east_asian"),
    ("MusicPlayer_eu4_kairis_forest_shade", "music/Forest_Shade.ogg", "dlc044_kairis_soundtrack", "peace", ""),
    ("MusicPlayer_eu4_kairis_jade_ambitions", "music/Jade_Ambitions.ogg", "dlc044_kairis_soundtrack", "neutral", "east_asian"),
    ("MusicPlayer_eu4_kairis_silken_path", "music/Silken_Path.ogg", "dlc044_kairis_soundtrack", "neutral", "east_asian"),
    ("MusicPlayer_eu4_kairis_takeda_sunrise", "music/Takeda_Sunrise.ogg", "dlc044_kairis_soundtrack", "neutral", "east_asian"),
    ("MusicPlayer_eu4_ksp2_eastern_fronts", "music/ksp2_eastern_fronts.ogg", "dlc059_kairis_soundtrack_part_2", "war", "east_asian"),
    ("MusicPlayer_eu4_ksp2_peace_for_generations", "music/ksp2_peace_for_generations.ogg", "dlc059_kairis_soundtrack_part_2", "peace", "east_asian"),
    ("MusicPlayer_eu4_ksp2_temple_ambitions", "music/ksp2_temple_ambitions.ogg", "dlc059_kairis_soundtrack_part_2", "neutral", "east_asian"),
    ("MusicPlayer_eu4_ksp2_the_grasslands_call", "music/ksp2_the_grasslands_call.ogg", "dlc059_kairis_soundtrack_part_2", "discovery", ""),
    ("MusicPlayer_eu4_ksp2_the_great_wall", "music/ksp2_the_great_wall.ogg", "dlc059_kairis_soundtrack_part_2", "neutral", "east_asian"),
    ("MusicPlayer_eu4_sormp_a_golden_sun_is_rising", "music/sormp_A_Golden_Sun_is_Rising_Ambient.ogg", "dlc063_songs_of_regency", "peace", "european"),
    ("MusicPlayer_eu4_sormp_for_honour_and_glory", "music/sormp_For_Honour_and_Glory_War.ogg", "dlc063_songs_of_regency", "war", "european"),
    ("MusicPlayer_eu4_sormp_our_destiny", "music/sormp_Our_Destiny_Ambient.ogg", "dlc063_songs_of_regency", "peace", ""),
    ("MusicPlayer_eu4_sormp_i_didnt_choose", "music/sormp_I_didnt_choose_this_life_it_chose_me_Ambient.ogg", "dlc063_songs_of_regency", "neutral", ""),
    ("MusicPlayer_eu4_rus_a_russian_heart", "music/ruamp_a_russian_heart.ogg", "dlc076_the_rus_awaken", "neutral", "european"),
    ("MusicPlayer_eu4_rus_following_the_volga", "music/ruamp_following_the_volga.ogg", "dlc076_the_rus_awaken", "peace", "european"),
    ("MusicPlayer_eu4_rus_iwans_dream", "music/ruamp_iwans_dream.ogg", "dlc076_the_rus_awaken", "neutral", "european"),
    ("MusicPlayer_eu4_kott_faith_restored", "music/Faith_Restored.ogg", "dlc081_kairis_soundtrack_3_ottoman_tunes", "peace", "middle_east"),
    ("MusicPlayer_eu4_kott_homebound", "music/Homebound.ogg", "dlc081_kairis_soundtrack_3_ottoman_tunes", "peace", "middle_east"),
    ("MusicPlayer_eu4_kott_peace_cannot_last", "music/Peace_Cannot_Last.ogg", "dlc081_kairis_soundtrack_3_ottoman_tunes", "neutral", "middle_east"),
    ("MusicPlayer_eu4_kott_sundered_hills", "music/Sundered_Hills.ogg", "dlc081_kairis_soundtrack_3_ottoman_tunes", "neutral", "middle_east"),
    ("MusicPlayer_eu4_kott_whispers_dark", "music/Whispers_in_the_Dark.ogg", "dlc081_kairis_soundtrack_3_ottoman_tunes", "neutral", "middle_east"),
    ("MusicPlayer_eu4_brit_alba", "music/Alba.ogg", "dlc089_rule_britannia_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_brit_battle_in_the_highlands", "music/A_Battle_in_the_Highlands.ogg", "dlc089_rule_britannia_music_pack", "war", "european"),
    ("MusicPlayer_eu4_brit_piper_lead_your_clansmen", "music/Piper_Lead_Your_Clansmen.ogg", "dlc089_rule_britannia_music_pack", "war", "european"),
    ("MusicPlayer_eu4_dharma_carnatic", "music/Carnatic.ogg", "dlc094_dharma_music", "neutral", "indian"),
    ("MusicPlayer_eu4_dharma_hindustani", "music/Hindustani.ogg", "dlc094_dharma_music", "neutral", "indian"),
    ("MusicPlayer_eu4_dharma_rajastani", "music/Rajastani.ogg", "dlc094_dharma_music", "neutral", "indian"),
    ("MusicPlayer_eu4_gc_birth_of_global_empire", "music/birth_of_a_global_empire.ogg", "dlc099_golden_century_music", "neutral", "european"),
    ("MusicPlayer_eu4_gc_conflict_in_the_caribbean", "music/conflict_in_the_caribbean.ogg", "dlc099_golden_century_music", "war", "european"),
    ("MusicPlayer_eu4_gc_march_on_granada", "music/march_on_granada.ogg", "dlc099_golden_century_music", "war", "european"),
    ("MusicPlayer_eu4_emp_empire_divided", "music/anempiredivided.ogg", "dlc105_emperor_music", "neutral", "european"),
    ("MusicPlayer_eu4_emp_birthplace_of_renaissance", "music/birthplaceofrenaissance.ogg", "dlc105_emperor_music", "neutral", "european"),
    ("MusicPlayer_eu4_emp_duality_of_faith", "music/dualityoffaith.ogg", "dlc105_emperor_music", "neutral", ""),
    ("MusicPlayer_eu4_na_american_soil", "music/american_soil.ogg", "dlc108_north_america_music", "neutral", "north_american"),
    ("MusicPlayer_eu4_na_cautious_preparation", "music/cautious_preparation.ogg", "dlc108_north_america_music", "neutral", ""),
    ("MusicPlayer_eu4_na_signs_of_victory", "music/signs_of_victory.ogg", "dlc108_north_america_music", "war", ""),
    ("MusicPlayer_eu4_sea_discoveries_revealed", "music/discoveries_revealed.ogg", "dlc109_south_east_asia_music", "discovery", "indian"),
    ("MusicPlayer_eu4_sea_undisclosed_tactics", "music/undisclosed_tactics.ogg", "dlc109_south_east_asia_music", "war", "indian"),
    ("MusicPlayer_eu4_sea_undiscovered_territory", "music/undiscovered_territory.ogg", "dlc109_south_east_asia_music", "discovery", ""),
    ("MusicPlayer_eu4_waf_new_destiny_awaits", "music/a_new_destiny_awaits.ogg", "dlc112_west_african_music_pack", "neutral", "african"),
    ("MusicPlayer_eu4_waf_into_the_wild", "music/into_the_wild.ogg", "dlc112_west_african_music_pack", "neutral", "african"),
    ("MusicPlayer_eu4_waf_strategy_reborn", "music/strategy_reborn.ogg", "dlc112_west_african_music_pack", "war", ""),
    ("MusicPlayer_eu4_eaf_encounters_in_the_sun", "music/encounters_in_the_sun_ea.ogg", "dlc113_east_african_music_pack", "neutral", "african"),
    ("MusicPlayer_eu4_eaf_neverending_dunes", "music/neverending_dunes.ogg", "dlc113_east_african_music_pack", "neutral", "african"),
    ("MusicPlayer_eu4_eaf_the_long_walk", "music/the_long_walk_ea.ogg", "dlc113_east_african_music_pack", "peace", ""),
    ("MusicPlayer_eu4_gds3_aarle", "music/aarle.ogg", "dlc114_guns_drums_and_steel_volume_3", "neutral", ""),
    ("MusicPlayer_eu4_gds3_after_the_rain", "music/after_the_rain.ogg", "dlc114_guns_drums_and_steel_volume_3", "peace", ""),
    ("MusicPlayer_eu4_gds3_darkness_falls", "music/darkness_falls.ogg", "dlc114_guns_drums_and_steel_volume_3", "war", ""),
    ("MusicPlayer_eu4_gds3_demons", "music/demons.ogg", "dlc114_guns_drums_and_steel_volume_3", "war", ""),
    ("MusicPlayer_eu4_gds3_kettil", "music/kettil.ogg", "dlc114_guns_drums_and_steel_volume_3", "neutral", ""),
    ("MusicPlayer_eu4_gds3_last_stand", "music/last_stand.ogg", "dlc114_guns_drums_and_steel_volume_3", "war", ""),
    ("MusicPlayer_eu4_gds3_legends_north", "music/legends_of_the_north.ogg", "dlc114_guns_drums_and_steel_volume_3", "neutral", "european"),
    ("MusicPlayer_eu4_gds3_over_seas", "music/over_seas.ogg", "dlc114_guns_drums_and_steel_volume_3", "discovery", ""),
    ("MusicPlayer_eu4_gds3_ravens", "music/ravens.ogg", "dlc114_guns_drums_and_steel_volume_3", "war", ""),
    ("MusicPlayer_eu4_gds3_the_conqueror", "music/the_conqueror.ogg", "dlc114_guns_drums_and_steel_volume_3", "war", ""),
    ("MusicPlayer_eu4_gds3_voices", "music/voices.ogg", "dlc114_guns_drums_and_steel_volume_3", "neutral", ""),
    ("MusicPlayer_eu4_gds3_whispering_forest", "music/whispering_forest.ogg", "dlc114_guns_drums_and_steel_volume_3", "peace", ""),
    ("MusicPlayer_eu4_scan_battle_of_scandinavia", "music/battle_of_scandinavia.ogg", "dlc117_scandinavian_music_pack", "war", "european"),
    ("MusicPlayer_eu4_scan_lands_of_midnight_sun", "music/lands_of_midnight_sun.ogg", "dlc117_scandinavian_music_pack", "peace", "european"),
    ("MusicPlayer_eu4_scan_united_we_stand", "music/united_we_stand.ogg", "dlc117_scandinavian_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_balt_crowned_in_tallin", "music/crowned_in_tallin.ogg", "dlc118_baltics_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_balt_knights_of_swords", "music/knights_of_swords.ogg", "dlc118_baltics_music_pack", "war", "european"),
    ("MusicPlayer_eu4_balt_rise_of_the_balts", "music/rise_of_the_balts.ogg", "dlc118_baltics_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_ott_conquest_of_constantinople", "music/conquest_of_constantinople.ogg", "dlc121_ottoman_music_pack", "war", "middle_east"),
    ("MusicPlayer_eu4_ott_redrawing_the_map", "music/redrawing_the_map.ogg", "dlc121_ottoman_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_ott_suleiman_the_magnificent", "music/suleiman_the_magnificent.ogg", "dlc121_ottoman_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_chi_path_of_the_dragon", "music/path_of_the_dragon.ogg", "dlc122_chinese_music_pack", "neutral", "east_asian"),
    ("MusicPlayer_eu4_chi_ports_of_china", "music/ports_of_china.ogg", "dlc122_chinese_music_pack", "peace", "east_asian"),
    ("MusicPlayer_eu4_chi_staff_of_the_emperor", "music/staff_of_the_emperor.ogg", "dlc122_chinese_music_pack", "neutral", "east_asian"),
    ("MusicPlayer_eu4_fr_a_new_king_arrives", "music/a_new_king_arrives.ogg", "dlc123_french_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_fr_castle_of_versailles", "music/castle_of_versailles.ogg", "dlc123_french_music_pack", "peace", "european"),
    ("MusicPlayer_eu4_fr_le_premier_jour", "music/le_premier_jour.ogg", "dlc123_french_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_ann_brief_history", "music/a_brief_history_of_everything.ogg", "dlc127_10th_anniversary", "neutral", ""),
    ("MusicPlayer_eu4_ann_world_to_explore", "music/a_world_to_explore.ogg", "dlc127_10th_anniversary", "discovery", ""),
    ("MusicPlayer_eu4_ann_all_roads_rome", "music/all_roads_lead_to_rome.ogg", "dlc127_10th_anniversary", "neutral", "european"),
    ("MusicPlayer_eu4_ann_back_motherland", "music/back_to_the_motherland.ogg", "dlc127_10th_anniversary", "neutral", ""),
    ("MusicPlayer_eu4_ann_clara_umbra", "music/clara_umbra.ogg", "dlc127_10th_anniversary", "neutral", ""),
    ("MusicPlayer_eu4_ann_dawn_empire", "music/dawn_of_an_empire.ogg", "dlc127_10th_anniversary", "neutral", ""),
    ("MusicPlayer_eu4_ann_in_taverns", "music/in_taverns_and_great_halls.ogg", "dlc127_10th_anniversary", "peace", ""),
    ("MusicPlayer_eu4_ann_into_beyond", "music/into_the_beyond.ogg", "dlc127_10th_anniversary", "discovery", ""),
    ("MusicPlayer_eu4_ann_one_world", "music/one_world.ogg", "dlc127_10th_anniversary", "neutral", ""),
    ("MusicPlayer_eu4_ann_conquistador", "music/the_conquistador.ogg", "dlc127_10th_anniversary", "war", "european"),
    ("MusicPlayer_eu4_egy_blue_nile", "music/blue_nile.ogg", "dlc130_egyptian_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_egy_fates_of_the_desert", "music/fates_of_the_desert.ogg", "dlc130_egyptian_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_egy_pharaohs_new_era", "music/pharaohs_of_a_new_era.ogg", "dlc130_egyptian_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_egy_ruler_pyramids", "music/ruler_of_the_pyramids.ogg", "dlc130_egyptian_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_per_battles_on_persian_borders", "music/battles_on_persian_borders.ogg", "dlc131_persian_music_pack", "war", "middle_east"),
    ("MusicPlayer_eu4_per_harbors_of_the_caspian_sea", "music/harbors_of_the_caspian_sea.ogg", "dlc131_persian_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_per_mount_damavand", "music/mount_damavand.ogg", "dlc131_persian_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_per_nader_shah", "music/nader_shah.ogg", "dlc131_persian_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_cau_battle_of_kakheti", "music/battle_of_kakheti.ogg", "dlc132_caucasian_music_pack", "war", "european"),
    ("MusicPlayer_eu4_cau_caucasus_mountains", "music/caucasus_mountains.ogg", "dlc132_caucasian_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_cau_days_of_glory", "music/days_of_glory.ogg", "dlc132_caucasian_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_cau_sight_black_sea", "music/sight_of_the_black_sea.ogg", "dlc132_caucasian_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_hre_continuation_diplomacy", "music/a_continuation_of_diplomacy.ogg", "dlc133_utopia_hre_music_pack", "peace", "european"),
    ("MusicPlayer_eu4_hre_autumn_aachen", "music/autumn_in_aachen.ogg", "dlc133_utopia_hre_music_pack", "peace", "european"),
    ("MusicPlayer_eu4_hre_charlemagne_legacy", "music/charlemange_s_legacy.ogg", "dlc133_utopia_hre_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_hre_election_habsburg", "music/election_of_a_habsburg.ogg", "dlc133_utopia_hre_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_hre_imperial_diet", "music/imperial_diet.ogg", "dlc133_utopia_hre_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_hre_life_shadow_kingdom", "music/life_under_the_shadow_kingdom.ogg", "dlc133_utopia_hre_music_pack", "neutral", ""),
    ("MusicPlayer_eu4_hre_ninety_five_theses", "music/ninety_five_theses.ogg", "dlc133_utopia_hre_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_hre_rise_loyal_subjects", "music/now_rise_my_loyal_subjects.ogg", "dlc133_utopia_hre_music_pack", "war", "european"),
    ("MusicPlayer_eu4_hre_order_diplomacy", "music/order_and_diplomacy.ogg", "dlc133_utopia_hre_music_pack", "peace", "european"),
    ("MusicPlayer_eu4_hre_prussian_ambitions", "music/prussian_ambitions.ogg", "dlc133_utopia_hre_music_pack", "war", "european"),
    ("MusicPlayer_eu4_ksp3_blood_old_gods", "music/blood_of_the_old_gods.ogg", "dlc134_kairis_soundtrack_part_3", "war", ""),
    ("MusicPlayer_eu4_ksp3_city_worlds_desire", "music/city_of_the_world_s_desire.ogg", "dlc134_kairis_soundtrack_part_3", "neutral", "middle_east"),
    ("MusicPlayer_eu4_ksp3_crossing_seas", "music/crossing_the_seas.ogg", "dlc134_kairis_soundtrack_part_3", "discovery", ""),
    ("MusicPlayer_eu4_ksp3_eastern_mists", "music/eastern_mists.ogg", "dlc134_kairis_soundtrack_part_3", "neutral", "east_asian"),
    ("MusicPlayer_eu4_ksp3_fine_day_sacrifice", "music/fine_day_for_sacrifice.ogg", "dlc134_kairis_soundtrack_part_3", "war", "south_american"),
    ("MusicPlayer_eu4_ksp3_gaelic_summers", "music/gaelic_summers.ogg", "dlc134_kairis_soundtrack_part_3", "peace", "european"),
    ("MusicPlayer_eu4_ksp3_hundred_years_war", "music/hundred_years_war.ogg", "dlc134_kairis_soundtrack_part_3", "war", "european"),
    ("MusicPlayer_eu4_ksp3_la_bataille_iberia", "music/la_bataille_de_iberia.ogg", "dlc134_kairis_soundtrack_part_3", "war", "european"),
    ("MusicPlayer_eu4_ksp3_march_empire", "music/march_for_the_empire.ogg", "dlc134_kairis_soundtrack_part_3", "war", ""),
    ("MusicPlayer_eu4_ksp3_old_families", "music/old_families.ogg", "dlc134_kairis_soundtrack_part_3", "neutral", ""),
    ("MusicPlayer_eu4_ksp3_prelude_march", "music/prelude_s_march.ogg", "dlc134_kairis_soundtrack_part_3", "neutral", ""),
    ("MusicPlayer_eu4_ksp3_shogunate_fall", "music/the_shogunate_will_fall.ogg", "dlc134_kairis_soundtrack_part_3", "war", "east_asian"),
    ("MusicPlayer_eu4_ksp3_siege_of_vienna", "music/the_siege_of_vienna.ogg", "dlc134_kairis_soundtrack_part_3", "war", "european"),
    ("MusicPlayer_eu4_natam_aztec_theme", "music/aztec_theme.ogg", "dlc138_native_america_music_pack", "neutral", "south_american"),
    ("MusicPlayer_eu4_natam_inca_theme", "music/inca_theme.ogg", "dlc138_native_america_music_pack", "neutral", "south_american"),
    ("MusicPlayer_eu4_natam_mayan_theme", "music/mayan_theme.ogg", "dlc138_native_america_music_pack", "neutral", "south_american"),
    ("MusicPlayer_eu4_cas_hordes_centralasian", "music/hordes_centralasian.ogg", "dlc139_central_asia_music_pack", "war", "middle_east"),
    ("MusicPlayer_eu4_cas_mughal_indian_persian", "music/mughal_indian_persian.ogg", "dlc139_central_asia_music_pack", "neutral", "indian"),
    ("MusicPlayer_eu4_cas_oman_arabic", "music/oman_arabic.ogg", "dlc139_central_asia_music_pack", "neutral", "middle_east"),
    ("MusicPlayer_eu4_ce_austria_theme", "music/austria_theme.ogg", "dlc140_central_europe_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_ce_hungary_theme", "music/hungary_theme.ogg", "dlc140_central_europe_music_pack", "neutral", "european"),
    ("MusicPlayer_eu4_ce_netherlands_theme", "music/netherlands_theme.ogg", "dlc140_central_europe_music_pack", "neutral", "european"),
]

# --- STEAM PATHS -------------------------------------------
def steam_libraries():
    libs = []
    env = os.environ.get("EU4SND_STEAM_LIBRARIES")
    if env:
        libs += [p for p in env.split(os.pathsep) if p]
    home = os.path.expanduser("~")
    roots = [home + "/.steam/steam", home + "/.steam/root", home + "/.local/share/Steam",
             home + "/.var/app/com.valvesoftware.Steam/.local/share/Steam",
             home + "/snap/steam/common/.local/share/Steam"]
    for root in roots:
        if os.path.isdir(os.path.join(root, "steamapps")):
            libs.append(root)
        vdf = os.path.join(root, "steamapps", "libraryfolders.vdf")
        if os.path.isfile(vdf):
            with open(vdf, encoding="utf-8", errors="replace") as f:
                libs += [m.group(1).replace("\\\\", "\\") for m in re.finditer(r'"path"\s+"([^"]+)"', f.read())]
    seen, out = set(), []
    for lib in libs:
        real = os.path.realpath(lib)
        if real not in seen and os.path.isdir(real):
            seen.add(real); out.append(real)
    return out

def find_ci(folder, name):
    """Case-insensitive lookup of one path component (Paradox data is not consistently cased)."""
    try:
        for entry in os.listdir(folder):
            if entry.lower() == name.lower():
                return os.path.join(folder, entry)
    except OSError:
        pass
    return None

def find_mod(libs):
    for lib in libs:
        base = os.path.join(lib, "steamapps", "workshop", "content", "3450310")
        if not os.path.isdir(base): continue
        for d in sorted(os.listdir(base)):
            meta = os.path.join(base, d, ".metadata", "metadata.json")
            try:
                with open(meta, encoding="utf-8", errors="replace") as f:
                    if '"eu4_soundtrack"' in f.read():
                        return os.path.join(base, d)
            except OSError:
                pass
    return None

def find_eu4(libs):
    for lib in libs:
        p = os.path.join(lib, "steamapps", "common", "Europa Universalis IV")
        if find_ci(p, "music"):
            return p
    return None

def find_eu5_bank(mod_dir, libs):
    rel = ["steamapps", "common", "Europa Universalis V", "game", "loading_screen", "sound", "banks", "windows", "sb_music_logic.bnk"]
    # Workshop mod lives in <library>/steamapps/workshop/content/3450310/<id> - EU5 is usually in that library
    for lib in [os.path.realpath(os.path.join(mod_dir, *[".."] * 5))] + libs:
        p = os.path.join(lib, *rel)
        if os.path.isfile(p):
            return p
    return None

def find_ogg(src, dlc, eu4):
    if not dlc:
        music = find_ci(eu4, "music")
        p = music and find_ci(music, src)
        return ("file", p, None) if p else None
    dlc_root = find_ci(eu4, "dlc")
    dlc_dir = dlc_root and find_ci(dlc_root, dlc)
    if not dlc_dir: return None
    for z in sorted(os.listdir(dlc_dir)):
        if not z.lower().endswith(".zip"): continue
        try:
            with zipfile.ZipFile(os.path.join(dlc_dir, z)) as zf:
                for entry in zf.namelist():
                    if entry.lower().endswith(src.lower()):
                        return ("zip", os.path.join(dlc_dir, z), entry)
        except (OSError, zipfile.BadZipFile):
            pass
    return None

# --- OGG -> WEM (port of OggToWem in EU4_Soundtrack_Setup.ps1) ---
class BitReader:
    def __init__(self, data):
        self.v = int.from_bytes(data, "little"); self.n = len(data) * 8; self.pos = 0
    def read(self, n):
        if self.pos + n > self.n: raise ValueError("unexpected end of packet")
        r = (self.v >> self.pos) & ((1 << n) - 1); self.pos += n
        return r

class BitWriter:
    def __init__(self): self.v = 0; self.n = 0
    def write(self, x, n):
        self.v |= (x & ((1 << n) - 1)) << self.n; self.n += n
    def bytes(self): return self.v.to_bytes((self.n + 7) // 8, "little")

def ilog(x): return x.bit_length()

def _lookup_values(dims, entries):
    if dims == 0: raise ValueError("bad codebook dimensions")
    q = 1
    while q ** dims < entries: q += 1
    return q

def canonical_codebook(br):
    """Std Vorbis codebook -> canonical bytes for the packed codebook lookup."""
    bw = BitWriter()
    sync = br.read(24)
    if sync != 0x564342: raise ValueError("Bad codebook sync")
    dims = br.read(16); entries = br.read(24)
    bw.write(sync, 24); bw.write(dims, 16); bw.write(entries, 24)
    ordered = br.read(1); bw.write(ordered, 1)
    if ordered:
        bw.write(br.read(5), 5); ce = 0
        while ce < entries:
            n = ilog(entries - ce); c = br.read(n); bw.write(c, n); ce += c
    else:
        sparse = br.read(1); bw.write(sparse, 1)
        for _ in range(entries):
            present = True
            if sparse:
                p = br.read(1); bw.write(p, 1); present = p == 1
            if present: bw.write(br.read(5), 5)
    lt = br.read(4); bw.write(lt, 4)
    if lt == 1:
        bw.write(br.read(32), 32); bw.write(br.read(32), 32)
        vl = br.read(4); bw.write(vl, 4); bw.write(br.read(1), 1)
        for _ in range(_lookup_values(dims, entries)): bw.write(br.read(vl + 1), vl + 1)
    return bw.bytes()

def canonical_packed(br):
    """Packed (Wwise inline) codebook -> canonical bytes."""
    bw = BitWriter()
    dims = br.read(4); entries = br.read(14)
    bw.write(0x564342, 24); bw.write(dims, 16); bw.write(entries, 24)
    ordered = br.read(1); bw.write(ordered, 1)
    if ordered:
        bw.write(br.read(5), 5); ce = 0
        while ce < entries:
            n = ilog(entries - ce); c = br.read(n); bw.write(c, n); ce += c
    else:
        cwll = br.read(3); sparse = br.read(1); bw.write(sparse, 1)
        for _ in range(entries):
            present = True
            if sparse:
                p = br.read(1); bw.write(p, 1); present = p == 1
            if present: bw.write(br.read(cwll), 5)
    lt = br.read(1); bw.write(lt, 4)
    if lt == 1:
        bw.write(br.read(32), 32); bw.write(br.read(32), 32)
        vl = br.read(4); bw.write(vl, 4); bw.write(br.read(1), 1)
        for _ in range(_lookup_values(dims, entries)): bw.write(br.read(vl + 1), vl + 1)
    return bw.bytes()

_lookup = None
def codebook_lookup(pcb_path):
    global _lookup
    if _lookup is None:
        with open(pcb_path, "rb") as f: pcb = f.read()
        table = struct.unpack_from("<i", pcb, len(pcb) - 4)[0]
        count = (len(pcb) - 4 - table) // 4
        offsets = [struct.unpack_from("<i", pcb, table + 4 * i)[0] for i in range(count)] + [table]
        _lookup = {}
        for i in range(count):
            try:
                _lookup.setdefault(canonical_packed(BitReader(pcb[offsets[i]:offsets[i + 1]])), i)
            except Exception:
                pass
    return _lookup

def convert_setup(setup, lookup, channels):
    """Std Vorbis setup -> Wwise setup with external codebook IDs; also returns mode info."""
    br = BitReader(setup); bw = BitWriter()
    br.read(56)                                   # '05 vorbis'
    cbc = br.read(8); bw.write(cbc, 8)
    for i in range(cbc + 1):
        cb = lookup.get(canonical_codebook(br))
        if cb is None: raise ValueError(f"Codebook {i} not in packed_codebooks")
        bw.write(cb, 10)
    tc = br.read(6)                               # time domain: Wwise omits it
    for _ in range(tc + 1): br.read(16)
    fc = br.read(6); bw.write(fc, 6)              # floors
    for _ in range(fc + 1):
        br.read(16)                               # floor_type: omitted (always 1)
        parts = br.read(5); bw.write(parts, 5)
        part_class = []
        for _ in range(parts):
            c = br.read(4); bw.write(c, 4); part_class.append(c)
        class_dims = []
        for _ in range(max(part_class, default=-1) + 1):
            d = br.read(3); bw.write(d, 3); class_dims.append(d + 1)
            subs = br.read(2); bw.write(subs, 2)
            if subs: bw.write(br.read(8), 8)
            for _ in range(1 << subs): bw.write(br.read(8), 8)
        bw.write(br.read(2), 2)                   # multiplier
        rangebits = br.read(4); bw.write(rangebits, 4)
        for c in part_class:
            for _ in range(class_dims[c]): bw.write(br.read(rangebits), rangebits)
    rc = br.read(6); bw.write(rc, 6)              # residues
    for _ in range(rc + 1):
        bw.write(br.read(16), 2)                  # residue_type: 16 -> 2 bits
        bw.write(br.read(24), 24); bw.write(br.read(24), 24); bw.write(br.read(24), 24)
        cls = br.read(6); bw.write(cls, 6); cls += 1
        bw.write(br.read(8), 8)
        cascade = []
        for _ in range(cls):
            lb = br.read(3); bw.write(lb, 3)
            bit = br.read(1); bw.write(bit, 1)
            hb = 0
            if bit: hb = br.read(5); bw.write(hb, 5)
            cascade.append(lb | (hb << 3))
        for c in cascade:
            for k in range(8):
                if c & (1 << k): bw.write(br.read(8), 8)
    mc = br.read(6); bw.write(mc, 6)              # mappings
    for _ in range(mc + 1):
        br.read(16)                               # mapping_type: omitted
        sf = br.read(1); bw.write(sf, 1); submaps = 1
        if sf:
            sm = br.read(4); bw.write(sm, 4); submaps = sm + 1
        sq = br.read(1); bw.write(sq, 1)
        if sq:
            cs = br.read(8); bw.write(cs, 8)
            cbits = ilog(channels - 1)
            for _ in range(cs + 1):
                bw.write(br.read(cbits), cbits); bw.write(br.read(cbits), cbits)
        br.read(2); bw.write(0, 2)                # reserved
        if submaps > 1:
            for _ in range(channels): bw.write(br.read(4), 4)
        for _ in range(submaps):
            bw.write(br.read(8), 8); bw.write(br.read(8), 8); bw.write(br.read(8), 8)
    modc = br.read(6); bw.write(modc, 6)          # modes
    blockflags = []
    for _ in range(modc + 1):
        bf = br.read(1); bw.write(bf, 1); blockflags.append(bf != 0)
        br.read(16); br.read(16)                  # windowtype, transformtype: omitted
        bw.write(br.read(8), 8)
    bw.write(1, 1)                                # framing bit
    return bw.bytes(), ilog(modc), blockflags

def modified_packet(pkt, mode_bits, blockflags):
    """Std Vorbis audio packet -> Wwise: drop packet type bit and, for long blocks, the window bits."""
    if not pkt: return pkt
    nbits = len(pkt) * 8
    v = int.from_bytes(pkt, "little")
    pos = 1
    mode = 0
    if mode_bits:
        if pos + mode_bits > nbits: raise ValueError("unexpected end of packet")
        mode = (v >> pos) & ((1 << mode_bits) - 1); pos += mode_bits
    if mode < len(blockflags) and blockflags[mode] and nbits - pos >= 2:
        pos += 2
    rest = max(nbits - pos, 0)
    out = mode | ((v >> pos) << mode_bits)
    return out.to_bytes((mode_bits + rest + 7) // 8, "little")

def parse_ogg(d):
    packets, granule, buf, pos = [], 0, bytearray(), 0
    while pos <= len(d) - 27:
        if d[pos:pos + 4] != b"OggS": break
        g = struct.unpack_from("<q", d, pos + 6)[0]
        if g > 0: granule = g
        ns = d[pos + 26]; dp = pos + 27 + ns
        for sz in d[pos + 27:pos + 27 + ns]:
            buf += d[dp:dp + sz]; dp += sz
            if sz < 255:
                packets.append(bytes(buf)); buf = bytearray()
        pos = dp
    if buf: packets.append(bytes(buf))
    return packets, granule

def ogg_to_wem(ogg, pcb_path):
    packets, granule = parse_ogg(ogg)
    if len(packets) < 4: raise ValueError(f"Too few packets: {len(packets)}")
    ident = packets[0]
    ch = ident[11]; sr = struct.unpack_from("<i", ident, 12)[0]; bs = ident[28]
    bs0, bs1 = bs & 0xF, (bs >> 4) & 0xF
    setup, mode_bits, blockflags = convert_setup(packets[2], codebook_lookup(pcb_path), ch)
    audio = [modified_packet(p, mode_bits, blockflags) for p in packets[3:]]
    mx = max((len(p) for p in audio), default=0)
    seek, apos = [], 0
    for p in audio:
        if not seek or apos - seek[-1] >= 2048: seek.append(apos)
        apos += 2 + len(p)
    seek_table = b"".join(struct.pack("<I", s & 0xFFFFFFFF) for s in seek)
    audio_start = len(seek_table) + 2 + len(setup)
    data = bytearray(seek_table) + struct.pack("<H", len(setup) & 0xFFFF) + setup
    for p in audio: data += struct.pack("<H", len(p) & 0xFFFF) + p
    u32 = lambda x: struct.pack("<I", x & 0xFFFFFFFF)
    u16 = lambda x: struct.pack("<H", x & 0xFFFF)
    extra = (bytes([0, 0, 2, 0x31, 0, 0]) + u32(granule) + u32(audio_start) + u32(len(data)) + u16(0) + u16(0)
             + u32(len(seek_table)) + u32(audio_start) + u16(mx) + u16(0)
             + u32((1 << bs1) * ch * 2) + u32((1 << bs1) * ch * 4) + u32(0) + bytes([bs0, bs1]))
    return (b"RIFF" + u32(4 + 8 + 66 + 8 + 16 + 8 + len(data)) + b"WAVEfmt " + u32(66) + u16(0xFFFF) + u16(ch)
            + u32(sr) + u32(sr * ch * 2) + u16(0) + u16(0) + u16(48) + extra
            + b"hash" + u32(16) + bytes(16) + b"data" + u32(len(data)) + bytes(data))

def convert_job(job):
    name, (kind, path, entry), wem_path, pcb_path, ffmpeg = job
    try:
        if kind == "file":
            with open(path, "rb") as f: src = f.read()
        else:
            with zipfile.ZipFile(path) as zf: src = zf.read(entry)
        # ffmpeg's libvorbis at q6 writes the same setup header as aoTuV oggenc2 -q 6 (used on Windows)
        r = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", "pipe:0", "-ar", "48000", "-ac", "2",
                            "-c:a", "libvorbis", "-q:a", "6", "-f", "ogg", "pipe:1"], input=src, capture_output=True)
        if r.returncode != 0 or not r.stdout:
            return name, "ffmpeg failed: " + r.stderr.decode(errors="replace").strip()[-300:]
        wem = ogg_to_wem(r.stdout, pcb_path)
        # Write to .part first: an interrupted run must not leave a truncated .wem that counts as done
        with open(wem_path + ".part", "wb") as f: f.write(wem)
        os.replace(wem_path + ".part", wem_path)
        return name, None
    except Exception as e:
        try: os.remove(wem_path + ".part")
        except OSError: pass
        return name, f"WEM failed: {type(e).__name__}: {e}"

# --- SOUND BANKS (port of BankBuilder in EU4_Soundtrack_Setup.ps1, mirrors build_mod.py) ---
def fnv(s):
    h = 2166136261
    for c in s.lower().encode("ascii", errors="replace"):
        h = (h * 16777619) & 0xFFFFFFFF
        h ^= c
    return h

def is_valid_wem(path):
    """RIFF size must match the file length (truncated WEM plays as silence); 0xFFFF = Vorbis WEM from this setup."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f: h = f.read(22)
        return (len(h) == 22 and h[:4] == b"RIFF" and h[8:12] == b"WAVE"
                and struct.unpack_from("<I", h, 4)[0] + 8 == size and h[20:22] == b"\xff\xff")
    except OSError:
        return False

def read_chunks(b):
    out, pos = [], 0
    while pos + 8 <= len(b):
        tag = b[pos:pos + 4]; sz = struct.unpack_from("<I", b, pos + 4)[0]
        if pos + 8 + sz > len(b): raise ValueError(f"truncated {tag.decode(errors='replace')} chunk")
        out.append((tag, b[pos + 8:pos + 8 + sz])); pos += 8 + sz
    return out

def write_if_changed(path, data):
    try:
        with open(path, "rb") as f:
            if f.read() == data: return False
    except OSError:
        pass
    with open(path + ".part", "wb") as f: f.write(data)
    os.replace(path + ".part", path)
    return True

def hirc(obj_type, obj_id, content):
    return struct.pack("<BII", obj_type, 4 + len(content), obj_id) + content

PL_ITEM = struct.Struct("<IIIiHHHIHBB")   # AkMusicRanSeqPlaylistItem, pre-order

def subtree_end(items, k):
    pending = 1
    while pending:
        if k >= len(items): return -1
        pending += items[k][2] - 1; k += 1
    return k

def insert_leaves(content, container_id, segs, join_pool):
    """Mirrors build_mod.insert_playlist_leaves / BankBuilder.InsertLeaves."""
    parsed = None
    for off in range(len(content) - 4 - PL_ITEM.size, -1, -1):
        n = struct.unpack_from("<I", content, off)[0]
        if n == 0 or off + 4 + n * PL_ITEM.size != len(content): continue
        items = [list(PL_ITEM.unpack_from(content, off + 4 + k * PL_ITEM.size)) for k in range(n)]
        if subtree_end(items, 0) == n:
            parsed = off, items; break
    if parsed is None: return None
    off, items = parsed
    n = len(segs)
    leaves = [[s, (s ^ 0xC0FFEE00 ^ i) & 0xFFFFFFFF, 0, -1, 1, 0, 0, 50000, 0, 0, 0] for i, s in enumerate(segs)]
    group = [0, fnv(f"eu4_soundtrack_group_{container_id}"), n, 3, 1, 0, 0, 50000, min(n - 1, n // 2), 1, 1]
    first = items[1] if len(items) > 1 else None
    pool = next((k for k, it in enumerate(items) if it[2] >= 2 and it[3] in (2, 3)), None)
    if join_pool and first and first[2] > 0 and first[3] in (2, 3) and subtree_end(items, 1) == 2 + first[2]:
        # WAR/PEACE: join the flat random pool
        end = 2 + first[2]; first[2] += n; items[end:end] = leaves
    elif pool is not None:
        # Culture: "EU5 soloist piece" or "EU4 track" at the start of the cycle
        m = items[pool][2]
        choice = [0, fnv(f"eu4_soundtrack_choice_{container_id}"), 2, 3, 1, 0, 0, items[pool][7], 0, 1, 0]
        items[pool][7] = 50000
        group[7] = 50000 * min(n, m) // m
        end = subtree_end(items, pool)
        items[pool:end] = [choice] + items[pool:end] + [group] + leaves
    else:
        items[0][2] += 1; items += [group] + leaves
    return content[:off] + struct.pack("<I", len(items)) + b"".join(PL_ITEM.pack(*it) for it in items)

MUSIC_BANK_ID, MEDIA_BANK_ID, BANK_VERSION = 0x3e708754, 0x990e0412, 150
MUSIC_GUID = bytes.fromhex("ae6da5b859d619f42aa763976cc0e0d1")
MEDIA_GUID = bytes.fromhex("b2a234ccd3aa95e28ce3432436c3c6ec")
WAR_PL, PEACE_PL = 0x290f1591, 0x3de374bf
CULTURE_PL = {"european": 0x172E4EBA, "east_asian": 0x2AE87B0D, "african": 0x2D1FE56A, "middle_east": 0x177DFABD,
              "indian": 0x014173A7, "north_american": 0x0847DCF1, "south_american": 0x360B858E}
TRACK_TPL = bytes.fromhex("00010000000100040001555f6625c2150000000100000000000000555f6625"
                          "00000000000000000000000000000000000000000000000000000000"
                          "1357ba37a0d8bc4001000000000000000000000000000000"
                          "ec74d200000000000000000000000100000000000000000064000000")
SEGMENT_TPL = bytes.fromhex("00000000000000000024e85a3b0000000000000000000001000000000000000001000000"
                            "ca670435"
                            "0000000000408f4000000000000000000000f0420404000000000045c85fb343d30741"
                            "0200000012df980200000000000000000048d6bb5b"
                            "45c85fb343d30741"
                            "00")

def music_track(obj_id, wem, prefetch, dur_ms, segment):
    t = bytearray(TRACK_TPL)
    struct.pack_into("<I", t, 10, wem); struct.pack_into("<I", t, 14, prefetch); struct.pack_into("<I", t, 27, wem)
    struct.pack_into("<ddd", t, 35, 0.0, 0.0, 0.0); struct.pack_into("<d", t, 59, dur_ms)
    struct.pack_into("<I", t, 83, segment)
    return hirc(11, obj_id, bytes(t))

def music_segment(obj_id, track, dur_ms, parent):
    t = bytearray(SEGMENT_TPL)
    if parent: struct.pack_into("<I", t, 9, parent)
    struct.pack_into("<I", t, 36, track); struct.pack_into("<d", t, 67, dur_ms); struct.pack_into("<d", t, 96, dur_ms)
    return hirc(10, obj_id, bytes(t))

def wem_duration(path):
    with open(path, "rb") as f: head = f.read(65536)
    pos = 12
    while pos < len(head) - 8:
        sz = struct.unpack_from("<I", head, pos + 4)[0]
        if head[pos:pos + 4] == b"fmt ":
            return struct.unpack_from("<I", head, pos + 8 + 24)[0] / max(struct.unpack_from("<I", head, pos + 8 + 4)[0], 1)
        pos += 8 + sz
    return 0.0

def build_music(eu5_bank, media_dir, out_path):
    with open(eu5_bank, "rb") as f: eu5 = read_chunks(f.read())
    chunks = dict(eu5)
    bkhd, hirc_chunk = chunks.get(b"BKHD"), chunks.get(b"HIRC")
    if bkhd is None or hirc_chunk is None or len(bkhd) < 24: raise ValueError("unexpected EU5 bank layout")
    if struct.unpack_from("<I", bkhd, 0)[0] != BANK_VERSION:
        raise ValueError(f"EU5 sound bank version {struct.unpack_from('<I', bkhd, 0)[0]} is not supported, mod update required")
    mod_objs, ins, present = [], {}, 0
    for ev, _src, _dlc, mood, culture in TRACKS:
        wem = fnv(ev + "_wem"); path = os.path.join(media_dir, f"{wem}.wem")
        if not is_valid_wem(path): continue
        present += 1
        dur_ms = max(1.0, wem_duration(path)) * 1000.0
        pre = min(os.path.getsize(path), 8192)
        tid, sid, aid, uid = fnv(ev + "_track"), fnv(ev + "_seg"), fnv(ev + "_action"), fnv(ev + "_setup")
        mod_objs += [music_track(tid, wem, pre, dur_ms, sid), music_segment(sid, tid, dur_ms, 0),
                     hirc(3, uid, b"\x03\x21" + struct.pack("<I", 0xdccd55a7) + b"\x00\x00\x00"),
                     hirc(3, aid, b"\x03\x04" + struct.pack("<I", sid) + bytes.fromhex("00000004a1c7709300000000")),
                     hirc(4, fnv(ev), struct.pack("<BII", 2, uid, aid))]
        dyn = [("", WAR_PL)] if mood == "war" else [("", PEACE_PL)] if mood == "peace" else [("_war", WAR_PL), ("_pce", PEACE_PL)]
        if culture in CULTURE_PL: dyn.append(("_cult", CULTURE_PL[culture]))
        for suffix, pl in dyn:
            ds, dt = fnv(ev + suffix + "_dynseg"), fnv(ev + suffix + "_dyn_track")
            mod_objs += [music_track(dt, wem, pre, dur_ms, ds), music_segment(ds, dt, dur_ms, pl)]
            ins.setdefault(pl, []).append(ds)
    objs, patched = [], set()
    count = struct.unpack_from("<I", hirc_chunk, 0)[0]; p = 4
    for _ in range(count):
        t = hirc_chunk[p]; size = struct.unpack_from("<I", hirc_chunk, p + 1)[0]
        raw = hirc_chunk[p:p + 5 + size]; oid = struct.unpack_from("<I", raw, 5)[0]; p += 5 + size
        if t == 13 and oid in ins:
            nc = insert_leaves(raw[9:], oid, ins[oid], oid in (WAR_PL, PEACE_PL))
            if nc is not None:
                objs.append(hirc(13, oid, nc)); patched.add(oid); continue
        objs.append(raw)
    for oid in ins:
        if oid not in patched: raise ValueError(f"EU5 playlist {oid:08x} not found, mod update required")
    objs += mod_objs
    new_bkhd = bkhd[:4] + struct.pack("<I", MUSIC_BANK_ID) + bkhd[8:24] + MUSIC_GUID
    new_hirc = struct.pack("<I", len(objs)) + b"".join(objs)
    bank = b"".join(tag + struct.pack("<I", len(d)) + d for tag, d in
                    ((tag, new_bkhd if tag == b"BKHD" else new_hirc if tag == b"HIRC" else d) for tag, d in eu5))
    return present, len(TRACKS) - present, write_if_changed(out_path, bank)

def build_media(media_dir, out_path):
    didx, data, n = bytearray(), bytearray(), 0
    for wem in sorted({fnv(t[0] + "_wem") for t in TRACKS}):
        path = os.path.join(media_dir, f"{wem}.wem")
        if not is_valid_wem(path): continue
        with open(path, "rb") as f: pre = f.read(8192)
        data += bytes((16 - len(data) % 16) % 16)
        didx += struct.pack("<III", wem, len(data), len(pre)); data += pre; n += 1
    bkhd = struct.pack("<IIIIII", BANK_VERSION, MEDIA_BANK_ID, 0x17705D3E, 0x10, 0x387C, 0) + MEDIA_GUID
    bank = b"BKHD" + struct.pack("<I", len(bkhd)) + bkhd
    if n: bank += b"DIDX" + struct.pack("<I", len(didx)) + didx + b"DATA" + struct.pack("<I", len(data)) + data
    return n, write_if_changed(out_path, bank)

# --- MAIN --------------------------------------------------
def main():
    print("\n  EU4 Soundtrack for EU5\n  ---------------------\n", flush=True)
    libs = steam_libraries()
    mod_dir = find_mod(libs)
    if not mod_dir:
        fail("EU4 Soundtrack mod not found in Steam Workshop. Subscribe to the mod first.")
    banks_dir = os.path.join(mod_dir, "loading_screen", "sound", "banks", "windows")
    media_dir = os.path.join(banks_dir, "Media")
    os.makedirs(media_dir, exist_ok=True)

    # 1. Check & convert missing tracks
    missing = [t for t in TRACKS if not is_valid_wem(os.path.join(media_dir, f"{fnv(t[0] + '_wem')}.wem"))]
    if not missing:
        ok(f"All {len(TRACKS)} tracks ready!")
    else:
        status("Locating EU4...")
        eu4 = find_eu4(libs)
        if not eu4:
            fail("EU4 not found. Make sure Europa Universalis IV is installed on this Steam account.")
        ok(f"EU4: {eu4}")
        work = []
        for ev, src, dlc, _mood, _culture in missing:
            found = find_ogg(src, dlc, eu4)
            if found:
                work.append((ev, found, os.path.join(media_dir, f"{fnv(ev + '_wem')}.wem")))
        skipped = len(missing) - len(work)
        if not work:
            ok(f"{len(TRACKS) - len(missing)} tracks ready, {skipped} need DLCs that are not installed")
        else:
            # Tools are only needed when there is something to convert
            status("Checking tools...")
            pcb = os.path.join(CACHE, "packed_codebooks.bin")
            if not (os.path.isfile(pcb) and os.path.getsize(pcb) == 74387):
                status("Downloading packed_codebooks.bin...")
                try:
                    urllib.request.urlretrieve("https://github.com/hcs64/ww2ogg/raw/master/packed_codebooks_aoTuV_603.bin", pcb)
                except Exception as e:
                    warn(f"download error: {e}")
            if not (os.path.isfile(pcb) and os.path.getsize(pcb) == 74387):
                fail("packed_codebooks.bin download failed")
            ok("Conversion tools ready")
            ffmpeg = shutil.which("ffmpeg")
            if not ffmpeg:
                fail("FFmpeg not found. Install it with your package manager (e.g. sudo apt install ffmpeg / sudo pacman -S ffmpeg), then restart Steam.")
            enc = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
            if " libvorbis " not in enc:
                fail("FFmpeg was built without libvorbis. Install an FFmpeg build with libvorbis.")
            ok("FFmpeg found")

            jobs = max(2, min(8, (os.cpu_count() or 2) // 2))
            status(f"Converting {len(work)} track(s) ({jobs} parallel jobs)...")
            done = failed = 0
            with cf.ProcessPoolExecutor(max_workers=jobs, mp_context=multiprocessing.get_context("fork")) as pool:
                futures = [pool.submit(convert_job, (ev, found, wem, pcb, ffmpeg)) for ev, found, wem in work]
                progress(0, f"Converting {len(work)} EU4 tracks...")
                for fut in cf.as_completed(futures):
                    name, err = fut.result()
                    if err:
                        failed += 1; warn(f"Failed: {name}"); say("  ->", err)
                    else:
                        done += 1; say("  [+]", name)
                    progress(100 * (done + failed) / len(work), f"Converting EU4 tracks: {done + failed}/{len(work)}")
            close_progress()
            ok(f"Done: {done}  Failed: {failed}  Skipped (no DLC): {skipped}")

    # 2. Sync sound banks with the WEM files actually present
    status("Updating sound banks...")
    try:
        n, changed = build_media(media_dir, os.path.join(banks_dir, "eu4_soundtrack_media.bnk"))
    except Exception as e:
        fail(f"media.bnk build failed: {e}")
    ok(f"media.bnk: {n} tracks ({'updated' if changed else 'unchanged'})")
    eu5_bank = find_eu5_bank(mod_dir, libs)
    if not eu5_bank:
        fail("EU5 not found (sb_music_logic.bnk). Make sure Europa Universalis V is installed on this Steam account.")
    try:
        present, absent, changed = build_music(eu5_bank, media_dir, os.path.join(banks_dir, "eu4_soundtrack_music.bnk"))
    except Exception as e:
        fail(f"music.bnk build failed: {e}")
    ok(f"music.bnk: {present} tracks in playlists, {absent} not installed left out ({'updated' if changed else 'unchanged'})")
    print("", flush=True)
    status("Setup complete. Game starting...")

main()
PYEOF
status=$?
[ $status -eq 0 ] || exit $status

# Start the game (%command% from the Steam launch option)
[ $# -gt 0 ] && exec "$@"
exit 0
