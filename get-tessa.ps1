# Tessa on Windows, step one: the public part of the installer. A new teammate pastes one line in PowerShell:
#   irm <where this file is published> | iex
# It needs nothing but Windows 10 or 11 and the GitHub invite to OneThousandPieces. It installs Git and the GitHub
# CLI, signs in to GitHub in the browser, copies otp-os to ~\GitHub\otp-os, then hands over to
# scripts\install-tessa.ps1 in that copy, which does the rest. This file is published as it is, so it holds no
# secrets and nothing about clients. Safe to run again: whatever is already done is skipped, and an existing copy is
# only updated when it's on main with nothing changed.
#   $env:TESSA_DIR = '<folder>'   put the copy somewhere else (set it before the line)
#   $env:TESSA_INSTALL_CI = '1'   a test run: stops after the copy, before anything is installed in it

# Continue, not Stop: Windows PowerShell 5.1 turns any stderr line of gh or git into a terminating error under Stop.
# Each step checks its own result instead.
$ErrorActionPreference = 'Continue'
$Org = 'OneThousandPieces'
$Repo = 'otp-os'
$Dir = if ($env:TESSA_DIR) { $env:TESSA_DIR } else { Join-Path $HOME 'GitHub\otp-os' }

function Step($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "   OK  $t" -ForegroundColor Green }
function Stop-Here($t) { Write-Host "`n$t" -ForegroundColor Red; throw 'Tessa setup stopped' }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
function Winget($id) { winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements | Out-Null; Refresh-Path }

Write-Host 'Setting up Tessa on this computer.' -ForegroundColor White -NoNewline
Write-Host ' It takes about fifteen minutes; it stops when you need to click or sign in.'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Stop-Here 'winget is missing: install "App Installer" from the Microsoft Store, open a new PowerShell and paste the line again.' }

Step '1/4  Git (Tessa''s scripts run in Git Bash)'
if (Test-Path 'C:\Program Files\Git\bin\bash.exe') { Ok 'already installed' } else {
    Write-Host '   Click Yes if Windows asks to allow changes.'
    Winget 'Git.Git'
    if (Test-Path 'C:\Program Files\Git\bin\bash.exe') { Ok 'installed' } else { Stop-Here 'Git did not install. Paste the line again; if it fails twice, send Iulian a picture of this window.' }
}

Step '2/4  The GitHub CLI (Tessa saves your work to GitHub with it)'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
if (-not (Test-Path $gh)) { $c = Get-Command gh -ErrorAction SilentlyContinue; if ($c) { $gh = $c.Source } }
if (Test-Path $gh) { Ok 'already installed' } else {
    Winget 'GitHub.cli'
    if (Test-Path 'C:\Program Files\GitHub CLI\gh.exe') { $gh = 'C:\Program Files\GitHub CLI\gh.exe'; Ok 'installed' } else { Stop-Here 'The GitHub CLI did not install. Paste the line again.' }
}

Step '3/4  Sign in to GitHub'
& $gh auth status *> $null
if ($LASTEXITCODE -eq 0) { Ok "signed in as $(& $gh api user --jq .login)" } else {
    Write-Host '   Press Enter, a browser tab opens: type the code shown below and click Authorize.'
    & $gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Stop-Here 'GitHub sign-in did not finish. Paste the line again.' }
}
& $gh auth setup-git *> $null
$login = & $gh api user --jq .login
function Get-State { $s = & $gh api "user/memberships/orgs/$Org" --jq .state 2>$null; if ($LASTEXITCODE -eq 0) { $s } else { '' } }
switch (Get-State) {
    'active' { Ok "member of $Org" }
    'pending' {
        Write-Host "   Your invite to $Org is waiting: click Join in the tab that opens. This continues by itself."
        Start-Process "https://github.com/orgs/$Org/invitation"
        while ((Get-State) -ne 'active') { Start-Sleep 5 }
        Ok "joined $Org"
    }
    default { Stop-Here "GitHub account $login isn't in $Org yet. Ask Iulian to invite $login, then paste the line again." }
}

Step '4/4  Your copy of otp-os'
if ($Dir -match 'OneDrive') { Stop-Here "$Dir is inside OneDrive, which corrupts git. Set `$env:TESSA_DIR to a plain folder (like C:\Users\you\GitHub\otp-os) and paste the line again." }
$git = 'C:\Program Files\Git\cmd\git.exe'
if (Test-Path (Join-Path $Dir '.git')) {
    $remote = & $git -C $Dir remote get-url origin
    if ($remote -notmatch "github\.com[:/]$Org/$Repo(\.git)?/?$") { Stop-Here "$Dir holds another repository. Move it away, or set `$env:TESSA_DIR to another folder and paste the line again." }
    $branch = & $git -C $Dir branch --show-current
    $dirty = & $git -C $Dir status --porcelain
    if ($branch -eq 'main' -and -not $dirty) { & $git -C $Dir pull -q --ff-only; Ok "updated $Dir" } else { Ok "$Dir is there (left as it is: it's on another branch or has changes)" }
} elseif ((Test-Path $Dir) -and (Get-ChildItem -Force $Dir | Select-Object -First 1)) {
    Stop-Here "$Dir already exists and isn't a copy of otp-os. Move it away, or set `$env:TESSA_DIR to another folder and paste the line again."
} else {
    New-Item -ItemType Directory -Force (Split-Path $Dir) | Out-Null
    & $gh repo clone "$Org/$Repo" $Dir -- -q
    if ($LASTEXITCODE -ne 0) { Stop-Here 'otp-os could not be copied. Paste the line again.' }
    Ok "copied to $Dir"
}

if ($env:TESSA_INSTALL_CI) { Write-Host "`nStopping after the copy (TESSA_INSTALL_CI)."; return }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'scripts\install-tessa.ps1')
