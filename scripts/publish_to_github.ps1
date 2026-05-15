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

function Ensure-GitUserIdentity([string] $GitHubUser) {
    $email = (git config user.email 2>$null)
    $name = (git config user.name 2>$null)
    if ([string]::IsNullOrWhiteSpace($email) -or [string]::IsNullOrWhiteSpace($name)) {
        $safeEmail = ($GitHubUser + '@users.noreply.github.com')
        git config user.email $safeEmail
        git config user.name $GitHubUser
        Write-Host ('Git identity lokal: ' + $GitHubUser + ' <' + $safeEmail + '>')
    }
}

function Get-GitStagedFileNames {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return @(
            git diff --cached --name-only 2>$null |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Ensure-GitCommit {
    param(
        [Parameter(Mandatory)][string] $InitialMessage,
        [Parameter(Mandatory)][string] $GitHubUser,
        [Parameter(Mandatory)][string] $DefaultBranch
    )

    $addCode = Invoke-Git -Args @('add', '-A')
    if ($addCode -ne 0) { throw 'git add gagal' }

    $hasHead = Test-GitHasHead
    $staged = Get-GitStagedFileNames

    if (-not $hasHead) {
        if ($staged.Count -eq 0) {
            Write-Host ''
            git status
            throw @'
Belum ada commit dan tidak ada file ter-stage.
Kemungkinan: .gitignore terlalu luas, atau folder proyek kosong.
Perbaiki .gitignore lalu jalankan script lagi.
'@
        }

        Ensure-GitUserIdentity -GitHubUser $GitHubUser
        Write-Step ('Commit awal (' + $staged.Count + ' file): ' + $InitialMessage)
        git commit -m $InitialMessage
        if ($LASTEXITCODE -ne 0) {
            throw 'git commit gagal. Set manual: git config user.name dan git config user.email'
        }

        Invoke-Git -Args @('branch', '-M', $DefaultBranch) | Out-Null
        return
    }

    $dirty = @(
        git status --porcelain 2>$null |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($dirty.Count -eq 0) {
        Write-Host 'Working tree bersih, tidak perlu commit baru.' -ForegroundColor Yellow
        return
    }

    if ($staged.Count -eq 0) {
        $addCode = Invoke-Git -Args @('add', '-A')
        if ($addCode -ne 0) { throw 'git add gagal' }
        $staged = Get-GitStagedFileNames
    }

    if ($staged.Count -eq 0) {
        throw 'Ada perubahan tetapi tidak ada file ter-stage. Coba: git add -A'
    }

    Ensure-GitUserIdentity -GitHubUser $GitHubUser
    $msg = Read-Host 'Ada perubahan. Pesan commit (Enter = Update IDX Stock ML)'
    if ([string]::IsNullOrWhiteSpace($msg)) {
        $msg = 'Update IDX Stock ML'
    }
    Write-Step ('Commit (' + $staged.Count + ' file): ' + $msg)
    git commit -m $msg
    if ($LASTEXITCODE -ne 0) { throw 'git commit gagal' }
}

function Invoke-Gh {
    param([Parameter(Mandatory)][string[]] $Args)
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & gh @Args 2>&1 | Out-Null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Test-GhRepoExists([string] $Repo) {
    # Repo belum ada → gh menulis GraphQL error ke stderr; itu normal, bukan kegagalan script.
    $exitCode = Invoke-Gh -Args @('repo', 'view', $Repo)
    return ($exitCode -eq 0)
}

function Test-GhLoggedIn([string] $ExpectedUser) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $statusLines = @(gh auth status 2>&1)
    $ErrorActionPreference = $oldEap

    if ($LASTEXITCODE -ne 0) {
        Write-Host ($statusLines -join [Environment]::NewLine)
        throw 'Belum login ke GitHub. Jalankan: gh auth login'
    }

    $login = ''
    $ErrorActionPreference = 'Continue'
    $login = (gh api user -q .login 2>&1 | Out-String).Trim()
    $ErrorActionPreference = $oldEap

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
Assert-Command 'gh' 'Instal: https://cli.github.com/ - lalu jalankan: gh auth login'

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
        Write-Host ('[dry-run] git init -b ' + $DefaultBranch)
    }
    else {
        # Jangan set branch sebelum commit pertama (hindari main tanpa commit).
        $initCode = Invoke-Git -Args @('init', '-b', $DefaultBranch)
        if ($initCode -ne 0) {
            $initCode = Invoke-Git -Args @('init')
            if ($initCode -ne 0) { throw 'git init gagal' }
        }
    }
}

Write-Step 'Staging & commit (mengikuti .gitignore)'
if ($DryRun) {
    Write-Host '[dry-run] git add -A && git commit (jika perlu)'
    Write-Host '[dry-run] git status -sb'
}
else {
    Ensure-GitCommit `
        -InitialMessage $InitialCommitMessage `
        -GitHubUser $GitHubUser `
        -DefaultBranch $DefaultBranch
}

Write-Step 'Remote origin'
$remotes = @()
if (-not $DryRun -and (Test-Path (Join-Path $ProjectRoot '.git'))) {
    $remotes = @(git remote)
}
$hasOrigin = $remotes -contains 'origin'

if ($DryRun) {
    if (-not $hasOrigin) {
        Write-Host ('[dry-run] git remote add origin ' + $RemoteUrl)
    }
    else {
        Write-Host ('[dry-run] git remote set-url origin ' + $RemoteUrl)
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
        Write-Host ('[dry-run] gh repo create ' + $GhRepo + ' --' + $Visibility + ' --source=. --remote=origin --push')
    }
    else {
        if (Test-GhRepoExists -Repo $GhRepo) {
            Write-Host "Repo sudah ada: https://github.com/$GhRepo"
        }
        else {
            Write-Host "Repo belum ada - membuat $GhRepo ($Visibility) ..."
            $createCode = Invoke-Gh -Args @(
                'repo', 'create', $GhRepo,
                "--$Visibility",
                '--source=.',
                '--remote=origin',
                '--push',
                '--description', $Description
            )
            if ($createCode -ne 0) {
                $manualCmd = 'gh repo create ' + $GhRepo + ' --' + $Visibility + ' --source=. --remote=origin --push'
                throw "gh repo create gagal (exit $createCode). Coba manual: $manualCmd"
            }
            Write-Host ''
            Write-Host ('Repo dibuat dan di-push: https://github.com/' + $GhRepo) -ForegroundColor Green
            exit 0
        }
    }
}

Write-Step "Push ke origin ($DefaultBranch)"
if ($DryRun) {
    Write-Host ('[dry-run] git push -u origin ' + $DefaultBranch)
}
else {
    if (-not (Test-GitHasHead)) {
        Write-Host 'Belum ada commit - mencoba commit otomatis...' -ForegroundColor Yellow
        Ensure-GitCommit `
            -InitialMessage $InitialCommitMessage `
            -GitHubUser $GitHubUser `
            -DefaultBranch $DefaultBranch
    }

    if (-not (Test-GitHasHead)) {
        throw 'Belum ada commit setelah git add. Periksa output git status di atas.'
    }

    git push -u origin $DefaultBranch
    if ($LASTEXITCODE -ne 0) {
        throw ('git push gagal. Coba: gh auth login; pastikan repo https://github.com/' + $GhRepo + ' ada; atau jalankan dengan -SkipCreate.')
    }
    Write-Host ''
    Write-Host ('Berhasil: https://github.com/' + $GhRepo) -ForegroundColor Green
}
