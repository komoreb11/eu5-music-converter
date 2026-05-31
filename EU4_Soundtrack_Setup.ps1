#Requires -Version 5.1
<#
.SYNOPSIS
    EU4 Soundtrack for EU5 - Auto Setup & Launcher
.DESCRIPTION
    Checks and converts missing EU4 tracks to WEM format, then launches EU5.
    No Python required. Uses ffmpeg + Wwise Authoring Tools.
.NOTES
    Steam launch option:
    powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\EU4_Soundtrack_Setup.ps1" -LaunchCmd "%COMMAND%"
    
    Or self-updating from GitHub:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr 'https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.ps1' -OutFile '$env:TEMP\eu4snd.ps1'; & '$env:TEMP\eu4snd.ps1' -LaunchCmd '%COMMAND%'"
#>

param([string]$LaunchCmd = "")

# Refresh PATH so winget-installed tools (ffmpeg etc.) are found
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "EU4 Soundtrack Setup"

# --- CONFIG ------------------------------------------------
$ModDir    = "$env:USERPROFILE\Documents\Paradox Interactive\Europa Universalis V\mod\eu4_soundtrack"
$BanksDir  = "$ModDir\loading_screen\sound\banks\windows"
$MediaDir  = "$BanksDir\Media"
$WwiseProjDir = "$ModDir\wwise_project"
$WwiseTmpDir  = "$env:TEMP\eu4snd_wwise"
$GitHubRaw = "https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main"

