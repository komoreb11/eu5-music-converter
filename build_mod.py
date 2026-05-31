#!/usr/bin/env python3
"""
EU4 Soundtrack for EU5 - Build Script
Converts EU4 OGG tracks to WEM and assembles Wwise banks.

Requirements: Python 3.8+, ffmpeg in PATH, WwiseConsole.exe

Usage: python build_mod.py
"""

import os, sys, struct, subprocess, zipfile, shutil, hashlib, binascii, json
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Optional

# ─── PATHS ──────────────────────────────────────────────────────────────────

def _find_steam():
    for p in [
        Path("/mnt/e/SteamLibrary/steamapps/common"),
        Path("/mnt/d/SteamLibrary/steamapps/common"),
        Path("/mnt/c/Program Files (x86)/Steam/steamapps/common"),
        Path("E:/SteamLibrary/steamapps/common"),
        Path("D:/SteamLibrary/steamapps/common"),
        Path("C:/Program Files (x86)/Steam/steamapps/common"),
    ]:
        if (p / "Europa Universalis IV").exists():
            return p
    return Path("E:/SteamLibrary/steamapps/common")

STEAM_PATH = _find_steam()
EU4_PATH   = STEAM_PATH / "Europa Universalis IV"
EU5_PATH   = STEAM_PATH / "Europa Universalis V"
MOD_PATH   = Path(__file__).parent
BANKS_PATH = MOD_PATH / "loading_screen/sound/banks/windows"
MEDIA_PATH = BANKS_PATH / "Media"

WWISE_CONSOLE  = Path("C:/Audiokinetic/Wwise_2026.1.1.9196/Authoring/x64/Release/bin/WwiseConsole.exe")
WWISE_PROJ_DIR = Path("C:/sound2wem/eu4mod")
WWISE_TMP_DIR  = Path("C:/sound2wem/tmpconv")
PREFETCH_SIZE  = 8192

# ─── TRACK DEFINITIONS ──────────────────────────────────────────────────────

@dataclass
class EU4Track:
    event_name:  str
    source_file: str
    dlc:         Optional[str]
    mood:        str            # war / peace / neutral / discovery
    region:      Optional[str]  # for culture playlist routing

