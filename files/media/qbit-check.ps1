<#
qbit-check.ps1 - read-only checks for qBittorrent on Windows behind a VPN app.

Run on: the Windows PC that runs qBittorrent, in PowerShell, as the same user that runs
qBittorrent (the settings file is per user):

    powershell -ExecutionPolicy Bypass -File .\qbit-check.ps1
    powershell -ExecutionPolicy Bypass -File .\qbit-check.ps1 -VpnAdapter "ProtonVPN" -SavePath "M:\Downloads" -MediaServer 192.168.50.2

-VpnAdapter is the VPN app's adapter name as shown by Get-NetAdapter (or the start of it).
"ProtonVPN" is only an example; other VPN apps name their adapter differently.

It changes nothing and prints no passwords. Parse-checked only: not yet run by the author.
Written for Windows 10/11 and Windows Server 2019/2022 with qBittorrent 5.x.
#>
param(
  [string]$VpnAdapter  = "ProtonVPN",      # the VPN app's adapter name (or its start); example only
  [string]$SavePath    = "M:\Downloads",   # qBittorrent default save path
  [int]   $WebUiPort   = 8080,
  [string]$MediaServer = "192.168.50.2"    # the Mac running Sonarr/Radarr (must reach the Web UI)
)

$script:fail = 0; $script:warn = 0
function Ok($m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Warn($m) { $script:warn++; Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Bad($m)  { $script:fail++; Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Hdr($m)  { Write-Host "`n== $m" }

Hdr "qBittorrent process"
$p = Get-Process -Name qbittorrent -ErrorAction SilentlyContinue
if ($p) { Ok "running (PID $($p.Id -join ', '))" } else { Bad "qbittorrent.exe is not running" }

$ini = Join-Path $env:APPDATA "qBittorrent\qBittorrent.ini"
$cfg = @{}
if (Test-Path $ini) {
  Ok "settings file $ini"
  foreach ($line in Get-Content $ini) {
    if ($line -match '^\s*([^=;\[]+?)\s*=\s*(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
  }
} else { Warn "no settings file at $ini (running as a different user or as a service?)" }

function Cfg($k) { if ($cfg.ContainsKey($k)) { $cfg[$k] } else { $null } }

Hdr "VPN binding"
$ad = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$VpnAdapter*" -or $_.InterfaceDescription -like "*$VpnAdapter*" }
if ($ad) {
  foreach ($a in $ad) {
    if ($a.Status -eq 'Up') { Ok "adapter '$($a.Name)' is Up" } else { Warn "adapter '$($a.Name)' is $($a.Status) (VPN disconnected?)" }
  }
} else { Bad "no network adapter matching '$VpnAdapter' (is the VPN app installed and connected?)" }

$ifName = Cfg 'Session\InterfaceName'; if (-not $ifName) { $ifName = Cfg 'Connection\InterfaceName' }
$ifId   = Cfg 'Session\Interface';     if (-not $ifId)   { $ifId   = Cfg 'Connection\Interface' }
if ($ifName -or $ifId) {
  if ("$ifName" -like "$VpnAdapter*") { Ok "qBittorrent is bound to '$ifName' (no traffic if the VPN drops)" }
  else { Bad "qBittorrent is bound to '$ifName' not '$VpnAdapter' (Tools > Options > Advanced > Network interface)" }
} else { Bad "qBittorrent is not bound to an interface: if the VPN drops, torrents use the normal connection" }

Hdr "Save path"
$sp = Cfg 'Session\DefaultSavePath'; if (-not $sp) { $sp = Cfg 'Downloads\SavePath' }
if ($sp) { Ok "default save path in settings: $sp" }
if (Test-Path $SavePath) { Ok "$SavePath is reachable" } else { Bad "$SavePath is not reachable (mapped drive not reconnected after login?)" }
$drive = Split-Path -Qualifier $SavePath -ErrorAction SilentlyContinue
if ($drive) {
  $m = Get-CimInstance Win32_MappedLogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -eq $drive }
  if ($m) { Ok "$drive is mapped to $($m.ProviderName)" } else { Warn "$drive is not a mapped network drive for this user (services cannot see mapped drives; use a UNC path there)" }
}
$tmm = Cfg 'Session\DisableAutoTMMByDefault'
if ($tmm -eq 'true' -or -not $tmm) { Warn "Automatic Torrent Management is off by default: category folders are not used" }

Hdr "Web UI"
$l = Get-NetTCPConnection -LocalPort $WebUiPort -State Listen -ErrorAction SilentlyContinue
if ($l) { Ok "listening on $(($l.LocalAddress | Sort-Object -Unique) -join ', '):$WebUiPort" } else { Bad "nothing listening on TCP $WebUiPort (Web UI off?)" }
$fw = Get-NetFirewallPortFilter -Protocol TCP -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq "$WebUiPort" } | Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' }
if ($fw) { Ok "inbound firewall rule allows TCP $WebUiPort ($($fw.DisplayName -join '; '))" } else { Warn "no enabled inbound rule for TCP $WebUiPort found by port (a program rule for qbittorrent.exe may still allow it)" }
if ((Cfg 'WebUI\UseUPnP') -eq 'true' -or (Cfg 'WebUI\UPnP') -eq 'true') { Warn "Web UI UPnP is on: it asks the router to forward the Web UI port to the internet (Options > Web UI > Use UPnP / NAT-PMP)" }
if ((Cfg 'WebUI\AuthSubnetWhitelistEnabled') -eq 'true') { Ok "auth bypass whitelist is on (subnets not printed; check Options > Web UI)" }

Hdr "Reachability from this PC"
if (Test-NetConnection -ComputerName $MediaServer -Port 8989 -InformationLevel Quiet -WarningAction SilentlyContinue) { Ok "media server $MediaServer answers on 8989 (LAN works while the VPN is up)" }
else { Warn "cannot reach ${MediaServer}:8989 from here (VPN blocking the LAN? turn on 'Allow LAN connections' in the VPN app)" }

Hdr "Seeding limits"
if ((Cfg 'Session\GlobalMaxRatio') -and [double](Cfg 'Session\GlobalMaxRatio') -ge 0) { Ok "ratio limit set: $(Cfg 'Session\GlobalMaxRatio')" }
else { Warn "no ratio limit: torrents seed forever, and Sonarr/Radarr 'Remove Completed' never triggers" }

Write-Host "`nSummary: $script:fail failures, $script:warn warnings"
exit $script:fail