# --- TRACK LIST --------------------------------------------
# Format: @(EventName, SourceOgg, DlcDir_or_$null)
$Tracks = @(
    "MusicPlayer_eu4_maintheme|maintheme.ogg|"
    "MusicPlayer_eu4_dehominisdignitate|dehominisdignitate.ogg|"
    "MusicPlayer_eu4_kingscourt|kingscourt.ogg|"
    "MusicPlayer_eu4_kingsinthenorth|kingsinthenorth.ogg|"
    "MusicPlayer_eu4_machiavelli|machiavelli.ogg|"
    "MusicPlayer_eu4_nighttime|nighttime.ogg|"
    "MusicPlayer_eu4_thestonemasons|thestonemasons.ogg|"
    "MusicPlayer_eu4_moodevent_thesnowiscoming|moodevent_thesnowiscoming.ogg|"
    "MusicPlayer_eu4_amongthepoor|amongthepoor.ogg|"
    "MusicPlayer_eu4_commerceinthepeninsula|commerceinthepeninsula.ogg|"
    "MusicPlayer_eu4_eire|eire.ogg|"
    "MusicPlayer_eu4_inthestreets|inthestreets.ogg|"
    "MusicPlayer_eu4_mood_landinsight|mood_landinsight.ogg|"
    "MusicPlayer_eu4_openseas|openseas.ogg|"
    "MusicPlayer_eu4_thesoundofsummer|thesoundofsummer.ogg|"
    "MusicPlayer_eu4_battleoflepanto|battleoflepanto.ogg|"
    "MusicPlayer_eu4_event_war_battleofbreitenfeld|event_war_battleofbreitenfeld.ogg|"
    "MusicPlayer_eu4_mykingdom|mykingdom.ogg|"
    "MusicPlayer_eu4_rideforthvictoriously|rideforthvictoriously.ogg|"
    "MusicPlayer_eu4_thestageisset|thestageisset.ogg|"
    "MusicPlayer_eu4_war_offtowar|war_offtowar.ogg|"
    "MusicPlayer_eu4_mood_discovery|mood_discovery.ogg|"
    "MusicPlayer_eu4_theageofdiscovery|theageofdiscovery.ogg|"
    "MusicPlayer_eu4_thegrandarmada|music/thegrandarmada.ogg|dlc013_songs_of_the_new_world"
    "MusicPlayer_eu4_thehunt|music/thehunt.ogg|dlc013_songs_of_the_new_world"
    "MusicPlayer_eu4_travelthenewworld|music/travelthenewworld.ogg|dlc013_songs_of_the_new_world"
    "MusicPlayer_eu4_pdxmascarol|music/pdxmascarol.ogg|dlc014_songs_of_yuletide"
    "MusicPlayer_eu4_rmp_a_new_way|music/A_new_way.ogg|dlc026_republican_music"
    "MusicPlayer_eu4_rmp_diplomatic_awakening|music/Diplomatic_Awakening.ogg|dlc026_republican_music"
    "MusicPlayer_eu4_rmp_falalalan|music/Falalalan.ogg|dlc026_republican_music"
    "MusicPlayer_eu4_sow_castles|music/sow_castles.ogg|dlc030_songs_of_war"
    "MusicPlayer_eu4_sow_distress|music/sow_distress.ogg|dlc030_songs_of_war"
    "MusicPlayer_eu4_sow_george_whitehead|music/sow_george_whitehead.ogg|dlc030_songs_of_war"
    "MusicPlayer_eu4_gds_battleoflepanto|music/031_battleoflepanto.ogg|dlc031_guns_drums_and_steel"
    "MusicPlayer_eu4_gds_kingscourt|music/031_kingscourt.ogg|dlc031_guns_drums_and_steel"
    "MusicPlayer_eu4_gds_maintheme|music/031_maintheme.ogg|dlc031_guns_drums_and_steel"
    "MusicPlayer_eu4_soe_asettlement|music/soe_asettlement.ogg|dlc036_songs_of_exploration"
    "MusicPlayer_eu4_soe_asettlement2|music/soe_asettlement2.ogg|dlc036_songs_of_exploration"
    "MusicPlayer_eu4_soe_canzonelabavara|music/soe_canzonelabavara.ogg|dlc036_songs_of_exploration"
    "MusicPlayer_eu4_gds_eire|music/037_eire.ogg|dlc037_guns_drums_and_steel_volume_2"
    "MusicPlayer_eu4_gds_mykingdom|music/037_mykingdom.ogg|dlc037_guns_drums_and_steel_volume_2"
    "MusicPlayer_eu4_kairis_emperors_road|music/Emperors_Road.ogg|dlc044_kairis_soundtrack"
    "MusicPlayer_eu4_kairis_forest_shade|music/Forest_Shade.ogg|dlc044_kairis_soundtrack"
    "MusicPlayer_eu4_kairis_jade_ambitions|music/Jade_Ambitions.ogg|dlc044_kairis_soundtrack"
    "MusicPlayer_eu4_ksp2_eastern_fronts|music/ksp2_eastern_fronts.ogg|dlc059_kairis_soundtrack_part_2"
    "MusicPlayer_eu4_ksp2_peace_for_generations|music/ksp2_peace_for_generations.ogg|dlc059_kairis_soundtrack_part_2"
    "MusicPlayer_eu4_ksp2_temple_ambitions|music/ksp2_temple_ambitions.ogg|dlc059_kairis_soundtrack_part_2"
    "MusicPlayer_eu4_ksp2_the_grasslands_call|music/ksp2_the_grasslands_call.ogg|dlc059_kairis_soundtrack_part_2"
    "MusicPlayer_eu4_ksp2_the_great_wall|music/ksp2_the_great_wall.ogg|dlc059_kairis_soundtrack_part_2"
    "MusicPlayer_eu4_sormp_a_golden_sun_is_rising|music/sormp_A_Golden_Sun_is_Rising_Ambient.ogg|dlc063_songs_of_regency"
    "MusicPlayer_eu4_sormp_for_honour_and_glory|music/sormp_For_Honour_and_Glory_War.ogg|dlc063_songs_of_regency"
    "MusicPlayer_eu4_rus_a_russian_heart|music/ruamp_a_russian_heart.ogg|dlc076_the_rus_awaken"
    "MusicPlayer_eu4_rus_following_the_volga|music/ruamp_following_the_volga.ogg|dlc076_the_rus_awaken"
    "MusicPlayer_eu4_rus_iwans_dream|music/ruamp_iwans_dream.ogg|dlc076_the_rus_awaken"
    "MusicPlayer_eu4_kott_faith_restored|music/Faith_Restored.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes"
    "MusicPlayer_eu4_kott_homebound|music/Homebound.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes"
    "MusicPlayer_eu4_kott_peace_cannot_last|music/Peace_Cannot_Last.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes"
    "MusicPlayer_eu4_kott_sundered_hills|music/Sundered_Hills.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes"
    "MusicPlayer_eu4_kott_whispers_dark|music/Whispers_in_the_Dark.ogg|dlc081_kairis_soundtrack_3_ottoman_tunes"
    "MusicPlayer_eu4_brit_alba|music/Alba.ogg|dlc089_rule_britannia_music_pack"
    "MusicPlayer_eu4_brit_battle_in_the_highlands|music/A_Battle_in_the_Highlands.ogg|dlc089_rule_britannia_music_pack"
    "MusicPlayer_eu4_brit_piper_lead_your_clansmen|music/Piper_Lead_Your_Clansmen.ogg|dlc089_rule_britannia_music_pack"
    "MusicPlayer_eu4_dharma_carnatic|music/Carnatic.ogg|dlc094_dharma_music"
    "MusicPlayer_eu4_dharma_hindustani|music/Hindustani.ogg|dlc094_dharma_music"
    "MusicPlayer_eu4_dharma_rajastani|music/Rajastani.ogg|dlc094_dharma_music"
    "MusicPlayer_eu4_gc_birth_of_global_empire|music/birth_of_a_global_empire.ogg|dlc099_golden_century_music"
    "MusicPlayer_eu4_gc_conflict_in_the_caribbean|music/conflict_in_the_caribbean.ogg|dlc099_golden_century_music"
    "MusicPlayer_eu4_gc_march_on_granada|music/march_on_granada.ogg|dlc099_golden_century_music"
    "MusicPlayer_eu4_emp_empire_divided|music/anempiredivided.ogg|dlc105_emperor_music"
    "MusicPlayer_eu4_emp_birthplace_of_renaissance|music/birthplaceofrenaissance.ogg|dlc105_emperor_music"
    "MusicPlayer_eu4_emp_duality_of_faith|music/dualityoffaith.ogg|dlc105_emperor_music"
    "MusicPlayer_eu4_na_american_soil|music/american_soil.ogg|dlc108_north_america_music"
    "MusicPlayer_eu4_na_cautious_preparation|music/cautious_preparation.ogg|dlc108_north_america_music"
    "MusicPlayer_eu4_na_signs_of_victory|music/signs_of_victory.ogg|dlc108_north_america_music"
    "MusicPlayer_eu4_sea_discoveries_revealed|music/discoveries_revealed.ogg|dlc109_south_east_asia_music"
    "MusicPlayer_eu4_sea_undisclosed_tactics|music/undisclosed_tactics.ogg|dlc109_south_east_asia_music"
    "MusicPlayer_eu4_sea_undiscovered_territory|music/undiscovered_territory.ogg|dlc109_south_east_asia_music"
    "MusicPlayer_eu4_waf_new_destiny_awaits|music/a_new_destiny_awaits.ogg|dlc112_west_african_music_pack"
    "MusicPlayer_eu4_waf_into_the_wild|music/into_the_wild.ogg|dlc112_west_african_music_pack"
    "MusicPlayer_eu4_waf_strategy_reborn|music/strategy_reborn.ogg|dlc112_west_african_music_pack"
    "MusicPlayer_eu4_eaf_encounters_in_the_sun|music/encounters_in_the_sun_ea.ogg|dlc113_east_african_music_pack"
    "MusicPlayer_eu4_eaf_neverending_dunes|music/neverending_dunes.ogg|dlc113_east_african_music_pack"
    "MusicPlayer_eu4_eaf_the_long_walk|music/the_long_walk_ea.ogg|dlc113_east_african_music_pack"
    "MusicPlayer_eu4_gds3_aarle|music/aarle.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_after_the_rain|music/after_the_rain.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_darkness_falls|music/darkness_falls.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_demons|music/demons.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_kettil|music/kettil.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_last_stand|music/last_stand.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_legends_north|music/legends_of_the_north.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_over_seas|music/over_seas.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_ravens|music/ravens.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_the_conqueror|music/the_conqueror.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_voices|music/voices.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_gds3_whispering_forest|music/whispering_forest.ogg|dlc114_guns_drums_and_steel_volume_3"
    "MusicPlayer_eu4_scan_battle_of_scandinavia|music/battle_of_scandinavia.ogg|dlc117_scandinavian_music_pack"
    "MusicPlayer_eu4_scan_lands_of_midnight_sun|music/lands_of_midnight_sun.ogg|dlc117_scandinavian_music_pack"
    "MusicPlayer_eu4_scan_united_we_stand|music/united_we_stand.ogg|dlc117_scandinavian_music_pack"
    "MusicPlayer_eu4_balt_crowned_in_tallin|music/crowned_in_tallin.ogg|dlc118_baltics_music_pack"
    "MusicPlayer_eu4_balt_knights_of_swords|music/knights_of_swords.ogg|dlc118_baltics_music_pack"
    "MusicPlayer_eu4_balt_rise_of_the_balts|music/rise_of_the_balts.ogg|dlc118_baltics_music_pack"
    "MusicPlayer_eu4_ott_conquest_of_constantinople|music/conquest_of_constantinople.ogg|dlc121_ottoman_music_pack"
    "MusicPlayer_eu4_ott_redrawing_the_map|music/redrawing_the_map.ogg|dlc121_ottoman_music_pack"
    "MusicPlayer_eu4_ott_suleiman_the_magnificent|music/suleiman_the_magnificent.ogg|dlc121_ottoman_music_pack"
    "MusicPlayer_eu4_chi_path_of_the_dragon|music/path_of_the_dragon.ogg|dlc122_chinese_music_pack"
    "MusicPlayer_eu4_chi_ports_of_china|music/ports_of_china.ogg|dlc122_chinese_music_pack"
    "MusicPlayer_eu4_chi_staff_of_the_emperor|music/staff_of_the_emperor.ogg|dlc122_chinese_music_pack"
    "MusicPlayer_eu4_fr_a_new_king_arrives|music/a_new_king_arrives.ogg|dlc123_french_music_pack"
    "MusicPlayer_eu4_fr_castle_of_versailles|music/castle_of_versailles.ogg|dlc123_french_music_pack"
    "MusicPlayer_eu4_fr_le_premier_jour|music/le_premier_jour.ogg|dlc123_french_music_pack"
    "MusicPlayer_eu4_ann_brief_history|music/a_brief_history_of_everything.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_world_to_explore|music/a_world_to_explore.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_all_roads_rome|music/all_roads_lead_to_rome.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_back_motherland|music/back_to_the_motherland.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_clara_umbra|music/clara_umbra.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_dawn_empire|music/dawn_of_an_empire.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_in_taverns|music/in_taverns_and_great_halls.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_into_beyond|music/into_the_beyond.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_one_world|music/one_world.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_ann_conquistador|music/the_conquistador.ogg|dlc127_10th_anniversary"
    "MusicPlayer_eu4_egy_blue_nile|music/blue_nile.ogg|dlc130_egyptian_music_pack"
    "MusicPlayer_eu4_egy_fates_of_the_desert|music/fates_of_the_desert.ogg|dlc130_egyptian_music_pack"
    "MusicPlayer_eu4_per_battles_on_persian_borders|music/battles_on_persian_borders.ogg|dlc131_persian_music_pack"
    "MusicPlayer_eu4_per_harbors_of_the_caspian_sea|music/harbors_of_the_caspian_sea.ogg|dlc131_persian_music_pack"
    "MusicPlayer_eu4_cau_battle_of_kakheti|music/battle_of_kakheti.ogg|dlc132_caucasian_music_pack"
    "MusicPlayer_eu4_cau_caucasus_mountains|music/caucasus_mountains.ogg|dlc132_caucasian_music_pack"
    "MusicPlayer_eu4_hre_continuation_diplomacy|music/a_continuation_of_diplomacy.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_autumn_aachen|music/autumn_in_aachen.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_charlemagne_legacy|music/charlemange_s_legacy.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_election_habsburg|music/election_of_a_habsburg.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_imperial_diet|music/imperial_diet.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_life_shadow_kingdom|music/life_under_the_shadow_kingdom.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_ninety_five_theses|music/ninety_five_theses.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_rise_loyal_subjects|music/now_rise_my_loyal_subjects.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_order_diplomacy|music/order_and_diplomacy.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_hre_prussian_ambitions|music/prussian_ambitions.ogg|dlc133_utopia_hre_music_pack"
    "MusicPlayer_eu4_ksp3_blood_old_gods|music/blood_of_the_old_gods.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_city_worlds_desire|music/city_of_the_world_s_desire.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_crossing_seas|music/crossing_the_seas.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_eastern_mists|music/eastern_mists.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_fine_day_sacrifice|music/fine_day_for_sacrifice.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_gaelic_summers|music/gaelic_summers.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_hundred_years_war|music/hundred_years_war.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_la_bataille_iberia|music/la_bataille_de_iberia.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_march_empire|music/march_for_the_empire.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_old_families|music/old_families.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_prelude_march|music/prelude_s_march.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_shogunate_fall|music/the_shogunate_will_fall.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_ksp3_siege_of_vienna|music/the_siege_of_vienna.ogg|dlc134_kairis_soundtrack_part_3"
    "MusicPlayer_eu4_natam_aztec_theme|music/aztec_theme.ogg|dlc138_native_america_music_pack"
    "MusicPlayer_eu4_natam_inca_theme|music/inca_theme.ogg|dlc138_native_america_music_pack"
    "MusicPlayer_eu4_cas_hordes_centralasian|music/hordes_centralasian.ogg|dlc139_central_asia_music_pack"
    "MusicPlayer_eu4_cas_mughal_indian_persian|music/mughal_indian_persian.ogg|dlc139_central_asia_music_pack"
    "MusicPlayer_eu4_ce_austria_theme|music/austria_theme.ogg|dlc140_central_europe_music_pack"
    "MusicPlayer_eu4_ce_hungary_theme|music/hungary_theme.ogg|dlc140_central_europe_music_pack"
)

