# Hong Kong PMTiles Offline Generation

This directory contains scripts and configuration for generating PMTiles for Hong Kong offline and uploading to Cloudflare R2.

## Prerequisites

- Docker Desktop (Windows)
- Python 3.11+
- PowerShell 5.0+
- AWS CLI (for R2 upload)
- IMPOSM3 (will be auto-downloaded)

## Installation

### 1. Install Python dependencies

```powershell
pip install psycopg2-binary pmtiles
```

### 2. Install AWS CLI (if not already installed)

```powershell
pip install awscli
# or via chocolatey: choco install awscliv2
```

### 3. Configure Cloudflare R2 credentials

```powershell
$env:R2_ACCESS_KEY_ID = "your-r2-access-key"
$env:R2_SECRET_ACCESS_KEY = "your-r2-secret-key"
$env:R2_ENDPOINT_URL = "https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com"
```

To find your R2 endpoint:
- Go to Cloudflare dashboard → R2 → Settings
- Copy your "S3 API endpoint"

## Quick Start

### Step 1: Download and Ingest Hong Kong OSM Data

```powershell
cd offline-hk
.\ingest-hk.ps1
```

This script will:
1. Start PostgreSQL + PostGIS in Docker
2. Download Hong Kong OSM data from Geofabrik (~27 MB)
3. Run IMPOSM3 to ingest into PostGIS
4. Install SoundScape SQL functions (tilefunc.sql)

**Estimated time: 10-20 minutes**

### Step 2: Generate PMTiles

```powershell
python generate-pmtiles.py
```

This will:
1. Connect to local PostgreSQL
2. Query all tiles in Hong Kong (zoom 16)
3. Generate `output/hongkong-z16.pmtiles`

**Estimated time: 5-15 minutes**

The PMTiles file will be ~50-150 MB depending on data density.

### Step 3: Upload to Cloudflare R2

```powershell
.\upload-to-r2.ps1
```

Or manually:
```powershell
$env:AWS_ACCESS_KEY_ID = "..."
$env:AWS_SECRET_ACCESS_KEY = "..."
aws s3 cp ./output/hongkong-z16.pmtiles s3://soundscape-tiles/pmtiles/ `
  --endpoint-url https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
```

## Configuration

Edit `.env` file to customize:

```env
# Bounding box
HK_MIN_LAT=22.15
HK_MAX_LAT=22.57
HK_MIN_LON=113.82
HK_MAX_LON=114.44

# Zoom level (currently 16)
HK_ZOOM=16

# Output
OUTPUT_DIR=./output
PMTILES_FILE=hongkong-z16.pmtiles
```

## Architecture

```
┌─────────────────────┐
│ Hong Kong OSM Data  │  (Geofabrik)
│ ~27 MB PBF         │
└──────────┬──────────┘
           │ wget
           ▼
┌─────────────────────┐
│   IMPOSM3 Import    │
│ (Windows native)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ PostgreSQL + PostGIS│  (Docker)
│ Tables:             │
│ - osm_roads         │
│ - osm_places        │
│ - osm_entrances     │
└──────────┬──────────┘
           │ soundscape_tile()
           ▼
┌─────────────────────┐
│ generate-pmtiles.py │
│ All tiles (z16)     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ hongkong-z16.pmtiles│  (~100 MB)
│ Local output/       │
└──────────┬──────────┘
           │ aws s3 sync
           ▼
┌─────────────────────┐
│ Cloudflare R2       │
│ s3://soundscape-    │
│ tiles/pmtiles/      │
└─────────────────────┘
```

## Docker Commands (Manual)

If you need to manage Docker containers manually:

```powershell
# Start containers
docker-compose up -d

# Stop containers
docker-compose down

# View logs
docker-compose logs -f postgres

# Connect to PostgreSQL
docker-compose exec postgres psql -U osm -d osm

# Clean up everything (including volumes)
docker-compose down -v
```

## Troubleshooting

### PostgreSQL connection refused
- Ensure Docker Desktop is running
- Check if port 5432 is available: `netstat -ano | findstr :5432`
- Wait 10-15 seconds for container to fully start

### IMPOSM import errors
- Ensure mapping.yml path is correct
- Check disk space (needs ~2-3 GB temporary)
- Verify PBF file is not corrupted

### PMTiles generation slow
- Normal for first run (~30k tiles at z16)
- Progress shown every 100 tiles
- Check database query performance: `docker-compose exec postgres pg_stat_statements`

### R2 upload fails
- Verify credentials are correct
- Check endpoint URL format (should include account ID)
- Ensure R2 bucket exists

## What's Generated

### PostgreSQL Tables (in Docker)
- `osm_roads` - Road/path geometries from OSM ways
- `osm_places` - POI/building geometries from OSM nodes/ways/relations
- `osm_entrances` - Building entrance points

### PMTiles File
Single file containing all zoom-16 tiles for Hong Kong bounding box.

Each tile in PMTiles is stored as:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "osm_ids": [123456],
        "feature_type": "highway",
        "feature_value": "primary",
        // ... all OSM tags
      },
      "geometry": { "type": "Point|LineString|Polygon", ... }
    }
    // ... more features
  ]
}
```

## Next Steps

After PMTiles are uploaded to R2:

1. **Update AlaVia Worker** to serve from `TILES_BUCKET`
   - Path: `/tiles/16/{x}/{y}.json`
   - Source: R2 PMTiles
   - For non-Hong Kong: fallback to Neon PostGIS

2. **Update SoundScape iOS app** to use Cloudflare Worker
   - Change service endpoint to `https://via.inclu.si`

3. **Monitor usage** via D1
   - Track which tiles are most frequently requested
   - Schedule regular updates (weekly/monthly)

## Cost Estimate

For Hong Kong at zoom 16:
- Tile count: ~30,000
- PMTiles size: ~100-150 MB
- R2 storage: < $0.01/month
- R2 reads: < $0.01/month (if < 1M requests)
- Total: < $0.05/month

## References

- [PMTiles Spec](https://github.com/protomaps/PMTiles)
- [IMPOSM3 Docs](https://imposm.org/)
- [Cloudflare R2 Docs](https://developers.cloudflare.com/r2/)
- [SoundScape Backend](../README.md)
