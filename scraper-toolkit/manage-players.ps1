# manage-players.ps1
# Interactive menu: list, add, edit, or remove players in players.json.
# (add-player.ps1 still works too, for a quick single add without the menu.)

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\players.json")) {
  Write-Host "ERROR: players.json not found in current folder. Run from scraper-toolkit\." -ForegroundColor Red
  exit 1
}

function Load-Players {
  return Get-Content ".\players.json" -Raw | ConvertFrom-Json
}

function Save-Players($json) {
  $jsonText = $json | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText((Resolve-Path ".\players.json"), $jsonText, (New-Object System.Text.UTF8Encoding $false))
}

function List-Players($json) {
  Write-Host ""
  $i = 0
  foreach ($p in $json.players) {
    Write-Host "[$i] $($p.playerName) (id=$($p.cardId))"
    $i++
  }
  Write-Host ""
}

function Add-PlayerInteractive($json) {
  Write-Host "--- Add player ---" -ForegroundColor Cyan
  $playerName = Read-Host "Player name"
  $cardId   = Read-Host "Card ID (fut.gg itemId / futwiz Card ID)"
  $futbinUrl  = Read-Host "FUTBIN URL"
  $futggUrl   = Read-Host "FUT.GG URL"
  $futwizUrl  = Read-Host "FUTWIZ URL"
  $futnextUrl = Read-Host "FutNext URL"

  $newPlayer = [PSCustomObject]@{
    playerName = $playerName
    playerId   = $cardId
    urls       = [PSCustomObject]@{
      futbin  = $futbinUrl
      futgg   = $futggUrl
      futwiz  = $futwizUrl
      futnext = $futnextUrl
    }
  }
  $json.players = @($json.players) + $newPlayer
  Save-Players $json
  Write-Host "Added $playerName." -ForegroundColor Green
  return $json
}

function Edit-PlayerInteractive($json) {
  List-Players $json
  $idxInput = Read-Host "Which number to edit? (blank to cancel)"
  if (-not $idxInput) { return $json }
  $idx = [int]$idxInput
  if ($idx -lt 0 -or $idx -ge $json.players.Count) { Write-Host "Invalid index." -ForegroundColor Red; return $json }

  $p = $json.players[$idx]
  Write-Host "Editing $($p.playerName) - press Enter to keep the current value" -ForegroundColor Cyan

  $v = Read-Host "Player name [$($p.playerName)]";      if ($v) { $p.playerName = $v }
  $v = Read-Host "Player ID [$($p.cardId)]";           if ($v) { $p.cardId = $v }
  $v = Read-Host "FUTBIN URL [$($p.urls.futbin)]";       if ($v) { $p.urls.futbin = $v }
  $v = Read-Host "FUT.GG URL [$($p.urls.futgg)]";        if ($v) { $p.urls.futgg = $v }
  $v = Read-Host "FUTWIZ URL [$($p.urls.futwiz)]";       if ($v) { $p.urls.futwiz = $v }
  $v = Read-Host "FutNext URL [$($p.urls.futnext)]";     if ($v) { $p.urls.futnext = $v }

  Save-Players $json
  Write-Host "Updated $($p.playerName)." -ForegroundColor Green
  return $json
}

function Remove-PlayerInteractive($json) {
  List-Players $json
  $idxInput = Read-Host "Which number to remove? (blank to cancel)"
  if (-not $idxInput) { return $json }
  $idx = [int]$idxInput
  if ($idx -lt 0 -or $idx -ge $json.players.Count) { Write-Host "Invalid index." -ForegroundColor Red; return $json }

  $removed = $json.players[$idx]
  $confirm = Read-Host "Remove $($removed.playerName)? (y/n)"
  if ($confirm -eq "y") {
    $json.players = @($json.players | Where-Object { $_.playerId -ne $removed.playerId })
    Save-Players $json
    Write-Host "Removed $($removed.playerName)." -ForegroundColor Green
  }
  return $json
}

$json = Load-Players
$loop = $true
while ($loop) {
  Write-Host ""
  Write-Host "--- Player Manager ($($json.players.Count) players) ---" -ForegroundColor Cyan
  Write-Host "1) List players"
  Write-Host "2) Add player"
  Write-Host "3) Edit player"
  Write-Host "4) Remove player"
  Write-Host "5) Exit"
  $choice = Read-Host "Choice"
  switch ($choice) {
    "1" { List-Players $json }
    "2" { $json = Add-PlayerInteractive $json }
    "3" { $json = Edit-PlayerInteractive $json }
    "4" { $json = Remove-PlayerInteractive $json }
    "5" { $loop = $false }
    default { Write-Host "Invalid choice." -ForegroundColor Red }
  }
}
