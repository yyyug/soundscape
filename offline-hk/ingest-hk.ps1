# Hong Kong OSM data ingestion script for Windows PowerShell
# This script downloads Hong Kong OSM data and ingests it into PostGIS

param(
    [string]$DockerComposePath = ".",
    [string]$DataDir = "./data",
    [string]$PBFUrl = "https://download.geofabrik.de/asia/china/hong-kong-latest.osm.pbf",
    [string]$ImposomVersion = "0.11.1"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OfflineRoot = (Resolve-Path $PSScriptRoot).Path
$ImposmImage = "soundscape-offline-imposm:0.11.1"

# Colors for output
$Info = "Cyan"
$Success = "Green"
$Error = "Red"
$Warning = "Yellow"

function Write-Info { Write-Host "[INFO]" -ForegroundColor $Info -NoNewline; Write-Host " $args" }
function Write-Success { Write-Host "[SUCCESS]" -ForegroundColor $Success -NoNewline; Write-Host " $args" }
function Write-Error { Write-Host "[ERROR]" -ForegroundColor $Error -NoNewline; Write-Host " $args" }
function Write-Warning { Write-Host "[WARNING]" -ForegroundColor $Warning -NoNewline; Write-Host " $args" }

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function Resolve-DockerCli {
    $cmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $fallback = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
    if (Test-Path $fallback) {
        return $fallback
    }

    throw "Docker CLI not found. Install Docker Desktop or add docker.exe to PATH."
}

Write-Info "Hong Kong OSM Data Ingestion Script"
Write-Info "===================================="

$DockerExe = Resolve-DockerCli

# Step 1: Start Docker containers
Write-Info "Step 1: Starting Docker containers..."
try {
    Invoke-Checked -FilePath $DockerExe `
        -Arguments @("compose", "-f", "$DockerComposePath\docker-compose.yml", "up", "-d") `
        -ErrorMessage "Failed to start Docker containers"
    Write-Success "Docker containers started"
} catch {
    Write-Error "Failed to start Docker containers: $_"
    exit 1
}

# Wait for PostgreSQL to be ready
Write-Info "Waiting for PostgreSQL to be ready..."
$maxAttempts = 30
$attempt = 0
while ($attempt -lt $maxAttempts) {
    try {
        Invoke-Checked -FilePath $DockerExe `
            -Arguments @("compose", "-f", "$DockerComposePath\docker-compose.yml", "exec", "-T", "postgres", "pg_isready", "-U", "osm") `
            -ErrorMessage "PostgreSQL is not ready yet"
        Write-Success "PostgreSQL is ready"
        break
    } catch {
        $attempt++
        Start-Sleep -Seconds 2
        if ($attempt -eq $maxAttempts) {
            Write-Error "PostgreSQL did not become ready in time"
            exit 1
        }
    }
}

# Ensure bootstrap SQL is applied even when the Docker volume already exists.
Write-Info "Applying SQL bootstrap (extensions + TileBBox + soundscape_tile)..."
Get-Content "$OfflineRoot\init-db.sql" -Raw | & $DockerExe exec -i soundscape-hk-postgis psql -U osm -d osm
if ($LASTEXITCODE -ne 0) { throw "Failed applying init-db.sql" }
Get-Content "$OfflineRoot\postgis-vt-util.sql" -Raw | & $DockerExe exec -i soundscape-hk-postgis psql -U osm -d osm
if ($LASTEXITCODE -ne 0) { throw "Failed applying postgis-vt-util.sql" }
Get-Content "$RepoRoot\svcs\data\tilefunc.sql" -Raw | & $DockerExe exec -i soundscape-hk-postgis psql -U osm -d osm
if ($LASTEXITCODE -ne 0) { throw "Failed applying svcs/data/tilefunc.sql" }
Write-Success "SQL bootstrap applied"

# Step 2: Download OSM PBF
Write-Info "Step 2: Downloading Hong Kong OSM data..."
$PBFFile = "$DataDir\hong-kong-latest.osm.pbf"
if (-not (Test-Path $PBFFile)) {
    try {
        mkdir -Force $DataDir | Out-Null
        Write-Info "Downloading from: $PBFUrl"
        & curl.exe -L --fail --output $PBFFile $PBFUrl
        Write-Success "OSM data downloaded: $PBFFile"
    } catch {
        Write-Error "Failed to download OSM data: $_"
        exit 1
    }
} else {
    Write-Warning "OSM data already exists at $PBFFile, skipping download"
}

$FileSize = (Get-Item $PBFFile).Length / 1MB
Write-Info "File size: $FileSize MB"

# Step 3: Build Linux IMPOSM image
Write-Info "Step 3: Building Dockerized IMPOSM3 image..."
try {
    Invoke-Checked -FilePath $DockerExe `
        -Arguments @("build", "--build-arg", "IMPOSM_VERSION=$ImposomVersion", "-t", $ImposmImage, "-f", "$OfflineRoot\Dockerfile.imposm", "$OfflineRoot") `
        -ErrorMessage "Failed to build IMPOSM3 image"
    Write-Success "IMPOSM3 image ready"
} catch {
    Write-Error "Failed to build IMPOSM3 image: $_"
    exit 1
}

# Step 4: Run IMPOSM import
Write-Info "Step 4: Importing OSM data with IMPOSM3..."
$MappingFile = "/repo/svcs/data/soundscape/other/mapping.yml"
$PBFFileLinux = "/repo/offline-hk/data/hong-kong-latest.osm.pbf"
$CacheDir = "/repo/offline-hk/imposm_cache"
$DiffDir = "/repo/offline-hk/imposm_diff"
$ConnectionUrl = "postgis://osm:osm@postgres:5432/osm?sslmode=disable"

mkdir -Force "$OfflineRoot\imposm_cache", "$OfflineRoot\imposm_diff" | Out-Null

try {
    # Read stage
    Write-Info "  - IMPOSM read stage..."
    Invoke-Checked -FilePath $DockerExe `
        -Arguments @("run", "--rm", "-v", "${RepoRoot}:/repo", "--network", "offline-hk_soundscape", $ImposmImage, "import", "-mapping", $MappingFile, "-read", $PBFFileLinux, "-srid", "4326", "-overwritecache", "-cachedir", $CacheDir) `
        -ErrorMessage "IMPOSM read stage failed"
    Write-Success "  - IMPOSM read complete"
    
    # Write stage
    Write-Info "  - IMPOSM write stage..."
    Invoke-Checked -FilePath $DockerExe `
        -Arguments @("run", "--rm", "-v", "${RepoRoot}:/repo", "--network", "offline-hk_soundscape", $ImposmImage, "import", "-mapping", $MappingFile, "-write", "-connection", $ConnectionUrl, "-srid", "4326", "-cachedir", $CacheDir) `
        -ErrorMessage "IMPOSM write stage failed"
    Write-Success "  - IMPOSM write complete"
    
    # Deploy production stage
    Write-Info "  - IMPOSM deployproduction stage..."
    Invoke-Checked -FilePath $DockerExe `
        -Arguments @("run", "--rm", "-v", "${RepoRoot}:/repo", "--network", "offline-hk_soundscape", $ImposmImage, "import", "-mapping", $MappingFile, "-connection", $ConnectionUrl, "-srid", "4326", "-deployproduction", "-cachedir", $CacheDir) `
        -ErrorMessage "IMPOSM deployproduction stage failed"
    Write-Success "IMPOSM ingestion complete"
    
} catch {
    Write-Error "IMPOSM import failed: $_"
    exit 1
}

Write-Success "Hong Kong OSM data ingestion complete!"
Write-Info "Next step: Run 'python generate-pmtiles.py' to generate PMTiles"