# --- FUNCTIONS ---------------------------------------------

function Write-Status($msg) { Write-Host "[EU4 Soundtrack] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)     { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)    { Write-Host "[X]  $msg" -ForegroundColor Red }

function Get-WemId([string]$EventName) {
    [uint64]$h = 2166136261
    [uint64]$mask = 4294967295
    [uint64]$mul  = 16777619
    foreach ($c in ($EventName + "_wem").ToLower().ToCharArray()) {
        $h = ($h * $mul) -band $mask
        $h = $h -bxor [uint64][byte][char]$c
    }
    return [uint32]$h
}

function Find-EU4Path {
    $candidates = @(
        "$env:ProgramFiles(x86)\Steam\steamapps\common\Europa Universalis IV",
        "C:\Program Files (x86)\Steam\steamapps\common\Europa Universalis IV",
        "D:\Steam\steamapps\common\Europa Universalis IV",
        "D:\SteamLibrary\steamapps\common\Europa Universalis IV",
        "E:\Steam\steamapps\common\Europa Universalis IV",
        "E:\SteamLibrary\steamapps\common\Europa Universalis IV",
        "F:\SteamLibrary\steamapps\common\Europa Universalis IV"
    )
    foreach ($p in $candidates) {
        if (Test-Path "$p\eu4.exe") { return $p }
    }
    # Check registry
    try {
        $reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 236850" -EA Stop
        if (Test-Path "$($reg.InstallLocation)\eu4.exe") { return $reg.InstallLocation }
    } catch {}
    return $null
}

function Find-WwiseConsole {
    $searchDirs = @(
        'C:\Audiokinetic',
        'D:\Audiokinetic',
        "$env:ProgramFiles\Audiokinetic",
        "${env:ProgramFiles(x86)}\Audiokinetic"
    )
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        $exe = Get-ChildItem "$dir\Wwise_*\Authoring\x64\Release\bin\WwiseConsole.exe" `
               -EA SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

function Find-Ogg([string]$SourceOgg, [string]$DlcDir, [string]$Eu4Path) {
    if (-not $DlcDir) {
        # Base game
        $p = "$Eu4Path\music\$SourceOgg"
        if (Test-Path $p) { return $p }
    } else {
        # DLC zip
        $dlcPath = "$Eu4Path\dlc\$DlcDir"
        if (-not (Test-Path $dlcPath)) { return $null }
        $zips = Get-ChildItem "$dlcPath\*.zip" -EA SilentlyContinue
        foreach ($zip in $zips) {
            $tmpExtract = "$env:TEMP\eu4snd_extract"
            try {
                Add-Type -Assembly System.IO.Compression.FileSystem -EA SilentlyContinue
                $zf = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
                $entry = $zf.Entries | Where-Object { $_.FullName -like "*$SourceOgg" } | Select-Object -First 1
                if ($entry) {
                    $outPath = "$tmpExtract\$($entry.Name)"
                    New-Item -ItemType Directory -Force $tmpExtract | Out-Null
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $outPath, $true)
                    $zf.Dispose()
                    return $outPath
                }
                $zf.Dispose()
            } catch {}
        }
    }
    return $null
}

function Convert-Track([string]$OggPath, [string]$WemPath, [string]$WwiseConsole) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($WemPath)
    New-Item -ItemType Directory -Force $WwiseTmpDir | Out-Null
    $wavPath     = "$WwiseTmpDir\$stem.wav"
    $wsourcePath = "$WwiseTmpDir\$stem.wsources"
    $outDir      = "$WwiseTmpDir\${stem}_out"

    # OGG - WAV
    $r = & ffmpeg -y -i $OggPath -ar 48000 -ac 2 -acodec pcm_s16le $wavPath 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Warn "ffmpeg failed for $stem"; return $false }

    # Use existing Wwise project (must exist at $WwiseProjDir)
    $proj = "$WwiseProjDir\eu4mod.wproj"
    if (-not (Test-Path $proj)) { Write-Warn "Wwise project not found: $proj"; return $false }

    # wsources XML
    $wsourcesXml = ("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n" +
        "<ExternalSourcesList SchemaVersion=`"1`" Root=`"$WwiseTmpDir`">`r`n" +
        "    <Source Path=`"$stem.wav`" Conversion=`"Vorbis Quality High`"/>`r`n" +
        "</ExternalSourcesList>")
    $wsourcesXml | Set-Content $wsourcePath -Encoding UTF8

    # WAV - WEM
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $wwOut = & $WwiseConsole convert-external-source $proj --source-file $wsourcePath --output $outDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "WwiseConsole failed (exit $LASTEXITCODE) for $stem"
        Write-Warn ($wwOut | Out-String)
        return $false
    }

    # Find output WEM - search broadly
    $wem = Get-ChildItem "$outDir\Windows\*.wem" -EA SilentlyContinue | Select-Object -First 1
    if (-not $wem) { $wem = Get-ChildItem "$outDir" -Recurse -Filter "*.wem" -EA SilentlyContinue | Select-Object -First 1 }
    if (-not $wem) {
        # Show what IS there for debugging
        $files = Get-ChildItem $outDir -Recurse -EA SilentlyContinue | Select-Object -First 5
        Write-Warn "WEM not found in $outDir. Contents: $($files.Name -join ', ')"
        return $false
    }

    Copy-Item $wem.FullName $WemPath -Force
    Remove-Item $wavPath,$wsourcePath -EA SilentlyContinue
    Remove-Item $outDir -Recurse -Force -EA SilentlyContinue
    return $true
}

