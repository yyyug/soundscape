# Upload PMTiles to Cloudflare R2
param(
    [string]$PMTilesFile = "./output/hongkong-z16.pmtiles",
    [string]$R2BucketName = "soundscape-tiles",
    [string]$R2KeyPrefix = "pmtiles",
    [string]$AwsAccessKeyId = $env:R2_ACCESS_KEY_ID,
    [string]$AwsSecretAccessKey = $env:R2_SECRET_ACCESS_KEY,
    [string]$R2EndpointUrl = $env:R2_ENDPOINT_URL,
    [string]$CloudflareAccountId = $env:CLOUDFLARE_ACCOUNT_ID
)

$ErrorActionPreference = "Stop"

# Colors
$Info = "Cyan"
$Success = "Green"
$Error = "Red"

function Write-Info { Write-Host "[INFO]" -ForegroundColor $Info -NoNewline; Write-Host " $args" }
function Write-Success { Write-Host "[SUCCESS]" -ForegroundColor $Success -NoNewline; Write-Host " $args" }
function Write-Error { Write-Host "[ERROR]" -ForegroundColor $Error -NoNewline; Write-Host " $args" }

Write-Info "Cloudflare R2 Upload Script"
Write-Info "============================"

# Validate inputs
if (-not (Test-Path $PMTilesFile)) {
    Write-Error "PMTiles file not found: $PMTilesFile"
    exit 1
}

if (-not $AwsAccessKeyId -or -not $AwsSecretAccessKey) {
    Write-Error "AWS credentials not set. Please set R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY environment variables"
    exit 1
}

if (-not $R2EndpointUrl) {
    Write-Error "R2_ENDPOINT_URL not set"
    Write-Info "Set it with: \$env:R2_ENDPOINT_URL='https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com'"
    exit 1
}

# Configure AWS CLI for R2
Write-Info "Configuring AWS CLI for R2..."
$env:AWS_ACCESS_KEY_ID = $AwsAccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $AwsSecretAccessKey

# Upload file
$R2Key = "$R2KeyPrefix/hongkong-z16.pmtiles"
$FileSize = (Get-Item $PMTilesFile).Length / (1024 * 1024)

Write-Info "Uploading PMTiles to R2..."
Write-Info "  Bucket: $R2BucketName"
Write-Info "  Key: $R2Key"
Write-Info "  Size: $FileSize MB"
Write-Info "  Endpoint: $R2EndpointUrl"

try {
    aws s3 cp $PMTilesFile "s3://$R2BucketName/$R2Key" `
        --endpoint-url $R2EndpointUrl `
        --region auto `
        --metadata "generated=$(Get-Date -Format 'yyyy-MM-dd\THH:mm:ssZ'),source=soundscape-hongkong"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Upload failed"
        exit 1
    }
    
    Write-Success "PMTiles uploaded successfully!"
    Write-Info "R2 URL: $R2EndpointUrl/$R2BucketName/$R2Key"
    
} catch {
    Write-Error "Upload failed: $_"
    exit 1
}

Write-Success "Done!"
