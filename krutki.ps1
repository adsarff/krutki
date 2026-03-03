$logPath = "$env:USERPROFILE\AppData\LocalLow\Gryphline\Endfield\sdklogs\HGWebview.log"

if (!(Test-Path $logPath)) {
    Write-Host "HGWebview.log не найден!" -ForegroundColor Red
    exit
}

Write-Host "Scanning log for token..." -ForegroundColor Cyan

# Читаем лог и убираем переносы строк
$logContent = (Get-Content $logPath -Raw) -replace "`r|`n",""

# Ищем URL с gacha_char
$regex = "https://ef-webview\.gryphline\.com/page/gacha_char\?[^\s]+"

$matches = [regex]::Matches($logContent, $regex)

if ($matches.Count -eq 0) {
    Write-Host "URL с токеном не найден!" -ForegroundColor Red
    exit
}

$lastUrl = $matches[$matches.Count - 1].Value

Write-Host "Found full URL"

$uri = [System.Uri]$lastUrl
$queryParams = @{}

foreach ($pair in $uri.Query.TrimStart("?").Split("&")) {
    $kv = $pair.Split("=")
    if ($kv.Count -eq 2) {
        $queryParams[$kv[0]] = $kv[1]
    }
}

$token = $queryParams["u8_token"]
if (!$token) { $token = $queryParams["token"] }

# ВАЖНО: в логе параметр называется server, а API требует server_id
$serverId = $queryParams["server"]
$lang = $queryParams["lang"]

if (!$token -or !$serverId) {
    Write-Host "Не удалось извлечь token или server!" -ForegroundColor Red
    exit
}

Write-Host "Token успешно найден" -ForegroundColor Green
Write-Host "Server ID: $serverId"
Write-Host "Lang: $lang"

# ==========================================
# НАСТРОЙКА ЗАПРОСОВ
# ==========================================

$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    "Referer"    = "https://ef-webview.gryphline.com/page/gacha_char"
    "Origin"     = "https://ef-webview.gryphline.com"
    "Accept"     = "application/json, text/plain, */*"
}

$pools = @(
    "E_CharacterGachaPoolType_Beginner",
    "E_CharacterGachaPoolType_Standard",
    "E_CharacterGachaPoolType_Special"
)

$allPulls = @()

# ==========================================
# СКАЧИВАНИЕ ИСТОРИИ
# ==========================================

foreach ($pool in $pools) {

    Write-Host "`nFetching pool: $pool" -ForegroundColor Cyan

    $firstUrl = "https://ef-webview.gryphline.com/api/record/char?lang=$lang&pool_type=$pool&token=$token&server_id=$serverId"

    try {
        $firstResponse = Invoke-RestMethod -Uri $firstUrl -Headers $headers -TimeoutSec 15
    }
    catch {
        Write-Host "Failed to fetch first page for $pool"
        continue
    }

    if ($firstResponse.code -ne 0 -or !$firstResponse.data.list) {
        continue
    }

    $batch = $firstResponse.data.list
    $allPulls += $batch

    Write-Host "Loaded $($batch.Count) pulls (Total: $($allPulls.Count))"

    $hasMore = $firstResponse.data.hasMore

    if (!$hasMore) { continue }

    $seqId = $batch[-1].seqId

    while ($hasMore) {

        $apiUrl = "https://ef-webview.gryphline.com/api/record/char?lang=$lang&pool_type=$pool&token=$token&server_id=$serverId&seq_id=$seqId"

        Write-Host "Requesting seq_id=$seqId"

        try {
            $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15
        }
        catch {
            Write-Host "Request failed"
            break
        }

        if ($response.code -ne 0 -or !$response.data.list) {
            break
        }

        $batch = $response.data.list
        $allPulls += $batch

        Write-Host "Loaded $($batch.Count) pulls (Total: $($allPulls.Count))"

        $hasMore = $response.data.hasMore

        if ($hasMore -and $batch.Count -gt 0) {
            $seqId = $batch[-1].seqId
        }

        Start-Sleep -Milliseconds 300
    }
}

Write-Host "`nTOTAL ALL POOLS: $($allPulls.Count)" -ForegroundColor Green

# ==========================================
# СОХРАНЕНИЕ НА РАБОЧИЙ СТОЛ
# ==========================================

$desktopPath = [Environment]::GetFolderPath("Desktop")
$fileName = "endfield_full_pulls_$((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')).json"
$fullPath = Join-Path $desktopPath $fileName

$allPulls | ConvertTo-Json -Depth 10 | Out-File $fullPath -Encoding UTF8

Write-Host "Saved to: $fullPath" -ForegroundColor Green