TRACKS = [
    # Base game
    EU4Track("MusicPlayer_eu4_maintheme","maintheme.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_dehominisdignitate","dehominisdignitate.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_kingscourt","kingscourt.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_kingsinthenorth","kingsinthenorth.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_machiavelli","machiavelli.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_nighttime","nighttime.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_thestonemasons","thestonemasons.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_moodevent_thesnowiscoming","moodevent_thesnowiscoming.ogg",None,"neutral",None),
    EU4Track("MusicPlayer_eu4_amongthepoor","amongthepoor.ogg",None,"peace",None),
    EU4Track("MusicPlayer_eu4_commerceinthepeninsula","commerceinthepeninsula.ogg",None,"peace",None),
    EU4Track("MusicPlayer_eu4_eire","eire.ogg",None,"peace","british_isles"),
    EU4Track("MusicPlayer_eu4_inthestreets","inthestreets.ogg",None,"peace",None),
    EU4Track("MusicPlayer_eu4_mood_landinsight","mood_landinsight.ogg",None,"peace",None),
    EU4Track("MusicPlayer_eu4_openseas","openseas.ogg",None,"peace",None),
    EU4Track("MusicPlayer_eu4_thesoundofsummer","thesoundofsummer.ogg",None,"peace",None),
    EU4Track("MusicPlayer_eu4_battleoflepanto","battleoflepanto.ogg",None,"war",None),
    EU4Track("MusicPlayer_eu4_event_war_battleofbreitenfeld","event_war_battleofbreitenfeld.ogg",None,"war",None),
    EU4Track("MusicPlayer_eu4_mykingdom","mykingdom.ogg",None,"war",None),
    EU4Track("MusicPlayer_eu4_rideforthvictoriously","rideforthvictoriously.ogg",None,"war",None),
    EU4Track("MusicPlayer_eu4_thestageisset","thestageisset.ogg",None,"war",None),
    EU4Track("MusicPlayer_eu4_war_offtowar","war_offtowar.ogg",None,"war",None),
    EU4Track("MusicPlayer_eu4_mood_discovery","mood_discovery.ogg",None,"discovery",None),
    EU4Track("MusicPlayer_eu4_theageofdiscovery","theageofdiscovery.ogg",None,"discovery",None),
    # DLC 013
    EU4Track("MusicPlayer_eu4_thegrandarmada","music/thegrandarmada.ogg","dlc013_songs_of_the_new_world","peace","iberian"),
    EU4Track("MusicPlayer_eu4_thehunt","music/thehunt.ogg","dlc013_songs_of_the_new_world","neutral",None),
    EU4Track("MusicPlayer_eu4_travelthenewworld","music/travelthenewworld.ogg","dlc013_songs_of_the_new_world","discovery",None),
    # DLC 014
    EU4Track("MusicPlayer_eu4_pdxmascarol","music/pdxmascarol.ogg","dlc014_songs_of_yuletide","neutral",None),
    # DLC 026
    EU4Track("MusicPlayer_eu4_rmp_a_new_way","music/A_new_way.ogg","dlc026_republican_music","neutral",None),
    EU4Track("MusicPlayer_eu4_rmp_diplomatic_awakening","music/Diplomatic_Awakening.ogg","dlc026_republican_music","peace",None),
    EU4Track("MusicPlayer_eu4_rmp_falalalan","music/Falalalan.ogg","dlc026_republican_music","neutral",None),
    # DLC 030
    EU4Track("MusicPlayer_eu4_sow_castles","music/sow_castles.ogg","dlc030_songs_of_war","neutral",None),
    EU4Track("MusicPlayer_eu4_sow_distress","music/sow_distress.ogg","dlc030_songs_of_war","war",None),
    EU4Track("MusicPlayer_eu4_sow_george_whitehead","music/sow_george_whitehead.ogg","dlc030_songs_of_war","war",None),
    # DLC 031
    EU4Track("MusicPlayer_eu4_gds_battleoflepanto","music/031_battleoflepanto.ogg","dlc031_guns_drums_and_steel","war",None),
    EU4Track("MusicPlayer_eu4_gds_kingscourt","music/031_kingscourt.ogg","dlc031_guns_drums_and_steel","neutral",None),
    EU4Track("MusicPlayer_eu4_gds_maintheme","music/031_maintheme.ogg","dlc031_guns_drums_and_steel","neutral",None),
    # DLC 036
    EU4Track("MusicPlayer_eu4_soe_asettlement","music/soe_asettlement.ogg","dlc036_songs_of_exploration","peace",None),
    EU4Track("MusicPlayer_eu4_soe_asettlement2","music/soe_asettlement2.ogg","dlc036_songs_of_exploration","peace",None),
    EU4Track("MusicPlayer_eu4_soe_canzonelabavara","music/soe_canzonelabavara.ogg","dlc036_songs_of_exploration","neutral",None),
    # DLC 037
    EU4Track("MusicPlayer_eu4_gds_eire","music/037_eire.ogg","dlc037_guns_drums_and_steel_volume_2","peace","british_isles"),
    EU4Track("MusicPlayer_eu4_gds_mykingdom","music/037_mykingdom.ogg","dlc037_guns_drums_and_steel_volume_2","war",None),
    # DLC 044
    EU4Track("MusicPlayer_eu4_kairis_emperors_road","music/Emperors_Road.ogg","dlc044_kairis_soundtrack","neutral","east_asian"),
    EU4Track("MusicPlayer_eu4_kairis_forest_shade","music/Forest_Shade.ogg","dlc044_kairis_soundtrack","peace",None),
    EU4Track("MusicPlayer_eu4_kairis_jade_ambitions","music/Jade_Ambitions.ogg","dlc044_kairis_soundtrack","neutral","east_asian"),
    # DLC 052 — REMOVED: Sabaton third-party copyright
    # DLC 059
    EU4Track("MusicPlayer_eu4_ksp2_eastern_fronts","music/ksp2_eastern_fronts.ogg","dlc059_kairis_soundtrack_part_2","war","east_asian"),
    EU4Track("MusicPlayer_eu4_ksp2_peace_for_generations","music/ksp2_peace_for_generations.ogg","dlc059_kairis_soundtrack_part_2","peace","east_asian"),
    EU4Track("MusicPlayer_eu4_ksp2_temple_ambitions","music/ksp2_temple_ambitions.ogg","dlc059_kairis_soundtrack_part_2","neutral","east_asian"),
    EU4Track("MusicPlayer_eu4_ksp2_the_grasslands_call","music/ksp2_the_grasslands_call.ogg","dlc059_kairis_soundtrack_part_2","discovery",None),
    EU4Track("MusicPlayer_eu4_ksp2_the_great_wall","music/ksp2_the_great_wall.ogg","dlc059_kairis_soundtrack_part_2","neutral","east_asian"),
    # DLC 063
    EU4Track("MusicPlayer_eu4_sormp_a_golden_sun_is_rising","music/sormp_A_Golden_Sun_is_Rising_Ambient.ogg","dlc063_songs_of_regency","peace","british_isles"),
    EU4Track("MusicPlayer_eu4_sormp_for_honour_and_glory","music/sormp_For_Honour_and_Glory_War.ogg","dlc063_songs_of_regency","war","british_isles"),
    # DLC 076
    EU4Track("MusicPlayer_eu4_rus_a_russian_heart","music/ruamp_a_russian_heart.ogg","dlc076_the_rus_awaken","neutral","russian"),
    EU4Track("MusicPlayer_eu4_rus_following_the_volga","music/ruamp_following_the_volga.ogg","dlc076_the_rus_awaken","peace","russian"),
    EU4Track("MusicPlayer_eu4_rus_iwans_dream","music/ruamp_iwans_dream.ogg","dlc076_the_rus_awaken","neutral","russian"),
    # DLC 081
    EU4Track("MusicPlayer_eu4_kott_faith_restored","music/Faith_Restored.ogg","dlc081_kairis_soundtrack_3_ottoman_tunes","peace","ottoman"),
    EU4Track("MusicPlayer_eu4_kott_homebound","music/Homebound.ogg","dlc081_kairis_soundtrack_3_ottoman_tunes","peace","ottoman"),
    EU4Track("MusicPlayer_eu4_kott_peace_cannot_last","music/Peace_Cannot_Last.ogg","dlc081_kairis_soundtrack_3_ottoman_tunes","neutral","ottoman"),
    EU4Track("MusicPlayer_eu4_kott_sundered_hills","music/Sundered_Hills.ogg","dlc081_kairis_soundtrack_3_ottoman_tunes","neutral","ottoman"),
    EU4Track("MusicPlayer_eu4_kott_whispers_dark","music/Whispers_in_the_Dark.ogg","dlc081_kairis_soundtrack_3_ottoman_tunes","neutral","middle_eastern"),
    # DLC 089
    EU4Track("MusicPlayer_eu4_brit_alba","music/Alba.ogg","dlc089_rule_britannia_music_pack","neutral","british_isles"),
    EU4Track("MusicPlayer_eu4_brit_battle_in_the_highlands","music/A_Battle_in_the_Highlands.ogg","dlc089_rule_britannia_music_pack","war","british_isles"),
    EU4Track("MusicPlayer_eu4_brit_piper_lead_your_clansmen","music/Piper_Lead_Your_Clansmen.ogg","dlc089_rule_britannia_music_pack","war","british_isles"),
    # DLC 094
    EU4Track("MusicPlayer_eu4_dharma_carnatic","music/Carnatic.ogg","dlc094_dharma_music","neutral","south_asian"),
    EU4Track("MusicPlayer_eu4_dharma_hindustani","music/Hindustani.ogg","dlc094_dharma_music","neutral","south_asian"),
    EU4Track("MusicPlayer_eu4_dharma_rajastani","music/Rajastani.ogg","dlc094_dharma_music","neutral","south_asian"),
    # DLC 099
    EU4Track("MusicPlayer_eu4_gc_birth_of_global_empire","music/birth_of_a_global_empire.ogg","dlc099_golden_century_music","neutral","iberian"),
    EU4Track("MusicPlayer_eu4_gc_conflict_in_the_caribbean","music/conflict_in_the_caribbean.ogg","dlc099_golden_century_music","war","iberian"),
    EU4Track("MusicPlayer_eu4_gc_march_on_granada","music/march_on_granada.ogg","dlc099_golden_century_music","war","iberian"),
    # DLC 105
    EU4Track("MusicPlayer_eu4_emp_empire_divided","music/anempiredivided.ogg","dlc105_emperor_music","neutral","central_european"),
    EU4Track("MusicPlayer_eu4_emp_birthplace_of_renaissance","music/birthplaceofrenaissance.ogg","dlc105_emperor_music","neutral","italian"),
    EU4Track("MusicPlayer_eu4_emp_duality_of_faith","music/dualityoffaith.ogg","dlc105_emperor_music","neutral",None),
    # DLC 108
    EU4Track("MusicPlayer_eu4_na_american_soil","music/american_soil.ogg","dlc108_north_america_music","neutral","north_american"),
    EU4Track("MusicPlayer_eu4_na_cautious_preparation","music/cautious_preparation.ogg","dlc108_north_america_music","neutral",None),
    EU4Track("MusicPlayer_eu4_na_signs_of_victory","music/signs_of_victory.ogg","dlc108_north_america_music","war",None),
    # DLC 109
    EU4Track("MusicPlayer_eu4_sea_discoveries_revealed","music/discoveries_revealed.ogg","dlc109_south_east_asia_music","discovery","east_asian"),
    EU4Track("MusicPlayer_eu4_sea_undisclosed_tactics","music/undisclosed_tactics.ogg","dlc109_south_east_asia_music","war","east_asian"),
    EU4Track("MusicPlayer_eu4_sea_undiscovered_territory","music/undiscovered_territory.ogg","dlc109_south_east_asia_music","discovery",None),
    # DLC 112
    EU4Track("MusicPlayer_eu4_waf_new_destiny_awaits","music/a_new_destiny_awaits.ogg","dlc112_west_african_music_pack","neutral","west_african"),
    EU4Track("MusicPlayer_eu4_waf_into_the_wild","music/into_the_wild.ogg","dlc112_west_african_music_pack","neutral","west_african"),
    EU4Track("MusicPlayer_eu4_waf_strategy_reborn","music/strategy_reborn.ogg","dlc112_west_african_music_pack","war",None),
    # DLC 113
    EU4Track("MusicPlayer_eu4_eaf_encounters_in_the_sun","music/encounters_in_the_sun_ea.ogg","dlc113_east_african_music_pack","neutral","east_african"),
    EU4Track("MusicPlayer_eu4_eaf_neverending_dunes","music/neverending_dunes.ogg","dlc113_east_african_music_pack","neutral","east_african"),
    EU4Track("MusicPlayer_eu4_eaf_the_long_walk","music/the_long_walk_ea.ogg","dlc113_east_african_music_pack","peace",None),
    # DLC 114
    EU4Track("MusicPlayer_eu4_gds3_aarle","music/aarle.ogg","dlc114_guns_drums_and_steel_volume_3","neutral",None),
    EU4Track("MusicPlayer_eu4_gds3_after_the_rain","music/after_the_rain.ogg","dlc114_guns_drums_and_steel_volume_3","peace",None),
    EU4Track("MusicPlayer_eu4_gds3_darkness_falls","music/darkness_falls.ogg","dlc114_guns_drums_and_steel_volume_3","war",None),
    EU4Track("MusicPlayer_eu4_gds3_demons","music/demons.ogg","dlc114_guns_drums_and_steel_volume_3","war",None),
    EU4Track("MusicPlayer_eu4_gds3_kettil","music/kettil.ogg","dlc114_guns_drums_and_steel_volume_3","neutral",None),
    EU4Track("MusicPlayer_eu4_gds3_last_stand","music/last_stand.ogg","dlc114_guns_drums_and_steel_volume_3","war",None),
    EU4Track("MusicPlayer_eu4_gds3_legends_north","music/legends_of_the_north.ogg","dlc114_guns_drums_and_steel_volume_3","neutral","scandinavian"),
    EU4Track("MusicPlayer_eu4_gds3_over_seas","music/over_seas.ogg","dlc114_guns_drums_and_steel_volume_3","discovery",None),
    EU4Track("MusicPlayer_eu4_gds3_ravens","music/ravens.ogg","dlc114_guns_drums_and_steel_volume_3","war",None),
    EU4Track("MusicPlayer_eu4_gds3_the_conqueror","music/the_conqueror.ogg","dlc114_guns_drums_and_steel_volume_3","war",None),
    EU4Track("MusicPlayer_eu4_gds3_voices","music/voices.ogg","dlc114_guns_drums_and_steel_volume_3","neutral",None),
    EU4Track("MusicPlayer_eu4_gds3_whispering_forest","music/whispering_forest.ogg","dlc114_guns_drums_and_steel_volume_3","peace",None),
    # DLC 117
    EU4Track("MusicPlayer_eu4_scan_battle_of_scandinavia","music/battle_of_scandinavia.ogg","dlc117_scandinavian_music_pack","war","scandinavian"),
    EU4Track("MusicPlayer_eu4_scan_lands_of_midnight_sun","music/lands_of_midnight_sun.ogg","dlc117_scandinavian_music_pack","peace","scandinavian"),
    EU4Track("MusicPlayer_eu4_scan_united_we_stand","music/united_we_stand.ogg","dlc117_scandinavian_music_pack","neutral","scandinavian"),
    # DLC 118
    EU4Track("MusicPlayer_eu4_balt_crowned_in_tallin","music/crowned_in_tallin.ogg","dlc118_baltics_music_pack","neutral","baltic"),
    EU4Track("MusicPlayer_eu4_balt_knights_of_swords","music/knights_of_swords.ogg","dlc118_baltics_music_pack","war","baltic"),
    EU4Track("MusicPlayer_eu4_balt_rise_of_the_balts","music/rise_of_the_balts.ogg","dlc118_baltics_music_pack","neutral","baltic"),
    # DLC 121
    EU4Track("MusicPlayer_eu4_ott_conquest_of_constantinople","music/conquest_of_constantinople.ogg","dlc121_ottoman_music_pack","war","ottoman"),
    EU4Track("MusicPlayer_eu4_ott_redrawing_the_map","music/redrawing_the_map.ogg","dlc121_ottoman_music_pack","neutral","ottoman"),
    EU4Track("MusicPlayer_eu4_ott_suleiman_the_magnificent","music/suleiman_the_magnificent.ogg","dlc121_ottoman_music_pack","neutral","ottoman"),
    # DLC 122
    EU4Track("MusicPlayer_eu4_chi_path_of_the_dragon","music/path_of_the_dragon.ogg","dlc122_chinese_music_pack","neutral","east_asian"),
    EU4Track("MusicPlayer_eu4_chi_ports_of_china","music/ports_of_china.ogg","dlc122_chinese_music_pack","peace","east_asian"),
    EU4Track("MusicPlayer_eu4_chi_staff_of_the_emperor","music/staff_of_the_emperor.ogg","dlc122_chinese_music_pack","neutral","east_asian"),
    # DLC 123
    EU4Track("MusicPlayer_eu4_fr_a_new_king_arrives","music/a_new_king_arrives.ogg","dlc123_french_music_pack","neutral","french"),
    EU4Track("MusicPlayer_eu4_fr_castle_of_versailles","music/castle_of_versailles.ogg","dlc123_french_music_pack","peace","french"),
    EU4Track("MusicPlayer_eu4_fr_le_premier_jour","music/le_premier_jour.ogg","dlc123_french_music_pack","neutral","french"),
    # DLC 127
    EU4Track("MusicPlayer_eu4_ann_brief_history","music/a_brief_history_of_everything.ogg","dlc127_10th_anniversary","neutral",None),
    EU4Track("MusicPlayer_eu4_ann_world_to_explore","music/a_world_to_explore.ogg","dlc127_10th_anniversary","discovery",None),
    EU4Track("MusicPlayer_eu4_ann_all_roads_rome","music/all_roads_lead_to_rome.ogg","dlc127_10th_anniversary","neutral","italian"),
    EU4Track("MusicPlayer_eu4_ann_back_motherland","music/back_to_the_motherland.ogg","dlc127_10th_anniversary","neutral",None),
    EU4Track("MusicPlayer_eu4_ann_clara_umbra","music/clara_umbra.ogg","dlc127_10th_anniversary","neutral",None),
    EU4Track("MusicPlayer_eu4_ann_dawn_empire","music/dawn_of_an_empire.ogg","dlc127_10th_anniversary","neutral",None),
    EU4Track("MusicPlayer_eu4_ann_in_taverns","music/in_taverns_and_great_halls.ogg","dlc127_10th_anniversary","peace",None),
    EU4Track("MusicPlayer_eu4_ann_into_beyond","music/into_the_beyond.ogg","dlc127_10th_anniversary","discovery",None),
    EU4Track("MusicPlayer_eu4_ann_one_world","music/one_world.ogg","dlc127_10th_anniversary","neutral",None),
    EU4Track("MusicPlayer_eu4_ann_conquistador","music/the_conquistador.ogg","dlc127_10th_anniversary","war","iberian"),
    # DLC 130
    EU4Track("MusicPlayer_eu4_egy_blue_nile","music/blue_nile.ogg","dlc130_egyptian_music_pack","neutral","middle_eastern"),
    EU4Track("MusicPlayer_eu4_egy_fates_of_the_desert","music/fates_of_the_desert.ogg","dlc130_egyptian_music_pack","neutral","middle_eastern"),
    # DLC 131
    EU4Track("MusicPlayer_eu4_per_battles_on_persian_borders","music/battles_on_persian_borders.ogg","dlc131_persian_music_pack","war","middle_eastern"),
    EU4Track("MusicPlayer_eu4_per_harbors_of_the_caspian_sea","music/harbors_of_the_caspian_sea.ogg","dlc131_persian_music_pack","neutral","middle_eastern"),
    # DLC 132
    EU4Track("MusicPlayer_eu4_cau_battle_of_kakheti","music/battle_of_kakheti.ogg","dlc132_caucasian_music_pack","war","caucasian"),
    EU4Track("MusicPlayer_eu4_cau_caucasus_mountains","music/caucasus_mountains.ogg","dlc132_caucasian_music_pack","neutral","caucasian"),
    # DLC 133
    EU4Track("MusicPlayer_eu4_hre_continuation_diplomacy","music/a_continuation_of_diplomacy.ogg","dlc133_utopia_hre_music_pack","peace","central_european"),
    EU4Track("MusicPlayer_eu4_hre_autumn_aachen","music/autumn_in_aachen.ogg","dlc133_utopia_hre_music_pack","peace","central_european"),
    EU4Track("MusicPlayer_eu4_hre_charlemagne_legacy","music/charlemange_s_legacy.ogg","dlc133_utopia_hre_music_pack","neutral","central_european"),
    EU4Track("MusicPlayer_eu4_hre_election_habsburg","music/election_of_a_habsburg.ogg","dlc133_utopia_hre_music_pack","neutral","central_european"),
    EU4Track("MusicPlayer_eu4_hre_imperial_diet","music/imperial_diet.ogg","dlc133_utopia_hre_music_pack","neutral","central_european"),
    EU4Track("MusicPlayer_eu4_hre_life_shadow_kingdom","music/life_under_the_shadow_kingdom.ogg","dlc133_utopia_hre_music_pack","neutral",None),
    EU4Track("MusicPlayer_eu4_hre_ninety_five_theses","music/ninety_five_theses.ogg","dlc133_utopia_hre_music_pack","neutral","central_european"),
    EU4Track("MusicPlayer_eu4_hre_rise_loyal_subjects","music/now_rise_my_loyal_subjects.ogg","dlc133_utopia_hre_music_pack","war","central_european"),
    EU4Track("MusicPlayer_eu4_hre_order_diplomacy","music/order_and_diplomacy.ogg","dlc133_utopia_hre_music_pack","peace","central_european"),
    EU4Track("MusicPlayer_eu4_hre_prussian_ambitions","music/prussian_ambitions.ogg","dlc133_utopia_hre_music_pack","war","central_european"),
    # DLC 134
    EU4Track("MusicPlayer_eu4_ksp3_blood_old_gods","music/blood_of_the_old_gods.ogg","dlc134_kairis_soundtrack_part_3","war",None),
    EU4Track("MusicPlayer_eu4_ksp3_city_worlds_desire","music/city_of_the_world_s_desire.ogg","dlc134_kairis_soundtrack_part_3","neutral","ottoman"),
    EU4Track("MusicPlayer_eu4_ksp3_crossing_seas","music/crossing_the_seas.ogg","dlc134_kairis_soundtrack_part_3","discovery",None),
    EU4Track("MusicPlayer_eu4_ksp3_eastern_mists","music/eastern_mists.ogg","dlc134_kairis_soundtrack_part_3","neutral","east_asian"),
    EU4Track("MusicPlayer_eu4_ksp3_fine_day_sacrifice","music/fine_day_for_sacrifice.ogg","dlc134_kairis_soundtrack_part_3","war","north_american"),
    EU4Track("MusicPlayer_eu4_ksp3_gaelic_summers","music/gaelic_summers.ogg","dlc134_kairis_soundtrack_part_3","peace","british_isles"),
    EU4Track("MusicPlayer_eu4_ksp3_hundred_years_war","music/hundred_years_war.ogg","dlc134_kairis_soundtrack_part_3","war","french"),
    EU4Track("MusicPlayer_eu4_ksp3_la_bataille_iberia","music/la_bataille_de_iberia.ogg","dlc134_kairis_soundtrack_part_3","war","iberian"),
    EU4Track("MusicPlayer_eu4_ksp3_march_empire","music/march_for_the_empire.ogg","dlc134_kairis_soundtrack_part_3","war",None),
    EU4Track("MusicPlayer_eu4_ksp3_old_families","music/old_families.ogg","dlc134_kairis_soundtrack_part_3","neutral",None),
    EU4Track("MusicPlayer_eu4_ksp3_prelude_march","music/prelude_s_march.ogg","dlc134_kairis_soundtrack_part_3","neutral",None),
    EU4Track("MusicPlayer_eu4_ksp3_shogunate_fall","music/the_shogunate_will_fall.ogg","dlc134_kairis_soundtrack_part_3","war","east_asian"),
    EU4Track("MusicPlayer_eu4_ksp3_siege_of_vienna","music/the_siege_of_vienna.ogg","dlc134_kairis_soundtrack_part_3","war","central_european"),
    # DLC 138
    EU4Track("MusicPlayer_eu4_natam_aztec_theme","music/aztec_theme.ogg","dlc138_native_america_music_pack","neutral","north_american"),
    EU4Track("MusicPlayer_eu4_natam_inca_theme","music/inca_theme.ogg","dlc138_native_america_music_pack","neutral","south_american"),
    # DLC 139
    EU4Track("MusicPlayer_eu4_cas_hordes_centralasian","music/hordes_centralasian.ogg","dlc139_central_asia_music_pack","war","central_asian"),
    EU4Track("MusicPlayer_eu4_cas_mughal_indian_persian","music/mughal_indian_persian.ogg","dlc139_central_asia_music_pack","neutral","central_asian"),
    # DLC 140
    EU4Track("MusicPlayer_eu4_ce_austria_theme","music/austria_theme.ogg","dlc140_central_europe_music_pack","neutral","central_european"),
    EU4Track("MusicPlayer_eu4_ce_hungary_theme","music/hungary_theme.ogg","dlc140_central_europe_music_pack","neutral","central_european"),
]

