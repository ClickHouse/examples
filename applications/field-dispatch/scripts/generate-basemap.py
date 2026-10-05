"""Generate a tiny, wholly synthetic vector PMTiles basemap (no OSM data)."""
import gzip
import math
from pathlib import Path

import mapbox_vector_tile
from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import Writer
from shapely.geometry import LineString, box
from shapely.ops import transform

ROOT = Path(__file__).resolve().parents[1]
WORLD = 20037508.342789244
EXTENT = (-1.51, 53.33, -1.41, 53.41)


def mercator(lon, lat):
    return lon * WORLD / 180, math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * WORLD / math.pi


def tile_xy(lon, lat, zoom):
    scale = 2 ** zoom
    return int((lon + 180) / 360 * scale), int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * scale)


def feature(geometry, kind, identifier):
    return {"geometry": transform(mercator, geometry), "properties": {"kind": kind}, "id": identifier}


roads = []
for i in range(10):
    lon = -1.495 + i * 0.006
    roads.append(feature(LineString([(lon, 53.343), (lon + 0.003, 53.400)]), "minor", i + 1))
for i in range(9):
    lat = 53.346 + i * 0.006
    roads.append(feature(LineString([(-1.501, lat), (-1.435, lat + 0.001)]), "main" if i in (2, 6) else "minor", i + 20))
land = []
for x in range(8):
    for y in range(7):
        lon, lat = -1.493 + x * 0.006, 53.349 + y * 0.006
        land.append(feature(box(lon, lat, lon + 0.003, lat + 0.002), "park" if (x + y) % 7 == 0 else "block", 100 + x * 10 + y))
water = [feature(LineString([(-1.469, 53.340), (-1.466, 53.360), (-1.462, 53.380), (-1.458, 53.402)]), "river", 500)]

output = ROOT / "public" / "maintenance-town.pmtiles"
output.parent.mkdir(exist_ok=True)
with output.open("wb") as stream:
    writer = Writer(stream)
    tiles = []
    for zoom in range(12, 15):
        west, south, east, north = EXTENT
        min_x, min_y = tile_xy(west, north, zoom)
        max_x, max_y = tile_xy(east, south, zoom)
        for x in range(min_x, max_x + 1):
            for y in range(min_y, max_y + 1):
                size = 2 * WORLD / 2 ** zoom
                bounds = (-WORLD + x * size, WORLD - (y + 1) * size, -WORLD + (x + 1) * size, WORLD - y * size)
                clip = box(*bounds)
                layers = []
                for name, source in [("roads", roads), ("land", land), ("water", water)]:
                    clipped = []
                    for original in source:
                        geometry = original["geometry"].intersection(clip)
                        if not geometry.is_empty and geometry.geom_type in ("Polygon", "MultiPolygon", "LineString", "MultiLineString"):
                            clipped.append({**original, "geometry": geometry})
                    layers.append({"name": name, "features": clipped})
                encoded = mapbox_vector_tile.encode(layers, default_options={"quantize_bounds": bounds, "extents": 4096})
                tiles.append((zxy_to_tileid(zoom, x, y), gzip.compress(encoded, mtime=0)))
    for tileid, encoded in sorted(tiles):
        writer.write_tile(tileid, encoded)
    writer.finalize({"tile_type": TileType.MVT, "tile_compression": Compression.GZIP,
                     "min_lon_e7": int(EXTENT[0] * 1e7), "min_lat_e7": int(EXTENT[1] * 1e7),
                     "max_lon_e7": int(EXTENT[2] * 1e7), "max_lat_e7": int(EXTENT[3] * 1e7),
                     "center_zoom": 14, "center_lon_e7": -14670000, "center_lat_e7": 533730000},
                    {"name": "Synthetic maintenance town", "description": "Generated fictional streets, blocks and parks. No real map data.",
                     "attribution": "Synthetic map data · ClickHouse examples", "vector_layers": [{"id": name, "fields": {"kind": "String"}, "minzoom": 12, "maxzoom": 14} for name in ["roads", "land", "water"]]})
print(f"Generated {len(tiles)} vector tiles, {output.stat().st_size} bytes: {output.name}")
