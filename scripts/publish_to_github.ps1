#Requires -Version 5.1
<#
.SYNOPSIS
  Inisialisasi git (jika belum) dan push proyek IDX Stock ML ke GitHub.

.DESCRIPTION
  - Memastikan .gitignore ada (venv, build Flutter, saved_models tidak ikut).
  - git init + commit pertama (hanya jika belum ada commit).
  - Membuat repo di akun GitHub (default: Memedsugianto) via GitHub CLI.
  - git push ke origin.

  Prasyarat:
    1. Git for Windows terpasang
    2. GitHub CLI (gh) terpasang
    3. Sudah login: gh auth login

.PARAMETER RepoName
  Override nama repo (default dari github.config.ps1).

.PARAMETER Visibility
  public atau private (override config).

.PARAMETER SkipCreate
  Hanya commit + push; tidak memanggil gh repo create.

.PARAMETER DryRun
  Tampilkan perintah tanpa menjalankan git/gh push.
#>
[CmdletBinding()]
param(
    [string] $RepoName,
    [ValidateSet('public', 'private')]
    [string] $Visibility,
    [switch] $SkipCreate,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-Command([string] $Name, [string] $InstallHint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name tidak ditemukan di PATH.`n$InstallHint"
    }
}

function Get-GithubPublishConfig([string] $ConfigPath) {
    if (-not (Test-Path $ConfigPath)) {
        throw "File konfigurasi tidak ditemukan: $ConfigPath"
    }
    $cfg = & $ConfigPath
    if ($null -eq $cfg -or $cfg -isnot [hashtable]) {
        throw "github.config.ps1 harus mengembalikan hashtable (@{ ... })."
    }
    return $cfg
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]] $Args)
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git @Args
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Test-GitHasHead {
    # rev-parse gagal jika belum ada commit — jangan biarkan stderr menghentikan script (EAP Stop).
    $exitCode = Invoke-Git -Args @('rev-parse', '--verify', 'HEAD')
    return ($exitCode -eq 0)
}

function Test-GhLoggedIn([string] $ExpectedUser) {
    $statusLines = @(gh auth status 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Host ($statusLines -join [Environment]::NewLine)
        throw 'Belum login ke GitHub. Jalankan: gh auth login'
    }

    $login = ''
    try {
        $login = (gh api user -q .login 2>$null).ToString().Trim()
    }
    catch {
        # gh api tidak tersedia / gagal — lanjut dengan teks auth status
    }

    if ([string]::IsNullOrWhiteSpace($login)) {
        $joined = ($statusLines | ForEach-Object { "$_" }) -join "`n"
        if ($joined -match 'account\s+(\S+)') {
            $login = $Matches[1]
        }
    }

    if ([string]::IsNullOrWhiteSpace($login)) {
        Write-Host ($statusLines -join [Environment]::NewLine)
        throw 'Tidak bisa membaca akun GitHub dari gh. Jalankan: gh auth login'
    }

    Write-Host "Login GitHub CLI: $login"
    if (-not [string]::IsNullOrWhiteSpace($ExpectedUser) -and
        ($login -ne $ExpectedUser)) {
        Write-Warning "Config GitHubUser='$ExpectedUser' tetapi gh login='$login'. Push tetap dilanjutkan ke remote config."
    }
}

# scripts\ -> stock_predictor\
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$ConfigPath = Join-Path $ScriptDir 'github.config.ps1'

$cfg = Get-GithubPublishConfig -ConfigPath $ConfigPath

$GitHubUser = [string]$cfg.GitHubUser
$RepoName = if ($PSBoundParameters.ContainsKey('RepoName') -and $RepoName) { $RepoName } else { [string]$cfg.RepoName }
$InitialCommitMessage = [string]$cfg.InitialCommitMessage
$DefaultBranch = [string]$cfg.DefaultBranch
$Visibility = if ($PSBoundParameters.ContainsKey('Visibility') -and $Visibility) { $Visibility } else { [string]$cfg.Visibility }
$Description = [string]$cfg.Description

foreach ($pair in @(
        @{ Name = 'GitHubUser'; Value = $GitHubUser }
        @{ Name = 'RepoName'; Value = $RepoName }
        @{ Name = 'DefaultBranch'; Value = $DefaultBranch }
        @{ Name = 'Visibility'; Value = $Visibility }
    )) {
    if ([string]::IsNullOrWhiteSpace($pair.Value)) {
        throw "Konfigurasi '$($pair.Name)' kosong di github.config.ps1"
    }
}

if ($Visibility -notin @('public', 'private')) {
    throw "Visibility harus 'public' atau 'private' (sekarang: '$Visibility')."
}

$RemoteUrl = "https://github.com/$GitHubUser/$RepoName.git"
$GhRepo = "$GitHubUser/$RepoName"

Write-Host "Proyek : $ProjectRoot"
Write-Host "Remote : $RemoteUrl"
Write-Host "Branch : $DefaultBranch"