function Sync-FromGitHub {
    Write-Status "Checking for mod updates..."
    $files = @(
        "loading_screen/sound/banks/windows/eu4_soundtrack_music.bnk",
        "loading_screen/sound/banks/windows/eu4_soundtrack_media.bnk",
        "loading_screen/sound/banks/windows/SoundbanksInfo.json",
        ".metadata/metadata.json",
        "descriptor.mod",
        "wwise_project/eu4mod.wproj",
        "wwise_project/Conversion Settings/Default Work Unit.wwu",
        "wwise_project/Conversion Settings/Factory Conversion Settings.wwu"
    )
    $updated = 0
    foreach ($f in $files) {
        $dest = "$ModDir\$f"
        $url  = "$GitHubRaw/$f"
        $dir  = Split-Path $dest
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        try {
            $tmp = "$env:TEMP\eu4snd_dl"
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 15 -EA Stop
            $newBytes = [System.IO.File]::ReadAllBytes($tmp)
            $changed = $true
            if (Test-Path $dest) {
                $oldBytes = [System.IO.File]::ReadAllBytes($dest)
                if ($newBytes.Length -eq $oldBytes.Length -and
                    [System.Linq.Enumerable]::SequenceEqual($newBytes, $oldBytes)) {
                    $changed = $false
                }
            }
            if ($changed) {
                Copy-Item $tmp $dest -Force
                $updated++
            }
        } catch { Write-Warn "Could not download $($f): $_" }
    }
    if ($updated -gt 0) { Write-Ok "$updated file(s) updated from GitHub" }
    else { Write-Ok "All mod files up to date" }
}

