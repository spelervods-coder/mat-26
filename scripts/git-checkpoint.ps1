param(
  [Parameter(Mandatory=$true)]
  [string]$Message
)

# Fix Windows "dubious ownership" issue (safe to run every time)
$repoPath = (Get-Location).Path
git config --global --add safe.directory $repoPath | Out-Null

git add -A
$staged = git diff --cached --stat

if ([string]::IsNullOrWhiteSpace($staged)) {
  Write-Host "Nothing to commit - working tree matches last commit." -ForegroundColor Yellow
  exit 0
}

Write-Host "`nStaged changes:" -ForegroundColor Cyan
Write-Host $staged

git commit -m $Message

if ($LASTEXITCODE -eq 0) {
  Write-Host "`nCommitted: $Message" -ForegroundColor Green
  git push origin main
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Pushed to GitHub." -ForegroundColor Green
  } else {
    Write-Host "Push failed - if this is your first push, try:" -ForegroundColor Red
    Write-Host "  git push -u origin main" -ForegroundColor Yellow
    Write-Host "If remote has unrelated commits (README etc), try:" -ForegroundColor Red
    Write-Host "  git pull origin main --allow-unrelated-histories" -ForegroundColor Yellow
  }
} else {
  Write-Host "Commit failed - check errors above." -ForegroundColor Red
}