Assert-Command 'git' 'Instal: https://git-scm.com/download/win'
Assert-Command 'gh' 'Instal: https://cli.github.com/ — lalu jalankan: gh auth login'

Set-Location $ProjectRoot

$gitignorePath = Join-Path $ProjectRoot '.gitignore'
if (-not (Test-Path $gitignorePath)) {
    throw ".gitignore tidak ada di root proyek. Jalankan ulang setup atau salin dari template repo."
}

Write-Step 'Memeriksa autentikasi GitHub CLI'
if ($DryRun) {
    Write-Host '[dry-run] gh auth status && gh api user -q .login'
}
else {
    Test-GhLoggedIn -ExpectedUser $GitHubUser
}

Write-Step 'Inisialisasi repository git'
if (-not (Test-Path (Join-Path $ProjectRoot '.git'))) {
    if ($DryRun) {
        Write-Host "[dry-run] git init -b $DefaultBranch"
    }
    else {
        git init
        if ($LASTEXITCODE -ne 0) { throw 'git init gagal' }
        git symbolic-ref HEAD "refs/heads/$DefaultBranch" 2>$null
        if ($LASTEXITCODE -ne 0) {
            git checkout -b $DefaultBranch 2>$null
            if ($LASTEXITCODE -ne 0) {
                git branch -M $DefaultBranch
            }
        }
    }
}

Write-Step 'Staging file (mengikuti .gitignore)'
if ($DryRun) {
    Write-Host '[dry-run] git add -A'
    Write-Host '[dry-run] git status -sb'
}
else {
    git add -A
    if ($LASTEXITCODE -ne 0) { throw 'git add gagal' }

    $porcelain = git status --porcelain
    if (-not $porcelain) {
        Write-Host 'Tidak ada perubahan untuk di-commit.' -ForegroundColor Yellow
    }
    else {
        $hasHead = Test-GitHasHead

        if (-not $hasHead) {
            Write-Step "Commit awal: $InitialCommitMessage"
            git commit -m $InitialCommitMessage
            if ($LASTEXITCODE -ne 0) { throw 'git commit gagal' }
        }
        else {
            $msg = Read-Host 'Ada perubahan. Masukkan pesan commit (Enter = Update IDX Stock ML)'
            if ([string]::IsNullOrWhiteSpace($msg)) {
                $msg = 'Update IDX Stock ML'
            }
            git commit -m $msg
            if ($LASTEXITCODE -ne 0) { throw 'git commit gagal' }
        }
    }
}

Write-Step 'Remote origin'
$remotes = @()
if (-not $DryRun -and (Test-Path (Join-Path $ProjectRoot '.git'))) {
    $remotes = @(git remote)
}
$hasOrigin = $remotes -contains 'origin'

if ($DryRun) {
    if (-not $hasOrigin) {
        Write-Host "[dry-run] git remote add origin $RemoteUrl"
    }
    else {
        Write-Host "[dry-run] git remote set-url origin $RemoteUrl"
    }
}
else {
    if (-not $hasOrigin) {
        git remote add origin $RemoteUrl
    }
    else {
        git remote set-url origin $RemoteUrl
    }
    if ($LASTEXITCODE -ne 0) { throw 'git remote gagal' }
}

if (-not $SkipCreate) {
    Write-Step "Membuat repo GitHub (jika belum ada): $GhRepo"
    if ($DryRun) {
        Write-Host "[dry-run] gh repo create $GhRepo --$Visibility --source=. --remote=origin --push"
    }
    else {
        $view = gh repo view $GhRepo 2>$null
        if ($LASTEXITCODE -ne 0) {
            & gh repo create $GhRepo `
                --$Visibility `
                --source=. `
                --remote=origin `
                --push `
                --description $Description
            if ($LASTEXITCODE -ne 0) { throw 'gh repo create gagal' }
            Write-Host "`nRepo dibuat dan di-push: https://github.com/$GhRepo" -ForegroundColor Green
            exit 0
        }
        else {
            Write-Host "Repo sudah ada: https://github.com/$GhRepo"
        }
    }
}

Write-Step "Push ke origin ($DefaultBranch)"
if ($DryRun) {
    Write-Host "[dry-run] git push -u origin $DefaultBranch"
}
else {
    if (-not (Test-GitHasHead)) {
        throw 'Belum ada commit. Pastikan ada file ter-stage, lalu jalankan script lagi.'
    }

    git push -u origin $DefaultBranch
    if ($LASTEXITCODE -ne 0) {
        throw @"
git push gagal. Coba:
  1. gh auth login
  2. Pastikan repo ada: https://github.com/$GhRepo
  3. Atau buat manual di GitHub lalu jalankan lagi script ini dengan -SkipCreate
"@
    }
    Write-Host "`nBerhasil: https://github.com/$GhRepo" -ForegroundColor Green
}