# ─── WWISE BINARY HELPERS ───────────────────────────────────────────────────

def make_id(name: str) -> int:
    """FNV-1 hash — matches Wwise's internal ID scheme."""
    h = 2166136261
    for c in name.lower().encode('ascii', errors='replace'):
        h = (h * 16777619) & 0xFFFFFFFF
        h ^= c
    return h

def pack_u8(v):  return struct.pack('B', v & 0xFF)
def pack_u16(v): return struct.pack('<H', v & 0xFFFF)
def pack_u32(v): return struct.pack('<I', v & 0xFFFFFFFF)
def pack_f32(v): return struct.pack('<f', v)
def pack_f64(v): return struct.pack('<d', v)

def make_hirc(obj_type: int, obj_id: int, content: bytes) -> bytes:
    body = pack_u32(obj_id) + content
    return pack_u8(obj_type) + pack_u32(len(body)) + body

def make_music_track(track_id, wem_id, wem_size, duration_sec, seg_id):
    """MusicTrack from EU5 track 0x13771d69 (111b, numPlaylistItem=1, no crash)."""
    dur_ms = duration_sec * 1000.0
    t = bytearray(bytes.fromhex(
        '00010000000100040001555f6625c2150000000100000000000000555f6625'
        '00000000000000000000000000000000000000000000000000000000'
        '1357ba37a0d8bc4001000000000000000000000000000000'
        'ec74d200000000000000000000000100000000000000000064000000'
    ))
    t[10:14] = pack_u32(wem_id)
    t[14:18] = pack_u32(wem_size)
    t[27:31] = pack_u32(wem_id)
    t[35:43] = pack_f64(0.0)        # fPlayAt
    t[43:51] = pack_f64(0.0)        # fBeginTrimOffset
    t[51:59] = pack_f64(0.0)        # fEndTrimOffset
    t[59:67] = pack_f64(dur_ms)     # fSrcDuration
    t[83:87] = pack_u32(seg_id)     # DirectParentID
    return make_hirc(11, track_id, bytes(t))