# --- MAIN --------------------------------------------------

Write-Host ""
Write-Host "  EU4 Soundtrack for EU5" -ForegroundColor White
Write-Host "  ---------------------" -ForegroundColor DarkGray
Write-Host ""

# 1. Sync bank files from GitHub
Sync-FromGitHub

# 2. Find tools
Write-Status "Locating tools..."
$eu4Path = Find-EU4Path
if (-not $eu4Path) { Write-Warn "EU4 not found in common Steam paths. Set EU4 path manually." }
else { Write-Ok "EU4: $eu4Path" }

$ffmpeg = Get-Command ffmpeg -EA SilentlyContinue
if (-not $ffmpeg) {
    $ffpaths = @("$env:ProgramFiles\\ffmpeg\\bin\\ffmpeg.exe",
        'C:\\ffmpeg\\bin\\ffmpeg.exe','C:\\ffmpeg\\ffmpeg.exe')
    foreach ($p in $ffpaths) { if (Test-Path $p) { $ffmpeg = Get-Item $p; break } }
    if (-not $ffmpeg) {
        $wg = "$env:LOCALAPPDATA\\Microsoft\\WinGet\\Packages"
        if (Test-Path $wg) { $ffmpeg = Get-ChildItem "$wg\\Gyan.FFmpeg*\\**\\ffmpeg.exe" -Recurse -EA SilentlyContinue | Select-Object -First 1 }
    }
}
if (-not $ffmpeg) { Write-Err 'FFmpeg not found! Run: winget install ffmpeg  OR add to PATH' }
else { Write-Ok "FFmpeg found" }
$wwiseConsole = Find-WwiseConsole
if (-not $wwiseConsole) { Write-Err "Wwise not found! Download free from: https://audiokinetic.com/download/" }
else { Write-Ok "Wwise: $wwiseConsole" }

