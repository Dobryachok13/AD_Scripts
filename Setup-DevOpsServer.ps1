<#
.SYNOPSIS
    Настраивает чистый Windows Server для DevOps-задач: Git, PowerShell 7, клонирование репозитория.
.DESCRIPTION
    Скрипт сам переключается в корень диска C:\, устанавливает всё необходимое,
    клонирует репозиторий и создаёт задачу в планировщике.
    Идемпотентный — можно запускать много раз.
.EXAMPLE
    .\Setup-DevOpsServer.ps1
#>

param(
    [string]$RepoUrl = "https://github.com/Dobryachok13/AD_Scripts.git",
    [string]$Destination = "C:\AD_Scripts",
    [string]$Branch = "feature/setup-script",
    [string]$Core = "C:\"
)

# Функция поиска pwsh.exe (руками, если Get-Command не сработал)
function Find-PwshExe {
    $pwshExe = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
    if ($pwshExe) { return $pwshExe }

    $possiblePaths = @(
        "C:\Program Files\PowerShell\7\pwsh.exe",
        "C:\Program Files\PowerShell\7-preview\pwsh.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    )
    $manualPath = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($manualPath) {
        $pwshDir = Split-Path $manualPath -Parent
        $env:Path += ";$pwshDir"
        Write-Host "PowerShell 7 found at $manualPath and added to PATH" -ForegroundColor Yellow
        return $manualPath
    }
    return $null
}

# Переключаемся в корень диска C:\
Set-Location C:\

# Проверка: запуск от администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit 1
}

# Проверка: не Domain Controller (если есть Get-WindowsFeature)
if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
    if ((Get-WindowsFeature -Name AD-Domain-Services).Installed) {
        Write-Host "This script should not run on a Domain Controller!" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Starting server setup from $(Get-Location)..." -ForegroundColor Cyan

# ===== 1. Установка Git (принудительная проверка по файлу git.exe) =====
$gitExe = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
if ($gitExe) {
    Write-Host "Git already installed: $gitExe" -ForegroundColor Green
} else {
    Write-Host "Installing Git..." -ForegroundColor Cyan
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.45.1.windows.1/Git-2.45.1-64-bit.exe"
    $gitInstaller = "$env:TEMP\GitInstaller.exe"
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
    Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" -Wait -NoNewWindow
    Remove-Item $gitInstaller -Force
    Write-Host "Git installed successfully" -ForegroundColor Green
}
$gitExe = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue

# Добавляем Git в PATH для текущей сессии
$env:Path += ";C:\Program Files\Git\bin"

# ===== 2. Установка PowerShell 7 =====
$pwshExe = Find-PwshExe
if ($pwshExe) {
    Write-Host "PowerShell 7 already installed: $pwshExe" -ForegroundColor Green
} else {
    Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
    $ps7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.6.2/PowerShell-7.6.2-win-x64.msi"
    $ps7Installer = "$env:TEMP\PowerShell7.msi"
    Invoke-WebRequest -Uri $ps7Url -OutFile $ps7Installer -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `"$ps7Installer`" /quiet /norestart" -Wait -NoNewWindow
    Remove-Item $ps7Installer -Force
    Write-Host "PowerShell 7 installed successfully" -ForegroundColor Green
}
$pwshExe = Find-PwshExe

# ===== 3. Клонирование или обновление репозитория =====
# Убедимся, что целевая папка существует
if (-not (Test-Path $Destination)) {
    Write-Host "Creating destination folder: $Destination" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

# Переходим в целевую папку
Set-Location $Destination

# Проверяем, есть ли уже репозиторий (наличие папки .git)
if (Test-Path ".git") {
    Write-Host "Repository already exists, pulling latest changes from branch $Branch..." -ForegroundColor Cyan
    git pull
} else {
    Write-Host "Cloning repository from $RepoUrl (branch $Branch) into $Destination..." -ForegroundColor Cyan
    git clone --branch $Branch $RepoUrl .
}

# ===== 4. Установка GitHub Actions Runner =====

# ===== Получение токена регистрации раннера через API =====
$pat = [Environment]::GetEnvironmentVariable("GITHUB_PAT", "Machine")
if (-not $pat) {
    Write-Host "GITHUB_PAT environment variable not found. Please set it first." -ForegroundColor Red
    exit 1
}

Write-Host "Obtaining runner registration token from GitHub API..." -ForegroundColor Cyan
$apiUrl = "https://api.github.com/repos/Dobryachok13/AD_Scripts/actions/runners/registration-token"
$headers = @{
    "Authorization" = "Bearer $pat"
    "Accept" = "application/vnd.github+json"
}

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers
    $runnerToken = $response.token
    Write-Host "Registration token obtained successfully (expires at: $($response.expires_at))" -ForegroundColor Green
} catch {
    Write-Host "Failed to obtain registration token: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n[4/6] Checking GitHub Actions Runner..." -ForegroundColor Yellow
$runnerDir = "C:\actions-runner"

Set-Location $Core

if (Test-Path "$runnerDir\.runner") {
    Write-Host "Runner service already exists, skipping" -ForegroundColor Green
} else {
    Write-Host "Downloading GitHub Actions runner..." -ForegroundColor Cyan
    $runnerUrl = "https://github.com/actions/runner/releases/download/v2.334.0/actions-runner-win-x64-2.334.0.zip"
    $runnerZip = "$env:TEMP\runner.zip"
    Invoke-WebRequest -Uri $runnerUrl -OutFile $runnerZip -UseBasicParsing
    
    # Создаём папку и распаковываем
    New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
    Expand-Archive -Path $runnerZip -DestinationPath $runnerDir -Force
    Remove-Item $runnerZip -Force
    
    # Регистрируем runner (токен нужно получить из GitHub)
    Write-Host "Registering runner with GitHub..." -ForegroundColor Cyan
    
    Push-Location $runnerDir
    .\config.cmd --unattended --url $RepoUrl --token $runnerToken --name "DEV-OPS-Runner" --labels "windows,devops" --runasservice
    Pop-Location
    
    Write-Host "Runner installed and configured as service" -ForegroundColor Green
}

# ===== 5. Настройка планировщика задач =====
$taskName = "AD_StalePasswords_Check"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Scheduled task '$taskName' already exists, skipping" -ForegroundColor Green
} else {
    Write-Host "Creating scheduled task for AD script..." -ForegroundColor Cyan
    $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$Destination\Find-StalePasswords.ps1`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "09:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    Write-Host "Scheduled task created successfully" -ForegroundColor Green
}

# ===== 6. Финальная проверка =====
Write-Host "`nFinal verification..." -ForegroundColor Yellow
$allGood = $true
if (-not ($gitExe)) { Write-Host "Git not found!" -ForegroundColor Red; $allGood = $false }
if (-not ($pwshExe)) { Write-Host "PowerShell 7 not found!" -ForegroundColor Red; $allGood = $false }
if (-not (Test-Path "$Destination\Find-StalePasswords.ps1")) { Write-Host "Main script not found!" -ForegroundColor Red; $allGood = $false }

if ($allGood) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Setup completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "Setup completed with errors. Please check above messages." -ForegroundColor Red
}