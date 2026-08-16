# add-player.ps1
# Interactive helper: paste the 4 URLs (+ name + playerId) for ONE player,
# appends a correctly-formatted entry to players.json. Run once per player.
#
# playerId = the EA official ID - the number that appears in BOTH the
# fut.gg URL (.../26-231747/) and the futnext URL (.../231747)

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\players.json")) {
  Write-Host "ERROR: players.json not found in current folder. Run from scraper-toolkit\." -ForegroundColor Red
  exit 1
}

Write-Host "--- Add a new player ---" -ForegroundColor Cyan
$playerName = Read-Host "Player name (e.g. Kylian Mbappe)"
$playerId   = Read-Host "Player ID (from fut.gg or futnext URL)"
$futbinUrl  = Read-Host "FUTBIN URL"
$futggUrl   = Read-Host "FUT.GG URL"
$futwizUrl  = Read-Host "FUTWIZ URL"
$futnextUrl = Read-Host "FutNext URL"

$json = Get-Content ".\players.json" -Raw | ConvertFrom-Json

$newPlayer = [PSCustomObject]@{
  playerName = $playerName
  playerId   = $playerId
  urls       = [PSCustomObject]@{
    futbin  = $futbinUrl
    futgg   = $futggUrl
    futwiz  = $futwizUrl
    futnext = $futnextUrl
  }
}

$existingIds = $json.players | ForEach-Object { $_.playerId }
if ($existingIds -contains $playerId) {
  Write-Host "WARNING: playerId $playerId already exists in players.json - adding anyway (you may want to remove the duplicate manually)." -ForegroundColor Yellow
}

$json.players = @($json.players) + $newPlayer
$json | ConvertTo-Json -Depth 10 | Set-Content ".\players.json" -Encoding UTF8

Write-Host "`nAdded $playerName (id=$playerId). Total players: $($json.players.Count)" -ForegroundColor Green
Write-Host "Run .\add-player.ps1 again for the next player." -ForegroundColor Yellow
