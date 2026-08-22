# watch-positions.ps1
# Checks output/positions.json every minute for listings older than 60
# minutes that haven't been marked sold/expired yet, and alerts you.
# Uses a real Windows toast notification if the BurntToast module is
# installed, otherwise falls back to a console beep + message (works
# either way - no hard dependency).
#
# Run in a SEPARATE terminal window, alongside scheduler.ps1.
#
# Optioneel voor nette meldingen:
#   Install-Module BurntToast -Scope CurrentUser

param(
  [int]$CheckIntervalSeconds = 60,
  [int]$ListingMinutes = 60
)

$hasBurntToast = Get-Module -ListAvailable -Name BurntToast

function Notify($title, $message) {
  if ($hasBurntToast) {
    Import-Module BurntToast -ErrorAction SilentlyContinue
    New-BurntToastNotification -Text $title, $message
  } else {
    [console]::beep(800, 300)
    Write-Host "`n🔔 $title" -ForegroundColor Yellow
    Write-Host "   $message" -ForegroundColor Yellow
  }
}

Write-Host "Watching positions.json for overdue listings (elke $CheckIntervalSeconds sec, drempel $ListingMinutes min)..." -ForegroundColor Cyan
if (-not $hasBurntToast) {
  Write-Host "Tip: 'Install-Module BurntToast -Scope CurrentUser' voor echte Windows-notificaties i.p.v. alleen een pieptoon." -ForegroundColor Yellow
}
Write-Host "Ctrl+C om te stoppen.`n" -ForegroundColor Cyan

$alreadyNotified = @{}

while ($true) {
  if (Test-Path ".\output\positions.json") {
    try {
      $positions = Get-Content ".\output\positions.json" -Raw | ConvertFrom-Json
      foreach ($prop in $positions.PSObject.Properties) {
        $pos = $prop.Value
        if ($pos.status -ne "open") { continue }
        $lastEvent = $pos.events[-1]
        if ($lastEvent.action -eq "list" -or $lastEvent.action -eq "relist") {
          $listedAt = [datetime]$lastEvent.timestamp
          $minutesAgo = (Get-Date).ToUniversalTime().Subtract($listedAt.ToUniversalTime()).TotalMinutes
          $key = "$($pos.positionId)-$($lastEvent.timestamp)"
          if ($minutesAgo -ge $ListingMinutes -and -not $alreadyNotified.ContainsKey($key)) {
            $shortId = $pos.positionId.Substring(0, 8)
            Notify "Listing verlopen: $($pos.playerName)" "Gelist voor $($lastEvent.price) - check: node index.js sold $($pos.cardId) <prijs>  of  node index.js expired $($pos.cardId)"
            $alreadyNotified[$key] = $true
          }
        }
      }
    } catch {
      Write-Host "⚠️  Kon positions.json niet lezen: $_" -ForegroundColor Red
    }
  }
  Start-Sleep -Seconds $CheckIntervalSeconds
}
