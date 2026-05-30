<#
.SYNOPSIS
Находит пользователей АДа с паролями старше 90 дней или никогда не менявшимися
.DESCROPTION
Скрипт для лаборатории АДа. Ищет включённых пользователей, у которых есть pwdLastSet = 0 (никогда не меняли) или pwdLastSet старше 90 дней.
Результаты пишет в лог-файл.
.EXAMPLE
.\Find-StalePasswords.ps1
#>

param(
[string]$LogPath = "C:\AD_Scripts\expired_Passwords.log"
)

$dateLimit = (Get-Date).AddDays(-90).ToFileTime()
$null = New-Item -ItemType Directory -Force -Path (Split-Path $LogPath -Parent)
$users = Get-ADUser -Filter "Enabled -eq 'True' -and (pwdLastSet -eq 0 -or pwdLastSet -lt $dateLimit)" -Properties pwdLastSet, PasswordLastSet

foreach ($user in $users) {
$reason = if ($user.pwdLastSet -eq 0) {"never changed"} else {"Older than 90 days"}
$line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $($user.Name), $reason, $($user.PasswordLastSet)"
Add-Content -Path $LogPath -Value $line
}

Write-Host "Logged $($users.Count) users to $LogPath" -ForegroundColor Green