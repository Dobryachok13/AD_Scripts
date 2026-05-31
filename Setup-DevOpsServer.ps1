<#
.SYNOPSIS
    Настраивает чистый Windows Server для DevOps-задач: Git, PowerShell 7, клонирование репозитория.
.DESCRIPTION
    Устанавливает всё необходимое для запуска AD-скриптов и GitHub Actions Runner.
    Запускать от администратора. Скрипт идемпотентный — можно запускать много раз.
.EXAMPLE
    .\Setup-DevOpsServer.ps1 -RepoUrl "https://github.com/Dobryachok13/AD_Scripts.git" -Destination "C:\AD_Scripts"
#>

param(
    [string]$RepoUrl = "https://github.com/Dobryachok13/AD_Scripts.git",
    [string]$Destination = "C:\AD_Scripts"
)

# Проверка: запуск от администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit 1
}

# Проверка: не Domain Controller
if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
    if ((Get-WindowsFeature -Name AD-Domain-Services).Installed) {
        Write-Host "This script should not run on a Domain Controller!" -ForegroundColor Red
        Write-Host "Exiting to avoid breaking AD." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Starting server setup..." -ForegroundColor Cyan

# ===== 1. Установка Git =====
Write-Host "`n[1/5] Checking Git..." -ForegroundColor Yellow
$gitPath = "C:\Program Files\Git\bin\git.exe"
if (Test-Path $gitPath) {
    Write-Host "Git already installed at $gitPath" -ForegroundColor Green
} else {
    Write-Host "Installing Git..." -ForegroundColor Cyan
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.45.1.windows.1/Git-2.45.1-64-bit.exe"
    $gitInstaller = "$env:TEMP\GitInstaller.exe"
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
    Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" -Wait -NoNewWindow
    Remove-Item $gitInstaller -Force
    Write-Host "Git installed successfully" -ForegroundColor Green
}

# Добавляем Git в PATH текущей сессии
$env:Path += ";C:\Program Files\Git\bin"

# ===== 2. Установка PowerShell 7 =====
Write-Host "`n[2/5] Checking PowerShell 7..." -ForegroundColor Yellow
$ps7Path = "C:\Program Files\PowerShell\7\pwsh.exe"
if (Test-Path $ps7Path) {
    Write-Host "PowerShell 7 already installed at $ps7Path" -ForegroundColor Green
} else {
    Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
    $ps7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.2/PowerShell-7.4.2-win-x64.msi"
    $ps7Installer = "$env:TEMP\PowerShell7.msi"
    Invoke-WebRequest -Uri $ps7Url -OutFile $ps7Installer -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `"$ps7Installer`" /quiet /norestart" -Wait -NoNewWindow
    Remove-Item $ps7Installer -Force
    Write-Host "PowerShell 7 installed successfully" -ForegroundColor Green
}

# ===== 3. Клонирование или обновление репозитория =====
Write-Host "`n[3/5] Checking repository at $Destination..." -ForegroundColor Yellow
if (Test-Path $Destination) {
    Write-Host "Repository already exists, pulling latest changes..." -ForegroundColor Cyan
    Push-Location $Destination
    git pull
    Pop-Location
} else {
    Write-Host "Cloning repository..." -ForegroundColor Cyan
    git clone $RepoUrl $Destination
    Write-Host "Repository cloned successfully" -ForegroundColor Green
}

# ===== 4. Настройка планировщика задач =====
Write-Host "`n[4/5] Checking scheduled task..." -ForegroundColor Yellow
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
Write-Host "`n[5/5] Final verification..." -ForegroundColor Yellow
$allGood = $true
if (-not (Test-Path $gitPath)) { Write-Host "Git not found!" -ForegroundColor Red; $allGood = $false }
if (-not (Test-Path $ps7Path)) { Write-Host "PowerShell 7 not found!" -ForegroundColor Red; $allGood = $false }
if (-not (Test-Path "$Destination\Find-StalePasswords.ps1")) { Write-Host "Script not found in repository!" -ForegroundColor Red; $allGood = $false }

if ($allGood) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Setup completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "`nSetup completed with errors. Please check above messages." -ForegroundColor Red
}