# 3. Check & convert missing tracks
if ($eu4Path -and $ffmpeg -and $wwiseConsole) {
    New-Item -ItemType Directory -Force $MediaDir | Out-Null
    
    $missing = @()
    foreach ($track in $Tracks) {
            if ($null -eq $track -or $track -notmatch "\|") { continue }
        $parts = $track -split "\|"
        $eventName = $parts[0]
        $wemId     = Get-WemId $eventName
        $wemPath   = "$MediaDir\$wemId.wem"
        if (-not (Test-Path $wemPath)) { $missing += $track }
    }

    if ($missing.Count -eq 0) {
        Write-Ok "All $($Tracks.Count) tracks ready!"
    } else {
        # Parallel conversion (N jobs = half of CPU cores, min 2, max 8)
        $maxJobs = [Math]::Max(2, [Math]::Min(8, [Environment]::ProcessorCount / 2))
        Write-Status "Converting $($missing.Count) missing track(s) ($maxJobs parallel jobs)..."

        # Build work list (only tracks with OGG found)
        $workList = @()
        foreach ($track in $missing) {
            $parts = $track -split "\|"
            $eventName = $parts[0]; $srcOgg = $parts[1]
            $dlcDir = if ($parts.Count -gt 2 -and $parts[2] -ne "") { $parts[2] } else { $null }
            $wemId   = Get-WemId $eventName
            $wemPath = "$MediaDir\$wemId.wem"
            $oggPath = Find-Ogg $srcOgg $dlcDir $eu4Path
            if ($oggPath) {
                $workList += [PSCustomObject]@{
                    EventName=$eventName; OggPath=$oggPath; WemPath=$wemPath
                }
            }
        }

        # Parallel runner using jobs
        $convertScript = {
            param($OggPath, $WemPath, $WwiseConsole, $WwiseProjDir, $WwiseTmpDir)
            $stem   = [System.IO.Path]::GetFileNameWithoutExtension($WemPath)
            $jid    = [System.Threading.Thread]::CurrentThread.ManagedThreadId
            $tmpDir = "$WwiseTmpDir\job_${jid}_$stem"
            New-Item -ItemType Directory -Force $tmpDir | Out-Null
            $wavPath = "$tmpDir\$stem.wav"
            $wsPath  = "$tmpDir\$stem.wsources"
            $outDir  = "$tmpDir\out"
            try {
                & ffmpeg -y -i $OggPath -ar 48000 -ac 2 -acodec pcm_s16le $wavPath 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { return $false }
                $proj = "$WwiseProjDir\eu4mod.wproj"
                if (-not (Test-Path $proj)) { return $false }
                ("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n" +
                 "<ExternalSourcesList SchemaVersion=`"1`" Root=`"$tmpDir`">`r`n" +
                 "    <Source Path=`"$stem.wav`" Conversion=`"Vorbis Quality High`"/>`r`n" +
                 "</ExternalSourcesList>") | Set-Content $wsPath -Encoding UTF8
                New-Item -ItemType Directory -Force $outDir | Out-Null
                $out = & $WwiseConsole convert-external-source $proj --source-file $wsPath --output $outDir 2>&1
                if ($LASTEXITCODE -ne 0) { return $false }
                $wem = Get-ChildItem $outDir -Recurse -Filter "*.wem" -EA SilentlyContinue | Select-Object -First 1
                if (-not $wem) { return $false }
                Copy-Item $wem.FullName $WemPath -Force
                return $true
            } finally {
                Remove-Item $tmpDir -Recurse -Force -EA SilentlyContinue
            }
        }

        $jobs = @(); $done = 0; $failed = 0; $idx = 0
        while ($idx -lt $workList.Count -or $jobs.Count -gt 0) {
            # Start new jobs up to limit
            while ($jobs.Count -lt $maxJobs -and $idx -lt $workList.Count) {
                $item = $workList[$idx++]
                Write-Host "  [+] $($item.EventName)" -ForegroundColor DarkCyan
                $job = Start-Job -ScriptBlock $convertScript `
                    -ArgumentList $item.OggPath,$item.WemPath,$wwiseConsole,$WwiseProjDir,$WwiseTmpDir
                $jobs += [PSCustomObject]@{Job=$job; Name=$item.EventName}
            }
            # Check completed jobs
            $remaining = @()
            foreach ($j in $jobs) {
                if ($j.Job.State -in 'Completed','Failed','Stopped') {
                    $result = Receive-Job $j.Job -EA SilentlyContinue
                    Remove-Job $j.Job -Force
                    if ($result -eq $true) { $done++ } else { $failed++; Write-Warn "Failed: $($j.Name)" }
                } else { $remaining += $j }
            }
            $jobs = $remaining
            if ($jobs.Count -ge $maxJobs -or ($idx -ge $workList.Count -and $jobs.Count -gt 0)) {
                Start-Sleep -Milliseconds 500
            }
        }
        $skipped = $missing.Count - $workList.Count
        Write-Ok "Done: $done  Failed: $failed  Skipped (no DLC): $skipped"
    }
} elseif (-not $eu4Path) {
    Write-Warn "Skipping conversion - EU4 not found"
} else {
    Write-Warn "Skipping conversion - install missing tools above"
}

# 4. Launch EU5
Write-Host ""
if ($LaunchCmd) {
    Write-Status "Launching EU5... ($LaunchCmd)"
    # Try multiple launch methods
    try {
        # Method 1: Invoke directly (works when LaunchCmd is a simple path)
        $exe = ($LaunchCmd -split '"')[1]
        $args = $LaunchCmd.Substring($LaunchCmd.IndexOf('"', $LaunchCmd.IndexOf('"')+1)+1).Trim()
        if ($exe -and (Test-Path $exe)) {
            Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden
        } else {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$LaunchCmd`"" -WindowStyle Hidden
        }
    } catch {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c $LaunchCmd" -WindowStyle Hidden
    }
} else {
    Write-Status "Launch EU5 from Steam."
}

Write-Host ""
Start-Sleep -Seconds 3