def make_music_segment(seg_id, track_id, duration_sec):
    """MusicSegment referencing Music Player playlist (0x3b5ae824)."""
    dur_ms = duration_sec * 1000.0
    t = bytearray(bytes.fromhex(
        '00000000000000000024e85a3b0000000000000000000001000000000000000001000000'
        'ca670435'
        '0000000000408f4000000000000000000000f0420404000000000045c85fb343d30741'
        '0200000012df980200000000000000000048d6bb5b'
        '45c85fb343d30741'
        '00'
    ))
    t[36:40] = pack_u32(track_id)
    t[67:75] = pack_f64(dur_ms)
    t[96:104]= pack_f64(dur_ms)
    return make_hirc(10, seg_id, bytes(t))

def make_music_segment_dynamic(seg_id, track_id, duration_sec, playlist_id):
    """MusicSegment referencing a dynamic playlist (WAR/PEACE/culture)."""
    dur_ms = duration_sec * 1000.0
    t = bytearray(bytes.fromhex(
        '00000000000000000024e85a3b0000000000000000000001000000000000000001000000'
        'ca670435'
        '0000000000408f4000000000000000000000f0420404000000000045c85fb343d30741'
        '0200000012df980200000000000000000048d6bb5b'
        '45c85fb343d30741'
        '00'
    ))
    t[9:13]  = pack_u32(playlist_id)
    t[36:40] = pack_u32(track_id)
    t[67:75] = pack_f64(dur_ms)
    t[96:104]= pack_f64(dur_ms)
    return make_hirc(10, seg_id, bytes(t))

