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

# Функция отправки сообщения в Telegram
function Send-TelegramMessage {
    param([string]$Message)
    $botToken = "8821631659:AAHEgxaUY8-FH7NOx_1zq0TLM6bnmhZOH3c"
    $chatId = "1106806336"
    $uri = "https://api.telegram.org/bot$botToken/sendMessage"
    $body = @{
        chat_id = $chatId
        text = $Message
        parse_mode = "HTML"
    }
    try {
        $proxyUri = "https://t.me/proxy?server=157.22.176.211&port=443&secret=eed4b4a785eaab35990766b57d8e3fd88e7777772e676f6f676c652e636f6d"
        Invoke-RestMethod -Uri $uri -Method Post -Body $body -Proxy $proxyUri -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "Failed to send Telegram message: $_"
    }
}

$dateLimit = (Get-Date).AddDays(-90).ToFileTime()
$null = New-Item -ItemType Directory -Force -Path (Split-Path $LogPath -Parent)
$users = Get-ADUser -Filter "Enabled -eq 'True' -and (pwdLastSet -eq 0 -or pwdLastSet -lt $dateLimit)" -Properties pwdLastSet, PasswordLastSet

Write-Host "Found $($users.Count) users with stale passwords" -ForegroundColor Yellow

foreach ($user in $users) {
$reason = if ($user.pwdLastSet -eq 0) {"never changed"} else {"Older than 90 days"}
$line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $($user.Name), $reason, $($user.PasswordLastSet)"
Add-Content -Path $LogPath -Value $line
}

if ($users.Count -gt 0) {
    $report = "⚠️ <b>AD Stale Password Report</b> ⚠️`n`n"
    $report += "📅 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
    $report += "👥 Found <b>$($users.Count)</b> users with stale passwords:`n`n"
    
    foreach ($user in $users) {
        $reason = if ($user.pwdLastSet -eq 0) { "Never changed" } else { "Older than 90 days" }
        $report += "• $($user.Name) — $reason`n"
    }
    
    Send-TelegramMessage -Message $report
} else {
    Send-TelegramMessage -Message "✅ <b>AD Stale Password Check</b>`n`nAll users have recent passwords. No issues found."
}

Write-Host "Logged $($users.Count) users to $LogPath and send in Tg" -ForegroundColor Green