#!/usr/bin/env python3
"""
Generate PMTiles from SoundScape PostGIS tiles for Hong Kong.
Requires: psycopg2, pmtiles
"""

import os
import sys
import json
import math
import gzip
import logging
from datetime import datetime
from pathlib import Path

try:
    import psycopg2
    from psycopg2.extras import NamedTupleCursor
except ImportError:
    print("ERROR: psycopg2 not installed. Run: pip install psycopg2-binary")
    sys.exit(1)

try:
    from pmtiles.writer import write
    from pmtiles.tile import zxy_to_tileid, Compression, TileType
except ImportError:
    print("ERROR: pmtiles not installed. Run: pip install pmtiles")
    sys.exit(1)

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def normalize_json(value):
    if value is None:
        return None
    if isinstance(value, (dict, list)):
        return value
    if isinstance(value, str):
        return json.loads(value)
    return value


class PMTilesGenerator:
    def __init__(self, dsn, min_lat, max_lat, min_lon, max_lon, zoom=16, output_file='hongkong.pmtiles'):
        self.dsn = dsn
        self.min_lat = min_lat
        self.max_lat = max_lat
        self.min_lon = min_lon
        self.max_lon = max_lon
        self.zoom = zoom
        self.output_file = output_file
        self.tile_count = 0
        self.error_count = 0

    def deg2num(self, lat, lon, zoom):
        """Convert lat/lon to tile x/y at zoom level."""
        lat_rad = math.radians(lat)
        n = 2 ** zoom
        x = int((lon + 180) / 360 * n)
        y = int((1 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2 * n)
        return x, y

    def get_tile_range(self):
        """Calculate tile range for bounding box."""
        # NW corner
        nw_x, nw_y = self.deg2num(self.max_lat, self.min_lon, self.zoom)
        # SE corner
        se_x, se_y = self.deg2num(self.min_lat, self.max_lon, self.zoom)
        return nw_x, nw_y, se_x, se_y

    def fetch_tile(self, conn, x, y):
        """Query a single tile from PostGIS."""
        try:
            with conn.cursor(cursor_factory=NamedTupleCursor) as cur:
                cur.execute(
                    "SELECT * FROM soundscape_tile(%s, %s, %s)",
                    (self.zoom, x, y)
                )
                rows = cur.fetchall()
                if not rows:
                    return None
                
                features = []
                for row in rows:
                    feature = {
                        'type': 'Feature',
                        'osm_ids': row.osm_ids if row.osm_ids else [],
                        'feature_type': row.feature_type,
                        'feature_value': row.feature_value,
                        'geometry': normalize_json(row.geometry),
                        'properties': normalize_json(row.properties) if row.properties else {}
                    }
                    features.append(feature)
                
                return {
                    'type': 'FeatureCollection',
                    'features': features
                }
        except Exception as e:
            logger.error(f"Error fetching tile {self.zoom}/{x}/{y}: {e}")
            self.error_count += 1
            return None

    def generate(self):
        """Main generation process."""
        logger.info(f"Connecting to PostgreSQL: {self.dsn}")
        try:
            conn = psycopg2.connect(self.dsn)
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL: {e}")
            sys.exit(1)

        min_x, min_y, max_x, max_y = self.get_tile_range()
        total_tiles = (max_x - min_x + 1) * (max_y - min_y + 1)
        
        logger.info(f"Generating PMTiles for Hong Kong")
        logger.info(f"Zoom: {self.zoom}")
        logger.info(f"Tile range X: {min_x} to {max_x}, Y: {min_y} to {max_y}")
        logger.info(f"Total tiles to generate: {total_tiles}")
        
        start_time = datetime.now()
        
        try:
            with write(self.output_file) as writer:
                for x in range(min_x, max_x + 1):
                    for y in range(min_y, max_y + 1):
                        tile_data = self.fetch_tile(conn, x, y)
                        
                        if tile_data:
                            tile_bytes = json.dumps(tile_data, separators=(',', ':')).encode('utf-8')
                            compressed = gzip.compress(tile_bytes)
                            tile_id = zxy_to_tileid(self.zoom, x, y)
                            
                            try:
                                writer.write_tile(tile_id, compressed)
                                self.tile_count += 1
                                
                                if self.tile_count % 100 == 0:
                                    logger.info(f"Progress: {self.tile_count}/{total_tiles} tiles")
                            except Exception as e:
                                logger.error(f"Error writing tile {self.zoom}/{x}/{y}: {e}")
                                self.error_count += 1

                header = {
                    "tile_compression": Compression.GZIP,
                    "tile_type": TileType.UNKNOWN,
                    "min_lon_e7": int(self.min_lon * 10_000_000),
                    "min_lat_e7": int(self.min_lat * 10_000_000),
                    "max_lon_e7": int(self.max_lon * 10_000_000),
                    "max_lat_e7": int(self.max_lat * 10_000_000),
                    "center_zoom": self.zoom,
                    "center_lon_e7": int(((self.min_lon + self.max_lon) / 2) * 10_000_000),
                    "center_lat_e7": int(((self.min_lat + self.max_lat) / 2) * 10_000_000),
                }
                metadata = {
                    "name": "SoundScape Hong Kong",
                    "description": "Zoom 16 SoundScape GeoJSON tiles for Hong Kong",
                    "version": "1",
                    "format": "json",
                    "generator": "soundscape-offline-hk",
                    "bounds": [self.min_lon, self.min_lat, self.max_lon, self.max_lat],
                    "minzoom": self.zoom,
                    "maxzoom": self.zoom,
                }
                writer.finalize(header, metadata)
                logger.info(f"PMTiles finalized: {self.output_file}")
            
        finally:
            conn.close()

        elapsed = (datetime.now() - start_time).total_seconds()
        logger.info(f"\nGeneration complete:")
        logger.info(f"  Tiles generated: {self.tile_count}")
        logger.info(f"  Errors: {self.error_count}")
        logger.info(f"  Time elapsed: {elapsed:.2f}s")
        logger.info(f"  Output file: {self.output_file}")
        
        if self.tile_count > 0:
            file_size = os.path.getsize(self.output_file) / (1024 * 1024)
            logger.info(f"  File size: {file_size:.2f} MB")
            return True
        else:
            logger.error("No tiles generated!")
            return False


def main():
    # Read from environment or use defaults
    dsn = os.getenv('LOCAL_DSN_WINDOWS', 'postgresql://osm:osm@localhost:5432/osm')
    min_lat = float(os.getenv('HK_MIN_LAT', 22.15))
    max_lat = float(os.getenv('HK_MAX_LAT', 22.57))
    min_lon = float(os.getenv('HK_MIN_LON', 113.82))
    max_lon = float(os.getenv('HK_MAX_LON', 114.44))
    zoom = int(os.getenv('HK_ZOOM', 16))
    output_dir = os.getenv('OUTPUT_DIR', './output')
    pmtiles_file = os.getenv('PMTILES_FILE', 'hongkong-z16.pmtiles')
    
    # Create output directory if it doesn't exist
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    output_path = os.path.join(output_dir, pmtiles_file)
    
    logger.info(f"Hong Kong PMTiles Generator")
    logger.info(f"Bounding box: lat [{min_lat}, {max_lat}], lon [{min_lon}, {max_lon}]")
    
    generator = PMTilesGenerator(
        dsn=dsn,
        min_lat=min_lat,
        max_lat=max_lat,
        min_lon=min_lon,
        max_lon=max_lon,
        zoom=zoom,
        output_file=output_path
    )
    
    success = generator.generate()
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