def make_setup_action(action_id):
    content = pack_u8(0x03) + pack_u8(0x21) + pack_u32(0xdccd55a7) + b'\x00\x00\x00'
    return make_hirc(3, action_id, content)

def make_play_action(action_id, seg_id):
    _SUFFIX = bytes.fromhex('00000004a1c7709300000000')
    content  = pack_u8(0x03) + pack_u8(0x04) + pack_u32(seg_id) + _SUFFIX
    return make_hirc(3, action_id, content)

def make_event(event_id, action_ids):
    content = pack_u8(len(action_ids))
    for a in action_ids: content += pack_u32(a)
    return make_hirc(4, event_id, content)

def make_bank(version, bank_id, hirc_objs, wem_entries=None):
    guid = hashlib.md5(f"eu4_{bank_id}".encode()).digest()
    bkhd = pack_u32(version) + pack_u32(bank_id) + pack_u32(0x17705D3E) + pack_u32(0x10) + pack_u32(0x387C) + pack_u32(0) + guid
    out  = b'BKHD' + pack_u32(len(bkhd)) + bkhd
    if wem_entries:
        didx = b''; data = b''; off = 0
        for wid, wdata in wem_entries:
            pad = (16 - off%16) % 16
            data += b'\x00'*pad; off += pad
            didx += pack_u32(wid) + pack_u32(off) + pack_u32(len(wdata))
            data += wdata; off += len(wdata)
        out += b'DIDX' + pack_u32(len(didx)) + didx
        out += b'DATA' + pack_u32(len(data)) + data
    if hirc_objs:
        hirc = pack_u32(len(hirc_objs)) + b''.join(hirc_objs)
        out += b'HIRC' + pack_u32(len(hirc)) + hirc
    return out

