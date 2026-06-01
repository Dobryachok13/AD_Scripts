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
    [string]$Branch = "setup-script"
)

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
    $gitExe = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
}

# Добавляем Git в PATH для текущей сессии
$env:Path += ";C:\Program Files\Git\bin"

# ===== 2. Установка PowerShell 7 =====
$pwshExe = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
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
    $pwshExe = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
}

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

# ===== 4. Настройка планировщика задач =====
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

# ===== 5. Финальная проверка =====
Write-Host "`nFinal verification..." -ForegroundColor Yellow
$allGood = $true
if (-not (Test-Path $gitExe)) { Write-Host "Git not found!" -ForegroundColor Red; $allGood = $false }
if (-not (Test-Path $pwshExe)) { Write-Host "PowerShell 7 not found!" -ForegroundColor Red; $allGood = $false }
if (-not (Test-Path "$Destination\Find-StalePasswords.ps1")) { Write-Host "Main script not found!" -ForegroundColor Red; $allGood = $false }

if ($allGood) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Setup completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "Setup completed with errors. Please check above messages." -ForegroundColor Red
}