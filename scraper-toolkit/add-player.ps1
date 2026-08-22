# add-player.ps1
# Interactive helper: paste the 4 URLs (+ optional name + cardId) for ONE
# player, appends a correctly-formatted entry to players.json.
#
# cardId = the CARD-specific ID (FUT.GG's itemId, or FUTWIZ's Card ID) -
# NOT the same across a player's different versions (Gold Rare vs TOTW vs
# Icon all have DIFFERENT cardIds, even for the same person). This is what
# uniquely identifies the exact card you want to track.

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\players.json")) {
  Write-Host "ERROR: players.json not found in current folder. Run from scraper-toolkit\." -ForegroundColor Red
  exit 1
}

Write-Host "--- Add a new player ---" -ForegroundColor Cyan
$futbinUrl  = Read-Host "FUTBIN URL"
$futggUrl   = Read-Host "FUT.GG URL"
$futwizUrl  = Read-Host "FUTWIZ URL"
$futnextUrl = Read-Host "FutNext URL"
$cardId     = Read-Host "Card ID (from fut.gg itemId / futwiz Card ID - blank = auto-fill on first scrape)"
$playerName = Read-Host "Player name (blank = guessed from FUTBIN URL)"

if (-not $playerName) {
  # crude auto-derive from URL slug: .../player/40/kylian-mbappe/... -> "Kylian Mbappe"
  if ($futbinUrl -match '/player/\d+/([a-z0-9\-]+)') {
    $slug = $Matches[1]
    $playerName = ($slug -split '-' | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ' '
    Write-Host "  (guessed name: $playerName)" -ForegroundColor Yellow
  } else {
    $playerName = "Unknown"
  }
}

$json = Get-Content ".\players.json" -Raw | ConvertFrom-Json

$newPlayer = [PSCustomObject]@{
  playerName = $playerName
  cardId     = $cardId
  urls       = [PSCustomObject]@{
    futbin  = $futbinUrl
    futgg   = $futggUrl
    futwiz  = $futwizUrl
    futnext = $futnextUrl
  }
}

if ($cardId) {
  $existingIds = $json.players | ForEach-Object { $_.cardId }
  if ($existingIds -contains $cardId) {
    Write-Host "WARNING: cardId $cardId already exists in players.json." -ForegroundColor Yellow
  }
}

$json.players = @($json.players) + $newPlayer
$jsonText = $json | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText((Resolve-Path ".\players.json"), $jsonText, (New-Object System.Text.UTF8Encoding $false))

Write-Host "`nAdded $playerName. Total players: $($json.players.Count)" -ForegroundColor Green
if (-not $cardId) {
  Write-Host "No cardId given - it will be filled in automatically the first time this player is scraped (via 'node index.js')." -ForegroundColor Yellow
}
Write-Host "Run .\add-player.ps1 again for the next player." -ForegroundColor Yellow
