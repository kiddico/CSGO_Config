@(set ^ "f0=%temp%\CS2.ps1" -desc ')|| Counter-Strike 2 launcher - AveYo, 2024.10.30
@(fc %0 "%f0%"||copy /y /b %0+nul "%f0%")>nul 2>&1& start "@" conhost powershell -nop -ep RemoteSigned -f "%f0%"& exit /b '); . {
<#
  match screen resolution before starting the game, to alleviate input lag, alt-tab & secondary screen issues
  once the game is closed, restores the previous resolution
  + game starts on screen with mouse pointer on and can seamlessly move between displays even if not set as primary & left
  + clear steam verify game integrity after a crash to relaunch quicker; toggle fso
  + unify settings for all users in game\csgo\cfg dir (also helps preserve settings when offline)
  + optionally force specific video settings at every launch
#>

#:: override resolution: no -1 max 0 |  if not appearing in res list, create the custom res in gpu driver settings / cru
#:: good custom res for [4:3] = 1080x810  1280x960  1440x1080   [16:10] = 1296x810  1440x900   [16:9] = 1440x810  1632x918
$force_width     = -1
$force_height    = -1
$force_refresh   = -1

#:: unify settings for all users in game\csgo\cfg dir: yes 1 no 0
$unify_cfg       =  1

#:: override video settings with the preset below: yes 1 no 0  
$force_settings  =  1

#:: override specific video settings - prefix with # lines to remain unchanged (adjust those in-game and relaunch)
$video = @{                                                           #        Shadow of a Potato preset        more jpeg:
  "setting.mat_vsync"                                = "0"            #  0     enable vsync in gpu driver instead
# "setting.msaa_samples"                             = "0"            #  2     should enable AA when using FSR           0
# "setting.r_csgo_cmaa_enable"                       = "0"            #  0     use msaa 2 instead                         
# "setting.videocfg_shadow_quality"                  = "0"            #  0     shadows high: 2 | med: 1 | low: 0          
  "setting.videocfg_dynamic_shadows"                 = "1"            #  1     must have for competitive play            0
# "setting.videocfg_texture_detail"                  = "0"            #  0     texture high: 2 | med: 1 | low: 0          
# "setting.r_texturefilteringquality"                = "3"            #  3     anyso16x: 5 | anyso4x: 3 | trilinear: 1   0
# "setting.shaderquality"                            = "0"            #  0     smooth shadows fps--                       
# "setting.videocfg_particle_detail"                 = "0"            #  0     smooth smokes fps--
# "setting.videocfg_ao_detail"                       = "0"            #  0     ambient oclussion fps--
# "setting.videocfg_hdr_detail"                      = "3"            #  -1    HDR quality: -1 | performance 8bit noise: 3
# "setting.videocfg_fsr_detail"                      = "0"            #  0     FSR quality: 2 | balanced: 3 | minecraft: 4
  "setting.r_low_latency"                            = "1"            #  1
}
$machine = @{
# "r_fullscreen_gamma"                               = "2.2"          #  2.2   brightness slider - works on windowed too now
# "r_player_visibility_mode"                         = "0"            #  0     kinda useless
# "r_drawtracers_firstperson"                        = "0"            #  0     tracers
  "engine_no_focus_sleep"                            = "0"            #  20    power saving while alt-tab
  "trusted_launch"                                   = "1"            #  1     trusted launch tracking
  "r_show_build_info"                                = "1"            #  1     build info is a must when reporting issues
}
$extra_launch_options = @()
$extra_launch_options+= '+cl_input_enable_raw_keyboard 0'             #  prevent keyboard issues
#$extra_launch_options+= '-allow_third_party_software'                #  uncomment if recording via obs game capture
#$extra_launch_options+= '-consolelog cfg\console.log'                #  uncomment to autosave cfg\console.log

#:: override fullscreen mode: exclusive 1 desktop-friendly 0
$force_exclusive =  0

#:: override fullscreen optimizations (FSO): enable 1 disable 0
$enable_fso      =  0

#:: override screen or use current -1 | this is 1st number in the screen list; second number is for -sdl_displayindex
$force_screen    = -1

#:: set to 1 to wait for external launcher to start the game (ex. gamersclub br) - not needed for faceit web
$external_launcher = 0

#:: override script handling or use default 0
$do_not_set_desktop_res_to_match_game = 0
$do_not_restore_res_use_max_available = 0
$do_not_hide_script_window_on_waiting = 0

#:: main script section --------------------------------------------------------------------- switch syntax highlight to powershell
$APPID      = 730
$APPNAME    = "cs2"
$INSTALLDIR = "Counter-Strike Global Offensive"
$MOD        = "csgo"
$GAMEBIN    = "bin\win64"
$USER_VCFG  = "${APPNAME}_user_convars_0_slot0.vcfg"
$KEYS_VCFG  = "${APPNAME}_user_keys_0_slot0.vcfg"
$MACH_VCFG  = "${APPNAME}_machine_convars.vcfg"
$VIDEO_TXT  = "${APPNAME}_video.txt"

#:: copy-pasted directly into powershell? then do not hide window
if (!$MyInvocation.ScriptName) { $do_not_hide_script_window_on_waiting = 1 }

#:: check if already opened
$c = 'HKCU:\Console\@'; ni $c -ea 0 >''; sp $c ScreenColors 0x0b -type dword -ea 0; sp $c QuickEdit 0 -type dword -ea 0
ps | where {$_.MainWindowTitle -eq "$APPNAME launcher"} | kill; $host.ui.RawUI.WindowTitle = "$APPNAME launcher"
if (ps $APPNAME -ea 0) { write-host " $APPNAME is running " -fore Black -back Yellow; sleep 3; exit 0 }

#:: detect STEAM and specific APP
$STEAM = resolve-path (gpv "HKCU:\SOFTWARE\Valve\Steam" SteamPath)
gc "$STEAM\steamapps\libraryfolders.vdf" |foreach  {$_ -split '"',5} |where {$_ -like '*:\\*'} |foreach {
  $l = resolve-path $_; $i = "$l\steamapps\common\$INSTALLDIR"; if (test-path "$i\game\$MOD\steam.inf") {
  $STEAMAPPS = "$l\steamapps"; $GAMEROOT = "$i\game"; $GAME = "$i\game\$MOD"
}}

#:: detect per-user data path
pushd "$STEAM\userdata"
$USRCLOUD = split-path (dir "localconfig.vdf" -File -Recurse | sort LastWriteTime -Descending | Select -First 1).DirectoryName
$USRLOCAL = "$USRCLOUD\$APPID\local"
popd

#:: unify settings for all users in game\csgo\cfg dir
$USRLOCALCSGO_U  = [Environment]::GetEnvironmentVariable("USRLOCALCSGO",1)
$USRLOCALCSGO_M  = [Environment]::GetEnvironmentVariable("USRLOCALCSGO",2)
$USRLOCALCSGO_Ub = ($USRLOCALCSGO_U -and (test-path "$USRLOCALCSGO_U\cfg\$MACH_VCFG")) 
$USRLOCALCSGO_Mb = ($USRLOCALCSGO_M -and (test-path "$USRLOCALCSGO_M\cfg\$MACH_VCFG"))
if ($unify_cfg -eq 0) {
  if ($USRLOCALCSGO_Mb) {
    $USRLOCAL = $USRLOCALCSGO_M
    write-host " USRLOCALCSGO is defined at machine level. unable to override cfg location" -fore Yellow
  }
  elseif ($USRLOCALCSGO_Ub) {
    [Environment]::SetEnvironmentVariable("USRLOCALCSGO","",0)
    [Environment]::SetEnvironmentVariable("USRLOCALCSGO","",1)
    robocopy "$USRLOCALCSGO_U\cfg/" "$USRCLOUD\$APPID\local\cfg/" *.txt *.cfg *.vcfg /XO >''
    if (ps "Steam" -ea 0) {
      write-host " will try closing Steam to refresh USRLOCAL gamevar" -fore Yellow
      start "$STEAM\Steam.exe" -args '-shutdown' -wait; sleep 5
    }
  }
}
if ($unify_cfg -eq 1) { 
  if ($USRLOCALCSGO_Mb) {
    $USRLOCAL = "$USRLOCALCSGO_M"
  }
  elseif ($USRLOCALCSGO_Ub -and $USRLOCALCSGO_U -eq "$GAME") {
    $USRLOCAL = "$GAME"
    [Environment]::SetEnvironmentVariable("USRLOCALCSGO","$GAME",0)
    [Environment]::SetEnvironmentVariable("USRLOCALCSGO","$GAME",1)
    robocopy "$USRCLOUD\$APPID\local\cfg/" "$GAME\cfg/" *.vcfg *video*.txt /XO >''
    robocopy "$USRCLOUD\$APPID\local/" "$GAME/" socache.dt /XO >''
  }  
  else {
    $USRLOCAL = "$GAME"
    [Environment]::SetEnvironmentVariable("USRLOCALCSGO","$GAME",0)
    [Environment]::SetEnvironmentVariable("USRLOCALCSGO","$GAME",1)
    if ($USRLOCALCSGO_Ub) {
      robocopy "$USRLOCALCSGO_U\cfg/" "$GAME\cfg/" *.vcfg *video*.txt /XO >''
      robocopy "$USRLOCALCSGO_U/" "$GAME/" socache.dt /XO >''
    }
    if (ps "Steam" -ea 0) {
      write-host " will try closing Steam to refresh USRLOCAL gamevar" -fore Yellow
      start "$STEAM\Steam.exe" -args '-shutdown' -wait; sleep 5
    }
  }
}

#:: generate a blank autoexec.cfg if not already found
if (-not (test-path "$GAME\cfg\autoexec.cfg")) { sc "$GAME\cfg\autoexec.cfg" "" }

#:: decide which sets of video options overrides to use: script has priority, then launch options, then cfg
$exclusive = 0; $screen = 0; $width = 0; $height = 0; $refresh = 0; $numer = -1; $denom = -1

#:: parse video txt file
$video_config = "$USRLOCAL\cfg\$VIDEO_TXT"
if ($video_config -ne '') {
  $lines = (gc $video_config); $txt = $lines -join "`n"
  if ($txt -match '"setting.fullscreen"\s+"([^"]*)"')              { $exclusive = [int]$matches[1] }
  if ($txt -match '"setting.monitor_index"\s+"([^"]*)"')           { $screen    = [int]$matches[1] }
  if ($txt -match '"setting.defaultres"\s+"([^"]*)"')              { $width     = [int]$matches[1] }
  if ($txt -match '"setting.defaultresheight"\s+"([^"]*)"')        { $height    = [int]$matches[1] }
  if ($txt -match '"setting.refreshrate_numerator"\s+"([^"]*)"')   { $numer     = [int]$matches[1] }
  if ($txt -match '"setting.refreshrate_denominator"\s+"([^"]*)"') { $denom     = [int]$matches[1] }
  #:: compute numerator / denominator = refresh for video txt file
  if ($numer -gt 0 -and $denom -gt 0) { $refresh = [decimal]$numer / $denom }
}

#:: parse game launch options
$lo = (gc "$USRCLOUD\config\localconfig.vdf") -join "`n"
$lo = (($lo -split '\n\s{5}"' + $APPID + '"\n\s{5}{\n')[1] -split '\n\s{5}}\n')[0]
$lo = (($lo -split '\n\s{6}"LaunchOptions"\s+"')[1] -split '"\n')[0]
if ($lo -ne '') {
  if ($lo -match '-fullscreen\s+')            { $exclusive = 1 }
  if ($lo -match '-sdl_displayindex\s+(\d+)') { $screen    = [int]$matches[1] }
  if ($lo -match '-w(idth)?\s+(\d+)')         { $width     = [int]$matches[2] }
  if ($lo -match '-h(eight)?\s+(\d+)')        { $height    = [int]$matches[2] }
  if ($lo -match '-r(efresh)?\s+([\d.]+)')    { $refresh   = [decimal]$matches[2] }
}

#:: script overrides
if ($force_exclusive -ge 0) { $exclusive = $force_exclusive }
if ($force_screen -ge 0)    { $screen    = $force_screen }
if ($force_width -ge 0)     { $width     = $force_width }
if ($force_height -ge 0)    { $height    = $force_height }
if ($force_refresh -ge 0)   { $refresh   = $force_refresh }
if ($refresh -gt 0) {
  $hz = ([string]$refresh).Split('.'); $denom = 1000
  if ($hz.length -eq 2) { $numer = [int]($hz[0] + $hz[1].PadRight(3,'0')) } else { $numer = [int]($hz[0] + "000") }
}

#:: set screen resolution via SetRes before launching the game, to alleviate input lag, alt-tab and secondary screens issues
$library1 = "SetRes"; $version1 = "2024.3.10.0"; $about1 = "set screen resolution"; $path1 = "$env:APPDATA\AveYo\$library1.dll"
<# usage:
  [SetRes.Displays]::Change(output=[0:none 1:def], screen, width, height, refresh=[0:def], test=[0:change 1:test])
  [SetRes.Displays]::List(output=[0:none 1:filter 2:all], screen, minw=[1024], maxw=[16384], maxh=[16384])
  returns array of: sdl_idx, screen, current_width, current_height, current_refresh, max_width, max_height, max_refresh
  the c# typefinition at the end of the script gets pre-compiled rather than let powershell do it slowly every launch #>
if ((gi $path1 -force -ea 0).VersionInfo.FileVersion -ne $version1) { del $path1 -force -ea 0 } ; if (-not (test-path $path1)) {
  mkdir "$env:APPDATA\AveYo" -ea 0 >'' 2>''; pushd $env:APPDATA\AveYo; " one-time initialization of $library1 library..."
  [io.file]::WriteAllText("$env:APPDATA\AveYo\$library1.cs", ($MyInvocation.MyCommand -split '<#[:]LIBRARY1[:].*')[1])
  $csc = join-path $([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
  start $csc -args "/out:$library1.dll /target:library /platform:anycpu /optimize /nologo $library1.cs" -nonew -wait; popd
}
Import-Module $path1
$display = [SetRes.Displays]::Init($screen)
$sdl_idx = $display[0];  $screen = $display[1];  $primary = $display[2] -gt 0;  $multimon = $display[3] -gt 1

#:: restore previous resolution if game was not gracefully closed last time
if ($do_not_set_desktop_res_to_match_game -le 0 -and (test-path "$GAME\cfg\SetRes.cfg")) {
  $restore = (gc "$GAME\cfg\SetRes.cfg") -split ','
  if ($null -eq (ps $APPNAME -ea 0)) {
    $c = [SetRes.Displays]::Change(0, $restore[1], $restore[2], $restore[3], $restore[4])
  }
}

#:: SetRes automatically picks a usable mode if the change is invalid so result might differ from the request
$oldres  = [SetRes.Displays]::List(1, $screen)
if ($width   -le 0) { $width  = $oldres[2] }
if ($height  -le 0) { $height = $oldres[3] }
if ($refresh -le 0) { $max_refresh = [SetRes.Displays]::List(0, $screen, $width, $width, $height); $refresh = $max_refresh[7] }
$newres  = [SetRes.Displays]::Change(1, $screen, $width, $height, $refresh, 1)
$width   = $newres[5]; $restore_width   = $newres[2]
$height  = $newres[6]; $restore_height  = $newres[3]
$refresh = $newres[7]; $restore_refresh = $newres[4]
function max {$r = [SetRes.Displays]::Change(1, $oldres[1], $oldres[5], $oldres[6], $oldres[7])} # console command to set max res
function min {$r = [SetRes.Displays]::Change(1, $oldres[1], 1024,       768,        $oldres[7])} # console command to set min res
if ($do_not_restore_res_use_max_available -ge 1) {
  $restore_width = $oldres[5]; $restore_height = $oldres[6]; $restore_refresh = $oldres[7]
}
$sameres = $width -eq $restore_width -and $height -eq $restore_height -and $refresh -eq $restore_refresh
$ratio   = $width / $height
if ($ratio -le 4/3) {$ar = 0} elseif ($ratio -le 16/10) {$ar = 2} elseif ($ratio -le 16/8.9) {$ar = 1} else {$ar = 3}
$mode = "{0,4} x {1,4} {2,3}Hz" -f ($width, $height, $refresh) 
$rend = ('Desktop-friendly','Exclusive')[$exclusive -gt 0] + (' + FSO','')[$enable_fso -eq 0]

#::  many thanks to /u/wazernet for testing and suggestions
write-host " $screen $mode $rend mode requested" -fore Yellow

#:: update video overrides in case the initial mode was invalid and SetRes applied a fallback
if ($force_settings -le 0) { $video = @{} }
$video["setting.fullscreen"]                   = (0,1)[$exclusive -eq 1]
$video["setting.coop_fullscreen"]              = (0,1)[$exclusive -ne 1]
$video["setting.nowindowborder"]               = 1
$video["setting.fullscreen_min_on_focus_loss"] = 0
$video["setting.monitor_index"]                = $sdl_idx
$video["setting.defaultres"]                   = $width
$video["setting.defaultresheight"]             = $height
$video["setting.refreshrate_numerator"]        = $refresh
$video["setting.refreshrate_denominator"]      = 1
$video["setting.aspectratiomode"]              = $ar

#:: update cfg files with the overrides
$video_config = "$USRLOCAL\cfg\$VIDEO_TXT"
if (-not (test-path $video_config)) {sc $video_config "`"video.cfg`"`n{`n`t`"Version`"`t`t`"13`"`n}`n" -force -ea 0 }
if ((test-path $video_config) -and $force_settings -ge 1) {
  $lines = (gc $video_config); $txt = $lines -join "`n"; $cfg = new-object System.Text.StringBuilder # dos line-endings
  foreach ($k in $video.Keys) {
    if ($k -like 'setting.*' -and $txt -notmatch "`"$k`"") { $cfg.Append("`r`n`t`"$k`"`t`t`"$($video.$k)`"")>'' }
  }
  if ($cfg.length -gt 0) { -1..-10 |foreach { if ($lines[$_] -match "^}$") { $lines[$_ - 1] += $cfg.ToString(); return } } }
  if ($cfg.length -gt 0) {sc $video_config $lines -force -ea 0 }
  (gc $video_config) |foreach {
    foreach ($k in $video.Keys) { if ($_ -like "*$k`"*") {
      $_ = $_ -replace "(`"$k`"\s+)(`"[^`"]*`")","`$1`"$($video.$k)`"" } }; $_ } | sc $video_config -force -ea 0
}
$machine_config = "$USRLOCAL\cfg\$MACH_VCFG"
if (-not (test-path $machine_config)) {sc $machine_config "`"config`"`n{`n`t`"convars`"`n`t{`n`t`t`n`t}`n}`n" -force -ea 0 }
if ((test-path $machine_config) -and $force_settings -ge 1) {
  $lines = (gc $machine_config); $txt = $lines -join "`n"; $cfg = new-object System.Text.StringBuilder # unix line-endings
  foreach ($k in $machine.Keys) { if ($txt -notmatch "`"$k`"") { $cfg.Append("`n`t`t`"$k`"`t`t`"$($machine.$k)`"")>'' } }
  if ($cfg.length -gt 0) { -1..-10 |foreach { if ($lines[$_] -match "^\s}$") { $lines[$_ - 1] += $cfg.ToString(); return } } }
  if ($cfg.length -gt 0) { sc $machine_config (($lines -join "`n") + "`n") -noNewLine -force -ea 0 }
  (gc $machine_config) |foreach {
    foreach ($k in $machine.Keys) { if ($_ -like "*$k`"*") {
      $_ = $_ -replace "(`"$k`"\s+)(`"[^`"]*`")","`$1`"$($machine.$k)`"" } }; $_ } | sc $machine_config -force -ea 0
}
if ($unify_cfg -gt 0 -and $USRLOCAL -ne "$USRCLOUD\$APPID\local") {
  robocopy "$USRLOCAL\cfg/" "$USRCLOUD\$APPID\local\cfg/" *convars.vcfg *slot0.vcfg *video*.txt /XO >''
}