# ─── PLAYLIST PATCHING ──────────────────────────────────────────────────────

def _patch_steprand_no_children(content: bytes, seg_ids: list, gap: int) -> bytes:
    """Add segments to StepRandom WITHOUT updating Children list.
    Skipping Children list update avoids result:15 circular dependency.
    gap=189 for WAR/PEACE, gap=95 for most culture, gap=236 for middle_east."""
    c = bytearray(content); n = len(seg_ids)
    ch = struct.unpack('<I', c[32:36])[0]
    ch_end = 36 + ch * 4
    ni_off = ch_end + gap
    c[ni_off:ni_off+4] = pack_u32(struct.unpack('<I', c[ni_off:ni_off+4])[0] + n)
    root_off = ni_off + 4; step_off = root_off + 30
    sn = struct.unpack('<I', c[step_off+8:step_off+12])[0]
    c[step_off+8:step_off+12] = pack_u32(sn + n)
    leaf_end = step_off + 30 + sn * 30
    leaves = b''
    for i, sid in enumerate(seg_ids):
        iid = (sid ^ 0xC0FFEE00 ^ i) & 0xFFFFFFFF
        leaves += pack_u32(sid)+pack_u32(iid)+pack_u32(0)+struct.pack('<i',-1)+pack_u16(1)+pack_u16(0)+pack_u16(0)+pack_u32(50000)+pack_u16(0)+b'\x00\x00'
    c = c[:leaf_end] + leaves + c[leaf_end:]
    return bytes(c)

# ─── OGG → WEM CONVERSION ───────────────────────────────────────────────────

def _win(p: Path) -> str:
    s = str(p)
    if s.startswith('/mnt/'):
        return s[5].upper() + ':' + s[6:].replace('/', '\\')
    return s

def _wem_duration(wem_data: bytes) -> float:
    pos = 12
    while pos < len(wem_data) - 8:
        cid = wem_data[pos:pos+4]; sz = struct.unpack('<I', wem_data[pos+4:pos+8])[0]
        if cid == b'fmt ':
            vorb = wem_data[pos+8+24:]
            sc = struct.unpack('<I', vorb[0:4])[0]
            sr = struct.unpack('<I', wem_data[pos+8+4:pos+8+8])[0]
            return sc / max(sr, 1)
        pos += 8 + sz
    return 0.0

def ogg_to_wem(ogg_path: Path, wem_path: Path) -> Optional[dict]:
    print(f"  Converting: {ogg_path.name}")
    WWISE_TMP_DIR.mkdir(parents=True, exist_ok=True)
    stem = wem_path.stem
    tmp_wav  = WWISE_TMP_DIR / f'{stem}.wav'
    wsources = WWISE_TMP_DIR / f'{stem}.wsources'
    out_dir  = WWISE_TMP_DIR / f'{stem}_out'
    try:
        r = subprocess.run(['ffmpeg','-y','-i',str(ogg_path),'-ar','48000','-ac','2','-acodec','pcm_s16le',str(tmp_wav)],
                           capture_output=True, timeout=120)
        if r.returncode != 0:
            print(f"    ERROR ffmpeg: {r.stderr.decode()[:200]}"); return None
        proj = WWISE_PROJ_DIR / f'{WWISE_PROJ_DIR.name}.wproj'
        if not proj.exists():
            WWISE_PROJ_DIR.mkdir(parents=True, exist_ok=True)
            subprocess.run([str(WWISE_CONSOLE),'create-new-project',_win(proj),'--quiet'], capture_output=True, timeout=60)
        wsources.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<ExternalSourcesList SchemaVersion="1" Root="{_win(WWISE_TMP_DIR)}">\n'
            f'\t<Source Path="{tmp_wav.name}" Conversion="Vorbis Quality High"/>\n'
            '</ExternalSourcesList>\n', encoding='utf-8')
        out_dir.mkdir(exist_ok=True)
        subprocess.run([str(WWISE_CONSOLE),'convert-external-source',_win(proj),
                        '--source-file',_win(wsources),'--output',_win(out_dir),'--quiet'],
                       capture_output=True, timeout=300)
        candidates = list((out_dir/'Windows').glob('*.wem')) if (out_dir/'Windows').exists() else []
        if not candidates: candidates = list(out_dir.rglob('*.wem'))
        if not candidates: print(f"    ERROR: no WEM output"); return None
        shutil.move(str(candidates[0]), str(wem_path))
        wdata = wem_path.read_bytes()
        dur = _wem_duration(wdata)
        print(f"    OK: {len(wdata)//1024}KB, {dur:.1f}s")
        return {'duration': dur, 'size': len(wdata)}
    except Exception as e:
        print(f"    ERROR: {e}"); return None
    finally:
        for p in [tmp_wav, wsources]:
            try: p.unlink()
            except: pass
        try: shutil.rmtree(str(out_dir), ignore_errors=True)
        except: pass

