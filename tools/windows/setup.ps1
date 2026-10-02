# Mudhkir - one-time setup for Windows + an Android phone.
#
# Run from PowerShell (no admin needed):
#   powershell -ExecutionPolicy Bypass -File setup.ps1
# or right-click this file > "Run with PowerShell".
#
# Safe to run again: finished steps are skipped.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

$FlutterVersion = '3.47.6'
$FlutterZipUrl  = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
$FlutterSha256  = 'a01bb0d26de91bc23c97cd9ccfaad281a612fb8304213fdd5df1119a09404796'
$FlutterRoot    = 'C:\src\flutter'
$RepoUrl        = 'https://github.com/AbdulrahmanB-25/Mudhkir_App.git'
$Branch         = 'claude/keen-wright-nbm6cv'
$ProjectDir     = Join-Path $env:USERPROFILE 'Mudhkir_App'
$SdkDir         = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$SupabaseUrl    = 'https://emvpjqtaylchpmaugipy.supabase.co'

function Step($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    OK: $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    !! $text" -ForegroundColor Yellow }

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Add-UserPath($dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $user) { $user = '' }
    $parts = $user.Split(';') | Where-Object { $_ -ne '' }
    if ($parts -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User')
        Ok "added $dir to your PATH"
    }
    Refresh-Path
}

function Winget-Install($id, $name) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is not available. Install '$name' manually, then run this script again."
    }
    Write-Host "    installing $name (this can take a few minutes)..."
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

# ---------------------------------------------------------------- 1. Git
Step 'Git'
if (Get-Command git -ErrorAction SilentlyContinue) {
    Ok (git --version)
} else {
    Winget-Install 'Git.Git' 'Git'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Add-UserPath 'C:\Program Files\Git\cmd'
    }
    Ok (git --version)
}

# ---------------------------------------------------------------- 2. Android Studio
Step 'Android Studio'
$studioExe = @(
    "$env:ProgramFiles\Android\Android Studio\bin\studio64.exe",
    "$env:LOCALAPPDATA\Programs\Android Studio\bin\studio64.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($studioExe) {
    Ok "found $studioExe"
} else {
    Winget-Install 'Google.AndroidStudio' 'Android Studio'
    $studioExe = "$env:ProgramFiles\Android\Android Studio\bin\studio64.exe"
}

# The SDK is downloaded by Android Studio's first-launch wizard.
if (-not (Test-Path (Join-Path $SdkDir 'platform-tools\adb.exe'))) {
    Warn 'The Android SDK is not installed yet. Android Studio will open now.'
    Write-Host '    In Android Studio:'
    Write-Host '      1. Choose "Do not import settings" > Next > "Standard" > Next.'
    Write-Host '      2. Accept all licenses and click Finish. Wait for the downloads to complete.'
    Write-Host '      3. On the Welcome screen: Plugins > search "Flutter" > Install > Restart IDE.'
    Write-Host '      4. Close Android Studio and come back here.'
    if (Test-Path $studioExe) { Start-Process $studioExe }
    Read-Host '    Press Enter when the wizard has finished'
}
if (-not (Test-Path (Join-Path $SdkDir 'platform-tools\adb.exe'))) {
    throw "The Android SDK is still missing at $SdkDir. Finish the Android Studio setup wizard, then run this script again."
}
Ok "Android SDK at $SdkDir"
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdkDir, 'User')
$env:ANDROID_HOME = $SdkDir
Add-UserPath (Join-Path $SdkDir 'platform-tools')