#:: clear verify integrity flags after a crash for quicker relaunch
$appmanifest="$STEAMAPPS\appmanifest_$APPID.acf"
if (test-path $appmanifest) {
  $ACF = [io.file]::ReadAllText($appmanifest)
  if ($ACF -match '"FullValidateAfterNextUpdate"\s+"1"' -or $ACF -notmatch '"StateFlags"\s+"4"') {
    write-host " update or verify integrity flags detected, will clear them and restart Steam...`n" -fore Yellow
    'dota2','cs2','steamwebhelper','steam' |foreach {kill -name $_ -force -ea 0} ; sleep 3; del "$STEAM\.crash" -force -ea 0
    $ACF = $ACF -replace '("FullValidateAfterNextUpdate"\s+)("\d+")',"`$1`"0`"" -replace '("StateFlags"\s+)("\d+")',"`$1`"4`""
    [io.file]::WriteAllText($appmanifest, $ACF)
  }
} else {
  write-host " $appmanifest missing or wrong lib path detected! continuing with a default manifest...`n" -fore Yellow
  $blank = "`"AppState`"`n{`n`"AppID`" `"$APPID`"`n`"Universe`" `"1`"`n`"installdir`" `"$INSTALLDIR`"`n`"StateFlags`" `"4`"`n}`n"
  sc $appmanifest $blank -force
}

#:: toggle fullscreen optimizations for game launcher - FSO as a concept is an abomination - ofc it causes input lag
$progr = "$GAMEROOT\$GAMEBIN\$APPNAME.exe"
$flags = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$found = (gi $flags -ea Ignore).Property -contains $progr
$valid = $found -and (gpv $flags $progr) -like '*DISABLEDXMAXIMIZEDWINDOWEDMODE*'
if ($enable_fso -eq 0 -and (!$found -or !$valid)) {
  write-host " disabling $APPNAME os fullscreen (un)optimizations"
  ni $flags -ea 0; sp $flags $progr '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' -force -ea 0
}
if ($enable_fso -eq 1 -and $valid) {rp $flags $progr -force -ea 0}

#:: prepare video launch options
$window = @("-force_allow_coop_fullscreen -coop_fullscreen", "-force_allow_excl_fullscreen -fullscreen")[$exclusive -ge 1]
$video_options = "$window -noborder -width $width -height $height -refresh $refresh -sdl_displayindex $sdl_idx "
write-host " $video_options`n" -fore Green
write-host " $GAMEROOT\$GAMEBIN\$APPNAME.exe" -fore Gray
write-host " $GAME\cfg\autoexec.cfg" -fore Gray
write-host " $video_config" -fore Gray
#pause

#:: prepare steam quick options
$quick = '-quicklogin -vgui -oldtraymenu -vrdisable -nofriendsui -skipstreamingdrivers -silent '
$quick+= '-cef-force-occlusion -cef-single-process -cef-disable-gpu -no-dwrite -forceservice'
$steam_options = "$quick -applaunch $APPID $video_options $extra_launch_options "

#:: here you can insert anything to run before starting the game like start "some\program" -args "etc";

#:: start game (and steam if not already running)
if ($external_launcher -le 0) {
  write-host "`n waiting for Steam to start $($APPNAME.ToUpper())... `t too long? run script again" -fore Yellow
  powershell.exe -nop -c "Start-Process \`"$STEAM\steam.exe\`" \`"$steam_options\`""
} else {
  write-host "`n waiting for external launcher to start $($APPNAME.ToUpper())... `t too long? run script again" -fore Yellow
}

#:: restore res after game closes if it was changed
if ($do_not_set_desktop_res_to_match_game -le 0 -and -not $sameres) {
  sc "$GAME\cfg\SetRes.cfg" "$sdl_idx,$screen,$restore_width,$restore_height,$restore_refresh,`r`n" -force -ea 0
  "`n will restore res to $restore_width x $restore_height ${restore_refresh}Hz after $($APPNAME.ToUpper()) closes..."
  while ($null -eq ($wait = ps $APPNAME -ea 0)) { sleep -m 250 }
  $change  = [SetRes.Displays]::Change(1, $screen, $width, $height, $refresh)
  if ($do_not_hide_script_window_on_waiting -le 0) { sleep 3; powershell -win 1 -nop -c ';' }
  while (-not $wait.HasExited) { sleep 5 }
  $restore = [SetRes.Displays]::Change(1, $screen, $restore_width, $restore_height, $restore_refresh)
  del "$GAME\cfg\SetRes.cfg" -force -ea 0
} else {
  #:: change even if res matches, to address a rare bug where game starts in a blank window and can only \ q-tab enter out of it
  $change  = [SetRes.Displays]::Change(1, $screen, $restore_width, $restore_height, $restore_refresh)
}
" can enter: max for $($oldres[5])x$($oldres[6]) or: min for 1024x768 if needed"

#:: here you can insert anything to run after game is closed like start "some\program" -args "etc";

#:: done, script closes
if ($do_not_hide_script_window_on_waiting -ge 1) { return }
[Environment]::Exit(0)

<#:LIBRARY1: start <# ------------------------------------------------------------------------------ switch syntax highlight to C#
/// SetRes - loosely based on code by Rick Strahl
using System; using System.Runtime.InteropServices; using System.Collections.Generic; using System.Linq; using System.Reflection;
[assembly:AssemblyVersion("2024.3.10.0")] [assembly: AssemblyTitle("AveYo")]
namespace SetRes
{
  public static class Displays
  {
    private const short CCDEVICENAME = 32,  CCFORMNAME  = 32;

    public const int SUCCESS       = 0,  ENUM_CURRENT  = -1,  MONITOR_DEFAULTTONEAREST = 0x00000002;
    public const int DMDFO_DEFAULT = 0,  DMDFO_STRETCH =  1,  DMDFO_CENTER = 2;
    public const int DMDO_DEFAULT  = 0,  DMDO_90       =  1,  DMDO_180     = 2,  DMDO_270 = 3;

    [Flags()]
    private enum EdsFlags : int
    {
      EDS_ATTACHEDTODESKTOP = 0x00000001,  EDS_MULTIDRIVER   = 0x00000002,  EDS_PRIMARYDEVICE = 0x00000004,
      EDS_MIRRORINGDRIVER   = 0x00000008,  EDS_VGACOMPATIBLE = 0x00000010,  EDS_REMOVABLE     = 0x00000020,
      EDS_MODESPRUNED       = 0x08000000,  EDS_REMOTE        = 0x04000000,  EDS_DISCONNECT    = 0x02000000
    }

    [Flags()]
    private enum CdsFlags : uint
    {
      CDS_NONE            = 0x00000000,  CDS_UPDATEREGISTRY      = 0x00000001,  CDS_TEST                 = 0x00000002,
      CDS_FULLSCREEN      = 0x00000004,  CDS_GLOBAL              = 0x00000008,  CDS_SET_PRIMARY          = 0x00000010,
      CDS_VIDEOPARAMETERS = 0x00000020,  CDS_ENABLE_UNSAFE_MODES = 0x00000100,  CDS_DISABLE_UNSAFE_MODES = 0x00000200,
      CDS_RESET           = 0x40000000,  CDS_RESET_EX            = 0x20000000,  CDS_NORESET              = 0x10000000
    }

    [Flags()]
    private enum DmFlags : int
    {
      DM_ORIENTATION   = 0x00000001,  DM_PAPERSIZE          = 0x00000002,  DM_PAPERLENGTH        = 0x00000004,
      DM_PAPERWIDTH    = 0x00000008,  DM_SCALE              = 0x00000010,  DM_POSITION           = 0x00000020,
      DM_NUP           = 0x00000040,  DM_DISPLAYORIENTATION = 0x00000080,  DM_COPIES             = 0x00000100,
      DM_DEFAULTSOURCE = 0x00000200,  DM_PRINTQUALITY       = 0x00000400,  DM_COLOR              = 0x00000800,
      DM_DUPLEX        = 0x00001000,  DM_YRESOLUTION        = 0x00002000,  DM_TTOPTION           = 0x00004000,
      DM_COLLATE       = 0x00008000,  DM_FORMNAME           = 0x00010000,  DM_LOGPIXELS          = 0x00020000,
      DM_BITSPERPEL    = 0x00040000,  DM_PELSWIDTH          = 0x00080000,  DM_PELSHEIGHT         = 0x00100000,
      DM_DISPLAYFLAGS  = 0x00200000,  DM_DISPLAYFREQUENCY   = 0x00400000,  DM_ICMMETHOD          = 0x00800000,
      DM_ICMINTENT     = 0x01000000,  DM_MEDIATYPE          = 0x02000000,  DM_DITHERTYPE         = 0x04000000,
      DM_PANNINGWIDTH  = 0x08000000,  DM_PANNINGHEIGHT      = 0x10000000,  DM_DISPLAYFIXEDOUTPUT = 0x20000000
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINTL { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int left; public int top; public int right; public int bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DISPLAY_DEVICE
    {
      [MarshalAs(UnmanagedType.U4)]                       public int      cb;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)]  public string   DeviceName;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string   DeviceString;
      [MarshalAs(UnmanagedType.U4)]                       public EdsFlags StateFlags;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string   DeviceID;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string   DeviceKey;
      public void Initialize()
      {
        this.DeviceName   = new string(new char[32]);
        this.DeviceString = new string(new char[128]);
        this.DeviceID     = new string(new char[128]);
        this.DeviceKey    = new string(new char[128]);
        this.cb           = Marshal.SizeOf(this);
      }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DEVMODE
    {
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=CCDEVICENAME)]
                                    public string  dmDeviceName;
      [MarshalAs(UnmanagedType.U2)] public ushort  dmSpecVersion;
      [MarshalAs(UnmanagedType.U2)] public ushort  dmDriverVersion;
      [MarshalAs(UnmanagedType.U2)] public ushort  dmSize;
      [MarshalAs(UnmanagedType.U2)] public ushort  dmDriverExtra;
      [MarshalAs(UnmanagedType.U4)] public DmFlags dmFields;
                                    public POINTL  dmPosition;
      [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayOrientation;
      [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayFixedOutput;
      [MarshalAs(UnmanagedType.I2)] public short   dmColor;
      [MarshalAs(UnmanagedType.I2)] public short   dmDuplex;
      [MarshalAs(UnmanagedType.I2)] public short   dmYResolution;
      [MarshalAs(UnmanagedType.I2)] public short   dmTTOption;
      [MarshalAs(UnmanagedType.I2)] public short   dmCollate;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst=CCFORMNAME)]
                                    public string  dmFormName;
      [MarshalAs(UnmanagedType.U2)] public ushort  dmLogPixels;
      [MarshalAs(UnmanagedType.U4)] public uint    dmBitsPerPel;
      [MarshalAs(UnmanagedType.U4)] public uint    dmPelsWidth;
      [MarshalAs(UnmanagedType.U4)] public uint    dmPelsHeight;
      [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayFlags;
      [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayFrequency;
      [MarshalAs(UnmanagedType.U4)] public uint    dmICMMethod;
      [MarshalAs(UnmanagedType.U4)] public uint    dmICMIntent;
      [MarshalAs(UnmanagedType.U4)] public uint    dmMediaType;
      [MarshalAs(UnmanagedType.U4)] public uint    dmDitherType;
      [MarshalAs(UnmanagedType.U4)] public uint    dmReserved1;
      [MarshalAs(UnmanagedType.U4)] public uint    dmReserved2;
      [MarshalAs(UnmanagedType.U4)] public uint    dmPanningWidth;
      [MarshalAs(UnmanagedType.U4)] public uint    dmPanningHeight;
      public void Initialize()
      {
        this.dmDeviceName = new string(new char[CCDEVICENAME]);
        this.dmFormName   = new string(new char[CCFORMNAME]);
        this.dmSize       = (ushort)Marshal.SizeOf(this);
      }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto, Pack = 4)]
    private struct MONITORINFOEX
    {
      public uint cbSize;
      public RECT rcMonitor;
      public RECT rcWork;
      public int dwFlags;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
      public void Initialize()
      {
        this.rcMonitor = new RECT();
        this.rcWork    = new RECT();
        this.szDevice  = new string(new char[32]);
        this.cbSize    = (uint)Marshal.SizeOf(this);
      }
    }

    [DllImport("kernel32", ExactSpelling = true)] private static extern IntPtr
    GetConsoleWindow();

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    GetCursorPos(out POINTL lpPoint);

    [DllImport("user32", SetLastError = true)] private static extern IntPtr
    MonitorFromPoint(POINTL pt, int dwFlags);

    [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    GetMonitorInfo(IntPtr hMonitor, [In, Out] ref MONITORINFOEX lpmi);

    [DllImport("user32", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    EnumDisplayMonitors(IntPtr hdc, IntPtr lpRect, EnumDisplayMonitorsDelegate lpfnEnum, IntPtr dwData);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32", SetLastError=true, BestFitMapping=false, ThrowOnUnmappableChar=true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    EnumDisplaySettings(byte[] lpszDeviceName, [param: MarshalAs(UnmanagedType.U4)] int iModeNum, [In,Out] ref DEVMODE lpDevMode);

    [DllImport("user32")] private static extern int
    ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, CdsFlags dwflags, IntPtr lParam);

    //[DllImport("user32")] private static extern int
    //ChangeDisplaySettingsEx(IntPtr lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool
    SetProcessDPIAware();

    private delegate bool EnumDisplayMonitorsDelegate(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    private static IntPtr consolehWnd = GetConsoleWindow();

    public static class StringExtensions
    {
      public static byte[] ToLPTStr(string str)
      {
        return (str == null) ? null : Array.ConvertAll((str + '\0').ToCharArray(), Convert.ToByte);
      }
    }

    public class DisplayInfo
    {
      public int    Index      { get; set; }
      public int    SDLIndex   { get; set; }
      public string DeviceName { get; set; }
      public int    Height     { get; set; }
      public int    Width      { get; set; }
      public RECT   Bounds     { get; set; }
      public RECT   WorkArea   { get; set; }
      public bool   IsPrimary  { get; set; }
      public bool   IsCurrent  { get; set; }

      public override string ToString()
      {
        return string.Format("{0} {1} {2} {3} {4} ({5},{6},{7},{8}){9}{10}", Index, SDLIndex, DeviceName,
          Height, Width, Bounds.left, Bounds.top, Bounds.right, Bounds.bottom,
          IsPrimary ? " [primary]" : "", IsCurrent ? " [current]" : "");
      }
    }

    public class DisplayDevice
    {
      public int    Index        { get; set; }
      public int    MonitorIndex { get; set; }
      public int    SDLIndex     { get; set; }
      public string Id           { get; set; }
      public string DriverName   { get; set; }
      public string DisplayName  { get; set; }
      public string AdapterName  { get; set; }
      public RECT   Bounds       { get; set; }
      public bool   IsPrimary    { get; set; }
      public bool   IsCurrent    { get; set; }

      public override string ToString()
      {
        return ToString(false);
      }
      public string ToString(bool Detail)
      {
        if (Detail)
        {
          var sb = new System.Text.StringBuilder(9);
          sb.AppendFormat(" Index:        {0}\n", Index);
          sb.AppendFormat(" MonitorIndex: {0}\n", MonitorIndex);
          sb.AppendFormat(" SDLIndex:     {0}\n", SDLIndex);
          sb.AppendFormat(" Id:           {0}\n", Id);
          sb.AppendFormat(" DriverName:   {0}\n", DriverName);
          sb.AppendFormat(" DisplayName:  {0}\n", DisplayName);
          sb.AppendFormat(" AdapterName:  {0}\n", AdapterName);
          sb.AppendFormat(" Resolution:   {0} x {1}\n", Bounds.right - Bounds.left, Bounds.bottom - Bounds.top);
          sb.AppendFormat(" Bounds:       {0},{1},{2},{3}\n", Bounds.left, Bounds.top, Bounds.right, Bounds.bottom);
          sb.AppendFormat(" IsPrimary:    {0}\n", IsPrimary);
          sb.AppendFormat(" IsCurrent:    {0}\n", IsCurrent);
          return sb.ToString();
        }
        return string.Format(" {0} {1} {2} - {3}{4}{5}", MonitorIndex, SDLIndex, AdapterName, DisplayName,
          IsPrimary ? " [primary]" : "", IsCurrent ? " [current]" : "");
      }
    }

    public class DisplaySettings
    {
      public int  Index       { get; set; }
      public uint Width       { get; set; }
      public uint Height      { get; set; }
      public uint Refresh     { get; set; }
      public uint Orientation { get; set; }
      public uint FixedOutput { get; set; }

      public override string ToString()
      {
        return ToString(false);
      }

      public string ToString(bool Detail)
      {
        var culture = System.Globalization.CultureInfo.CurrentCulture;
        if (!Detail)
          return string.Format(culture, "   {0,4} x {1,4}", Width, Height);

        var degrees = Orientation == DMDO_90  ? " 90\u00b0" : Orientation == DMDO_180 ? " 180\u00b0" :
          Orientation == DMDO_270 ? " 270\u00b0" : "";
        var scaling = FixedOutput == DMDFO_CENTER ? " C" : FixedOutput == DMDFO_STRETCH ? " F" : "";
        return string.Format(culture, "   {0,4} x {1,4} {2,3}Hz {3}{4}", Width, Height, Refresh, degrees, scaling);
      }

      public override bool Equals(object d)
      {
        var disp = d as DisplaySettings;
        return (disp.Width == Width && disp.Height == Height && disp.Refresh == Refresh && disp.Orientation == Orientation);
      }

      public override int GetHashCode()
      {
        return (string.Format("W{0}H{1}R{2}O{3}", Width, Height, Refresh, Orientation)).GetHashCode();
      }
    }

    private static DEVMODE GetDeviceMode(string deviceName = null)
    {
      var mode = new DEVMODE();
      mode.Initialize();

      if (EnumDisplaySettings(StringExtensions.ToLPTStr(deviceName), ENUM_CURRENT, ref mode))
        return mode;
      else
        throw new InvalidOperationException(":(");
    }

    private static DisplaySettings CreateDisplaySettingsObject(int idx, DEVMODE mode)
    {
      return new DisplaySettings()
      {
        Index       = idx,
        Width       = mode.dmPelsWidth,
        Height      = mode.dmPelsHeight,
        Refresh     = mode.dmDisplayFrequency,
        Orientation = mode.dmDisplayOrientation,
        FixedOutput = mode.dmDisplayFixedOutput
      };
    }

    public static List<DisplayDevice> GetAllDisplayDevices()
    {
      var list = new List<DisplayDevice>();
      uint idx = 0;
      uint size = 256;
      var device = new DISPLAY_DEVICE();
      device.Initialize();

      /// AveYo: detect current monitor via cursor pointer and save Bounds rect for all
      var currentCursorP = new POINTL();
      GetCursorPos(out currentCursorP);
      var currentMonitor = MonitorFromPoint(currentCursorP, MONITOR_DEFAULTTONEAREST);
      var currentMonInfo = new MONITORINFOEX();
      currentMonInfo.Initialize();
      var currentDevice = GetMonitorInfo(currentMonitor, ref currentMonInfo) ? currentMonInfo.szDevice : "";

      var monitors = new List<DisplayInfo>();
      EnumDisplayMonitors( IntPtr.Zero, IntPtr.Zero,
        delegate (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor,  IntPtr dwData)
        {
          var mi = new MONITORINFOEX();
          mi.Initialize();
          var success = GetMonitorInfo(hMonitor, ref mi);
          if (success)
          {
            var di = new DisplayInfo();
            di.Index      = monitors.Count + 1;
            di.SDLIndex   = monitors.Count + 1;
            di.DeviceName = mi.szDevice;
            di.Width      = mi.rcMonitor.right - mi.rcMonitor.left;
            di.Height     = mi.rcMonitor.bottom - mi.rcMonitor.top;
            di.Bounds     = mi.rcMonitor;
            di.WorkArea   = mi.rcWork;
            di.IsPrimary  = (mi.dwFlags > 0);
            di.IsCurrent  = (mi.szDevice == currentDevice);
            monitors.Add(di);
          }
          return true;
        }, IntPtr.Zero
      );

      /// AveYo: calculate equivalent for sdl_displayindex to use as game launch option
      var primary = monitors.FirstOrDefault(d => d.IsPrimary == true);
      primary.SDLIndex = 0;
      if (primary.Index == 1) {
        for (var i = 1; i < monitors.Count; i++) { monitors[i].SDLIndex = i; }
      }
      else if (primary.Index <= monitors.Count - 1) {
        for (var i = primary.Index; i <= monitors.Count - 1; i++) { monitors[i].SDLIndex = i; }
      }
      //foreach (var mon in monitors) Console.WriteLine(mon.ToString());

      while (EnumDisplayDevices(null, idx, ref device, size) )
      {
        if (device.StateFlags.HasFlag(EdsFlags.EDS_ATTACHEDTODESKTOP))
        {
          var isPrimary  = device.StateFlags.HasFlag(EdsFlags.EDS_PRIMARYDEVICE);
          var isCurrent  = currentDevice != "" ? (device.DeviceName == currentDevice) : isPrimary;
          var monitor = monitors.FirstOrDefault(d => d.DeviceName == device.DeviceName);
          var deviceName = device.DeviceName; var deviceString = device.DeviceString;

          EnumDisplayDevices(device.DeviceName, 0, ref device, 0);
          var dev = new DisplayDevice()
          {
            Index        = list.Count + 1,
            MonitorIndex = monitor.Index > 0 ? monitor.Index : list.Count + 1,
            SDLIndex     = monitor.Index > 0 ? monitor.SDLIndex : list.Count + 1,
            Id           = device.DeviceID,
            DriverName   = deviceName,
            DisplayName  = device.DeviceString,
            AdapterName  = deviceString,
            Bounds       = monitor.Bounds,
            IsPrimary    = isPrimary,
            IsCurrent    = isCurrent
          };
          list.Add(dev);
        }
        idx++;
        device = new DISPLAY_DEVICE();
        device.Initialize();
      }
      return list;
    }

    public static List<DisplaySettings> GetAllDisplaySettings(string deviceName = null)
    {
      var list = new List<DisplaySettings>();
      DEVMODE mode = new DEVMODE();
      mode.Initialize();
      int idx = 0;

      while (EnumDisplaySettings(StringExtensions.ToLPTStr(deviceName), idx, ref mode))
        list.Add(CreateDisplaySettingsObject(idx++, mode));
      return list;
    }

    public static DisplaySettings GetCurrentSettings(string deviceName = null)
    {
      return CreateDisplaySettingsObject(-1, GetDeviceMode(deviceName));
    }

    public static DisplaySettings GetCurrentDisplaySetting(string deviceName = null)
    {
      var mode = GetDeviceMode(deviceName);
      return CreateDisplaySettingsObject(0, mode);
    }

    public static int[] List(int Output = 1, int Screen = -1, int MinWidth = 1024, int MaxWidth = 16384, int MaxHeight = 16384)
    {
      var devices = GetAllDisplayDevices();
      var monitor = devices.FirstOrDefault(d => d.IsCurrent);
      if (Screen > 0 && Screen <= devices.Count) monitor = devices.FirstOrDefault(d => d.MonitorIndex == Screen);

      if (Output != 0) foreach (var display in devices) Console.WriteLine(display.ToString());

      var displayModes = GetAllDisplaySettings(monitor.DriverName);
      var current      = GetCurrentDisplaySetting(monitor.DriverName);
      IList<DisplaySettings> filtered = displayModes;

      /// AveYo: MaxWidth & MaxHeight are used to aggregate the list further by Refresh rate
      if (Output == 1)
      {
        filtered = displayModes
          .Where(d => d.Width >= MinWidth && d.Width <= MaxWidth && d.Height <= MaxHeight && d.Orientation == current.Orientation)
          .OrderByDescending(d => d.Width).ThenByDescending(d => d.Refresh)
          .GroupBy(d => new {d.Width, d.Height}).Select(g => g.First()).ToList();
      }
      else if (Output == 2 || Output == 0 && MaxWidth != 16384)
      {
        filtered = displayModes
          .Where(d => d.Width >= MinWidth && d.Width <= MaxWidth && d.Height <= MaxHeight)
          .OrderByDescending(d => d.Width).ThenByDescending(d => d.Refresh).ToList();
      }

      if (filtered.Count == 0)
        filtered.Add(current);

      var max = filtered.Aggregate((top, atm) => {
          return atm.Width > top.Width || atm.Height > top.Height ? atm :
            atm.Width == top.Width && atm.Height == top.Height && atm.Refresh > top.Refresh ? atm : top;
      });

      foreach (var set in filtered)
      {
        if (set.Equals(current))
        {
          if (Output != 0) Console.WriteLine(set.ToString(true) + " [current]");
        }
        else
        {
          if (Output != 0) Console.WriteLine(set.ToString(true));
        }
      }
      if (Output != 0) Console.WriteLine();
      return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
        (int)current.Width, (int)current.Height, (int)current.Refresh, (int)max.Width, (int)max.Height, (int)max.Refresh };
    }

    public static int[] Change(int Output = 1, int Screen = -1, int Width = 0, int Height = 0, decimal Refresh = 0, int Test = 0)
    {
      var devices = GetAllDisplayDevices();
      var monitor = devices.FirstOrDefault(d => d.IsCurrent);
      if (Screen > 0 && Screen <= devices.Count) monitor = devices.FirstOrDefault(d => d.MonitorIndex == Screen);

      var deviceName = monitor.DriverName;
      var current    = GetCurrentDisplaySetting(deviceName);
      //var position = new POINTL(); position.x = monitor.Bounds.left; position.y = monitor.Bounds.top;

      if (Width == 0 || Height == 0)
      {
        if (Output != 0) Console.WriteLine(" Width and Height parameters required.\n");
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)current.Width, (int)current.Height, (int)current.Refresh, 0, 0, 0, 1 };
      }

      /// AveYo: Refresh fallback from fractional ex: 59.976 - to nearest integer ex: 60 - to highest supported
      uint Orientation = 0, FixedOutput = 0, Temporary = 0; /// for testing
      var displayModes = GetAllDisplaySettings(deviceName);
      var filtered = displayModes
        .Where(d => d.Width == Width && d.Height == Height && d.Orientation == current.Orientation)
        .OrderByDescending(d => d.Width).ThenByDescending(d => d.Refresh).ToList();

      var ref1 = filtered.FirstOrDefault(d => d.Refresh == (uint)Decimal.Truncate(Refresh));
      var ref2 = filtered.FirstOrDefault(d => d.Refresh == (uint)Decimal.Truncate(Refresh + 1));
      var set = Refresh == 0 ? filtered.FirstOrDefault() : ref1 != null ? ref1 : ref2 != null ? ref2 : filtered.FirstOrDefault();
      if (set == null)
      {
        /// AveYo: Resolution fallback to current
        if (Output != 0) Console.WriteLine(" No matching display mode!\n");
        set = current;
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)set.Width, (int)set.Height, (int)set.Refresh, (int)set.Width, (int)set.Height, (int)set.Refresh, 2 };
      }

      try
      {
        DEVMODE mode = GetDeviceMode(deviceName);
        //mode.dmPosition           = position;
        mode.dmPelsWidth          = set.Width;
        mode.dmPelsHeight         = set.Height;
        mode.dmDisplayFrequency   = set.Refresh;
        mode.dmDisplayOrientation = Orientation > 0 ? Orientation : set.Orientation;
        mode.dmDisplayFixedOutput = FixedOutput > 0 ? FixedOutput : set.FixedOutput;
        mode.dmFields             = DmFlags.DM_PELSWIDTH | DmFlags.DM_PELSHEIGHT; //DmFlags.DM_POSITION
        if (Refresh > 0)     mode.dmFields |= DmFlags.DM_DISPLAYFREQUENCY;
        if (FixedOutput > 0) mode.dmFields |= DmFlags.DM_DISPLAYORIENTATION;
        if (Temporary > 0)   mode.dmFields |= DmFlags.DM_DISPLAYFIXEDOUTPUT;

        /// AveYo: test and apply the target res even if it's the same as the current one
        CdsFlags flags = CdsFlags.CDS_TEST | CdsFlags.CDS_RESET | CdsFlags.CDS_UPDATEREGISTRY; //CdsFlags.CDS_NORESET
        if (Temporary > 0) flags |= CdsFlags.CDS_FULLSCREEN;

        int result = ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero, flags, IntPtr.Zero);
        if (Test != 0)
          return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
            (int)current.Width, (int)current.Height, (int)current.Refresh, (int)set.Width, (int)set.Height, (int)set.Refresh, 0 };
        if (result != SUCCESS)
          throw new InvalidOperationException(string.Format("{0} : {1} = N/A", set.ToString(true), monitor.DisplayName));
        flags &= ~CdsFlags.CDS_TEST;
        result = ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero, flags, IntPtr.Zero);
        if (result != SUCCESS)
          throw new InvalidOperationException(string.Format("{0} : {1} = FAIL", set.ToString(true), monitor.DisplayName));

        //ChangeDisplaySettingsEx(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        if (Output != 0) Console.WriteLine(string.Format("{0} : {1} = OK", set.ToString(true), monitor.DisplayName));
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)current.Width, (int)current.Height, (int)current.Refresh, (int)set.Width, (int)set.Height, (int)set.Refresh, 0 };
      }
      catch(Exception ex)
      {
        if (Output != 0) Console.WriteLine(ex.Message);
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)current.Width, (int)current.Height, (int)current.Refresh, 0, 0, 0, 3 };
      }
    }

    public static int[] Init(int Screen = -1)
    {
      SetProcessDPIAware(); /// AveYo: calculate using real screen values, not windows dpi scaling ones
      var devices = GetAllDisplayDevices();
      var monitor = devices.FirstOrDefault(d => d.IsCurrent);
      if (Screen > 0 && Screen <= devices.Count) monitor = devices.FirstOrDefault(d => d.MonitorIndex == Screen);
      RECT cR = new RECT(), mR = monitor.Bounds;
      GetWindowRect(consolehWnd, out cR);
      /// AveYo: move console window to Screen index or currently active
      MoveWindow(consolehWnd, mR.left + 100, mR.top + 100, cR.right - cR.left, cR.bottom - cR.top, true);
      return new int[] { monitor.SDLIndex, monitor.MonitorIndex, monitor.IsPrimary ? 1 : 0, devices.Count };
    }
  }
}
<#:LIBRARY1: end -------------------------------------------------------------------------------------------------------------- #>
} @args; return; ${ press Enter if copy-pasted in powershell }