def find_ogg(track: EU4Track, tmp_dir: Path) -> Optional[Path]:
    if track.dlc is None:
        p = EU4_PATH / "music" / track.source_file
        return p if p.exists() else None
    dlc_dir = EU4_PATH / "dlc" / track.dlc
    if not dlc_dir.exists(): return None
    zips = list(dlc_dir.glob("*.zip"))
    if not zips: return None
    filename = Path(track.source_file).name
    output = tmp_dir / track.dlc / filename
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists(): return output
    for zp in zips:
        try:
            with zipfile.ZipFile(str(zp)) as z:
                names = z.namelist()
                match = next((n for n in names if n.endswith(track.source_file) or n == track.source_file), None)
                if not match: continue
                z.extract(match, str(output.parent.parent))
                extracted = output.parent.parent / match
                if extracted != output:
                    output.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(extracted), str(output))
                return output
        except: pass
    return None

# ─── MAIN BUILD ─────────────────────────────────────────────────────────────

# Culture playlist IDs with correct gaps
CULTURE_PLAYLISTS = {
    'european':      (0x172E4EBA, 95),
    'east_asian':    (0x2AE87B0D, 95),
    'african':       (0x2D1FE56A, 95),
    'middle_east':   (0x177DFABD, 236),  # different structure
    'indian':        (0x014173A7, 95),
    'north_american':(0x0847DCF1, 95),
    'south_american':(0x360B858E, 95),
}
REGION_TO_CULTURE = {
    'british_isles':'european','scandinavian':'european','french':'european',
    'iberian':'european','central_european':'european','italian':'european',
    'baltic':'european','russian':'european',
    'east_asian':'east_asian',
    'west_african':'african','east_african':'african',
    'middle_eastern':'middle_east','ottoman':'middle_east','caucasian':'middle_east',
    'south_asian':'indian','central_asian':'indian',
    'north_american':'north_american',
    'south_american':'south_american',
}