# ---------------------------------------------------------------- 3. Flutter
Step "Flutter $FlutterVersion"
$flutterBat = Join-Path $FlutterRoot 'bin\flutter.bat'
$haveRightFlutter = $false
if (Test-Path $flutterBat) {
    $versionFile = Join-Path $FlutterRoot 'version'
    if ((Test-Path $versionFile) -and ((Get-Content $versionFile -Raw).Trim() -eq $FlutterVersion)) {
        $haveRightFlutter = $true
    }
}
if ($haveRightFlutter) {
    Ok "already installed in $FlutterRoot"
} else {
    if (Test-Path $FlutterRoot) {
        $old = "$FlutterRoot-old-$(Get-Date -Format yyyyMMddHHmmss)"
        Warn "moving the existing $FlutterRoot to $old"
        Move-Item $FlutterRoot $old
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $FlutterRoot) | Out-Null
    $zip = Join-Path $env:TEMP "flutter_$FlutterVersion.zip"
    if (-not (Test-Path $zip) -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $FlutterSha256.ToUpper()) {
        Write-Host '    downloading Flutter (about 1 GB)...'
        Invoke-WebRequest -Uri $FlutterZipUrl -OutFile $zip
    }
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $FlutterSha256.ToUpper()) {
        Remove-Item $zip
        throw 'The Flutter download is corrupted. Run the script again.'
    }
    Write-Host '    extracting...'
    Expand-Archive -Path $zip -DestinationPath (Split-Path $FlutterRoot) -Force
    Ok "installed to $FlutterRoot"
}
Add-UserPath (Join-Path $FlutterRoot 'bin')
& $flutterBat config --no-analytics | Out-Null
& $flutterBat config --android-sdk $SdkDir | Out-Null

# ---------------------------------------------------------------- 4. SDK packages + licenses
Step 'Android SDK packages'
$sdkManager = Get-ChildItem -Path (Join-Path $SdkDir 'cmdline-tools') -Filter 'sdkmanager.bat' -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $sdkManager) {
    Warn 'Android SDK Command-line Tools are missing.'
    Write-Host '    In Android Studio: More Actions (or Settings) > SDK Manager > "SDK Tools" tab >'
    Write-Host '    tick "Android SDK Command-line Tools (latest)" > Apply. Then press Enter here.'
    if (Test-Path $studioExe) { Start-Process $studioExe }
    Read-Host '    Press Enter when it is installed'
    $sdkManager = Get-ChildItem -Path (Join-Path $SdkDir 'cmdline-tools') -Filter 'sdkmanager.bat' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($sdkManager) {
    & $sdkManager.FullName --install 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' | Out-Host
    Ok 'SDK packages installed'
} else {
    Warn 'Skipping SDK packages; Gradle will download what it needs on the first build.'
}
Write-Host '    accepting Android licenses (answering "y" for you)...'
('y' + [Environment]::NewLine) * 20 | & $flutterBat doctor --android-licenses | Out-Null
Ok 'licenses accepted'

# ---------------------------------------------------------------- 5. Project
Step 'Mudhkir project'
if (Test-Path (Join-Path $ProjectDir '.git')) {
    Push-Location $ProjectDir
    git fetch origin $Branch
    git checkout $Branch
    git pull --ff-only origin $Branch
    Pop-Location
    Ok "updated $ProjectDir"
} else {
    git clone --branch $Branch $RepoUrl $ProjectDir
    Ok "cloned to $ProjectDir"
}

$envFile = Join-Path $ProjectDir 'env.json'
if (Test-Path $envFile) {
    Ok 'env.json already exists'
} else {
    Write-Host ''
    Write-Host '    Paste your Supabase publishable key (starts with sb_publishable_).'
    Write-Host '    Find it at: Supabase dashboard > project "mudhkir" > Project Settings > API Keys.'
    Write-Host '    Or press Enter to skip and use the app offline only.'
    $key = (Read-Host '    Key').Trim()
    if ($key) {
        $json = @{ SUPABASE_URL = $SupabaseUrl; SUPABASE_PUBLISHABLE_KEY = $key } | ConvertTo-Json
        [IO.File]::WriteAllText($envFile, $json)
        Ok 'env.json created (it is git-ignored)'
    } else {
        [IO.File]::WriteAllText($envFile, '{}')
        Warn 'env.json created empty: the app will run offline only. Edit it later to add the key.'
    }
}

Push-Location $ProjectDir
& $flutterBat pub get
Pop-Location
Ok 'packages downloaded'

# ---------------------------------------------------------------- 6. Check
Step 'flutter doctor'
& $flutterBat doctor
Step 'Connected devices'
& $flutterBat devices

Write-Host ''
Write-Host 'Setup finished.' -ForegroundColor Green
Write-Host 'Next: connect your phone with USB debugging on (see docs\WINDOWS_SETUP.md), then either'
Write-Host "  - double-click $ProjectDir\tools\windows\run-on-phone.bat, or"
Write-Host "  - open $ProjectDir in Android Studio, pick your phone and the 'Mudhkir' configuration, press the green Run button."
Write-Host '(Close and reopen any terminal or Android Studio window so it sees the new PATH.)'
Read-Host 'Press Enter to close'
