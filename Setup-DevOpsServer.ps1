<#
.SYNOPSIS
    Настраивает чистый Windows Server для DevOps-задач: Git, PowerShell 7, клонирование репозитория.
.DESCRIPTION
    Устанавливает всё необходимое для запуска AD-скриптов и GitHub Actions Runner.
    Запускать от администратора.
.EXAMPLE
    .\Setup-DevOpsServer.ps1 -RepoUrl "https://github.com/Dobryachok13/AD_Scripts.git" -Destination "C:\AD_Scripts"
#>

param(
    [string]$RepoUrl = "https://github.com/Dobryachok13/AD_Scripts.git",
    [string]$Destination = "C:\AD_Scripts"
)

# 1. Установка Git (тихая)
Write-Host "Installing Git..." -ForegroundColor Cyan
$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.45.1.windows.1/Git-2.45.1-64-bit.exe"
$gitInstaller = "$env:TEMP\GitInstaller.exe"
Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" -Wait -NoNewWindow
Remove-Item $gitInstaller -Force

# 2. Установка PowerShell 7
Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
$ps7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.2/PowerShell-7.4.2-win-x64.msi"
$ps7Installer = "$env:TEMP\PowerShell7.msi"
Invoke-WebRequest -Uri $ps7Url -OutFile $ps7Installer -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `"$ps7Installer`" /quiet /norestart" -Wait -NoNewWindow
Remove-Item $ps7Installer -Force

# 3. Добавляем Git в PATH текущей сессии, чтобы команда git заработала сразу
$env:Path += ";C:\Program Files\Git\bin"

# 4. Клонирование или обновление репозитория
if (Test-Path $Destination) {
    Write-Host "Repository already exists at $Destination, pulling latest changes..." -ForegroundColor Yellow
    Push-Location $Destination
    git pull
    Pop-Location
} else {
    Write-Host "Cloning repository to $Destination..." -ForegroundColor Cyan
    git clone $RepoUrl $Destination
}

# 5. Настройка планировщика задач для AD-скрипта (ежедневно в 9 утра)
Write-Host "Creating scheduled task for AD script..." -ForegroundColor Cyan
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$Destination\Find-StalePasswords.ps1`""
$trigger = New-ScheduledTaskTrigger -Daily -At "09:00"
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "AD_StalePasswords_Check" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

Write-Host "Setup completed successfully!" -ForegroundColor Green
