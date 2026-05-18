$ErrorActionPreference = "Stop"

$vars = @{}
Get-Content ".dev.vars" | ForEach-Object {
    if ($_ -match "^(.*?)=(.*)$") {
        $vars[$matches[1]] = $matches[2]
    }
}

$token = $vars["CLOUDFLARE_API_TOKEN"]
$accountId = $vars["CLOUDFLARE_ACCOUNT_ID"]
$bucket = "soundscape-tiles"
$key = "pmtiles/hongkong-z16.pmtiles"
$filePath = "./output/hongkong-z16.pmtiles"

if (-not $token) { throw "CLOUDFLARE_API_TOKEN missing in .dev.vars" }
if (-not $accountId) { throw "CLOUDFLARE_ACCOUNT_ID missing in .dev.vars" }
if (-not (Test-Path $filePath)) { throw "PMTiles file not found: $filePath" }

$headers = @{ Authorization = "Bearer $token" }
$base = "https://api.cloudflare.com/client/v4/accounts/$accountId/r2/buckets/$bucket/objects"

$deleted = 0
$listResp = Invoke-RestMethod -Method Get -Uri $base -Headers $headers
if (-not $listResp.success) {
    throw "List objects failed"
}

$objects = @($listResp.result)
foreach ($obj in $objects) {
    $objKey = [string]$obj.key
    if (-not $objKey) {
        continue
    }

    $encodedKey = [uri]::EscapeDataString($objKey).Replace("%2F", "/")
    $delResp = Invoke-RestMethod -Method Delete -Uri "$base/$encodedKey" -Headers $headers
    if (-not $delResp.success) {
        throw "Delete failed for key: $objKey"
    }
    $deleted++
}

Write-Host "Deleted objects: $deleted"

$uploadKey = [uri]::EscapeDataString($key).Replace("%2F", "/")
$uploadResp = Invoke-RestMethod -Method Put -Uri "$base/$uploadKey" -Headers $headers -InFile $filePath -ContentType "application/octet-stream"
if (-not $uploadResp.success) {
    throw "Upload failed"
}

Write-Host "Uploaded key: $key"
Write-Host "R2 URL: https://$accountId.r2.cloudflarestorage.com/$bucket/$key"