def build():
    print("=" * 60)
    print("EU4 Soundtrack for EU5 - Build")
    print("=" * 60)
    if not shutil.which('ffmpeg'):
        print("ERROR: ffmpeg not found"); sys.exit(1)
    BANKS_PATH.mkdir(parents=True, exist_ok=True)
    MEDIA_PATH.mkdir(parents=True, exist_ok=True)
    tmp_dir = MOD_PATH / "_tmp_ogg"; tmp_dir.mkdir(exist_ok=True)

    hirc_objects = []; war_ids = []; peace_ids = []
    culture_ids  = {k: [] for k in CULTURE_PLAYLISTS}
    built_tracks = []; prefetch_entries = []
    WAR_PL = 0x3de374bf; PCE_PL = 0x290f1591

    print(f"\nProcessing {len(TRACKS)} tracks...")
    for track in TRACKS:
        print(f"\n[{track.event_name}]")
        ogg_path = find_ogg(track, tmp_dir)
        if not ogg_path:
            print("  SKIPPED: source not found"); continue

        wem_id  = make_id(track.event_name + "_wem")
        wem_path = MEDIA_PATH / f"{wem_id}.wem"

        if wem_path.exists():
            wdata = wem_path.read_bytes()
            if len(wdata) > 22 and wdata[20:22] == b'\xff\xff':
                print("  WEM exists (Vorbis)")
                dur = max(1.0, _wem_duration(wdata))
            else:
                print("  WEM exists (old format), reconverting...")
                wem_path.unlink()
                r = ogg_to_wem(ogg_path, wem_path)
                if not r: continue
                wdata = wem_path.read_bytes(); dur = r['duration']
        else:
            r = ogg_to_wem(ogg_path, wem_path)
            if not r: continue
            wdata = wem_path.read_bytes(); dur = r['duration']

        pref_data = wdata[:min(PREFETCH_SIZE, len(wdata))]
        pref_size = len(pref_data)

        tid = make_id(track.event_name + "_track")
        sid = make_id(track.event_name + "_seg")
        aid = make_id(track.event_name + "_action")
        uid = make_id(track.event_name + "_setup")
        eid = make_id(track.event_name)

        # Music Player chain
        hirc_objects += [
            make_music_track(tid, wem_id, pref_size, dur, sid),
            make_music_segment(sid, tid, dur),
            make_setup_action(uid),
            make_play_action(aid, sid),
            make_event(eid, [uid, aid]),
        ]

        # WAR/PEACE dynamic
        if track.mood == 'war':
            ds = make_id(track.event_name+'_dynseg'); dt = make_id(track.event_name+'_dyn_track')
            hirc_objects += [make_music_track(dt,wem_id,pref_size,dur,ds), make_music_segment_dynamic(ds,dt,dur,WAR_PL)]
            war_ids.append(ds)
        elif track.mood == 'peace':
            ds = make_id(track.event_name+'_dynseg'); dt = make_id(track.event_name+'_dyn_track')
            hirc_objects += [make_music_track(dt,wem_id,pref_size,dur,ds), make_music_segment_dynamic(ds,dt,dur,PCE_PL)]
            peace_ids.append(ds)
        else:
            wds=make_id(track.event_name+'_war_dynseg'); wdt=make_id(track.event_name+'_war_dyn_track')
            pds=make_id(track.event_name+'_pce_dynseg'); pdt=make_id(track.event_name+'_pce_dyn_track')
            hirc_objects += [
                make_music_track(wdt,wem_id,pref_size,dur,wds), make_music_segment_dynamic(wds,wdt,dur,WAR_PL),
                make_music_track(pdt,wem_id,pref_size,dur,pds), make_music_segment_dynamic(pds,pdt,dur,PCE_PL),
            ]
            war_ids.append(wds); peace_ids.append(pds)

        # Culture dynamic
        if track.region and track.region in REGION_TO_CULTURE:
            cult = REGION_TO_CULTURE[track.region]
            pl_id, _ = CULTURE_PLAYLISTS[cult]
            cds=make_id(track.event_name+'_cult_dynseg'); cdt=make_id(track.event_name+'_cult_dyn_track')
            hirc_objects += [make_music_track(cdt,wem_id,pref_size,dur,cds), make_music_segment_dynamic(cds,cdt,dur,pl_id)]
            culture_ids[cult].append(cds)

        prefetch_entries.append((wem_id, pref_data))
        built_tracks.append(track)
        print(f"  wem_id={wem_id}, dur={dur:.0f}s")

    if not built_tracks:
        print("\nERROR: No tracks built."); sys.exit(1)

    print(f"\nBuilding banks ({len(built_tracks)} tracks, {len(hirc_objects)} HIRC objects)...")
    eu5_bnk = EU5_PATH / "game/loading_screen/sound/banks/windows/sb_music_logic.bnk"
    logic_id = binascii.crc32(b'eu4_soundtrack_music') & 0xFFFFFFFF

    # Patch EU5 base bank
    with open(str(eu5_bnk),'rb') as f: base = f.read()
    pos=0; sections=[]
    while pos<len(base)-8:
        cid=base[pos:pos+4]; sz=struct.unpack('<I',base[pos+4:pos+8])[0]
        sections.append((cid,sz,base[pos+8:pos+8+sz])); pos+=8+sz

    out=b''
    for cid,sz,chunk in sections:
        if cid==b'BKHD':
            guid=hashlib.md5(f'eu4_bnk_{logic_id}'.encode()).digest()
            nb=chunk[:4]+pack_u32(logic_id)+chunk[8:24]+guid[:16]
            out+=b'BKHD'+pack_u32(len(nb))+nb
        elif cid==b'HIRC':
            orig=struct.unpack('<I',chunk[:4])[0]; p=4; raw=[]
            for _ in range(orig):
                ot=chunk[p]; os_=struct.unpack('<I',chunk[p+1:p+5])[0]
                obj=chunk[p+5:p+5+os_]; oid=struct.unpack('<I',obj[:4])[0]
                patched=False
                if oid==WAR_PL and war_ids:
                    pat=_patch_steprand_no_children(obj[4:],war_ids,189)
                    raw.append(bytes([ot])+pack_u32(4+len(pat))+obj[:4]+pat); patched=True
                elif oid==PCE_PL and peace_ids:
                    pat=_patch_steprand_no_children(obj[4:],peace_ids,189)
                    raw.append(bytes([ot])+pack_u32(4+len(pat))+obj[:4]+pat); patched=True
                else:
                    for cult,(pl_id,gap) in CULTURE_PLAYLISTS.items():
                        if oid==pl_id and culture_ids[cult]:
                            pat=_patch_steprand_no_children(obj[4:],culture_ids[cult],gap)
                            raw.append(bytes([ot])+pack_u32(4+len(pat))+obj[:4]+pat); patched=True; break
                if not patched: raw.append(chunk[p:p+5+os_])
                p+=5+os_
            all_objs=raw+list(hirc_objects)
            nh=pack_u32(len(all_objs))+b''.join(all_objs)
            out+=b'HIRC'+pack_u32(len(nh))+nh
        else:
            out+=cid+pack_u32(sz)+chunk

    logic_path = BANKS_PATH / "eu4_soundtrack_music.bnk"
    with open(str(logic_path),'wb') as f: f.write(out)

    media_id = binascii.crc32(b'eu4_soundtrack_media') & 0xFFFFFFFF
    media_data = make_bank(150, media_id, [], prefetch_entries)
    with open(str(BANKS_PATH/'eu4_soundtrack_media.bnk'),'wb') as f: f.write(media_data)

    wem_ids = [make_id(t.event_name+'_wem') for t in built_tracks]
    sbi = {'SoundBanksInfo':{'Platform':'Windows','SoundBanks':[
        {'Id':str(logic_id),'Language':'SFX','ShortName':'eu4_soundtrack_music','Path':'eu4_soundtrack_music.bnk','Media':[{'Id':str(w),'ShortName':f'{w}.wem','Path':f'Media/{w}.wem'} for w in wem_ids]},
        {'Id':str(media_id),'Language':'SFX','ShortName':'eu4_soundtrack_media','Path':'eu4_soundtrack_media.bnk','Media':[{'Id':str(w),'ShortName':f'{w}.wem','Path':f'Media/{w}.wem'} for w in wem_ids]},
    ]}}
    with open(str(BANKS_PATH/'SoundbanksInfo.json'),'w') as f: json.dump(sbi,f,indent=2)

    shutil.rmtree(tmp_dir, ignore_errors=True)

    hc = struct.unpack('<I',out[48+8:48+12])[0]
    print(f"\n{'='*60}")
    print(f"BUILD COMPLETE: {len(built_tracks)} tracks")
    print(f"  eu4_soundtrack_music.bnk: {len(out)//1024}KB ({hc} HIRC objects)")
    print(f"  eu4_soundtrack_media.bnk: {len(media_data)//1024}KB")
    print(f"  WAR: +{len(war_ids)}  PEACE: +{len(peace_ids)}  CULTURE: +{sum(len(v) for v in culture_ids.values())}")
    print("="*60)

if __name__ == '__main__':
    build()
