CREATE OR REPLACE FUNCTION TileBBox(z integer, x integer, y integer, srid integer DEFAULT 3857)
RETURNS geometry
AS $$
DECLARE
  n numeric := power(2.0, z);
  west numeric := x / n * 360.0 - 180.0;
  east numeric := (x + 1) / n * 360.0 - 180.0;
  north numeric := degrees(atan(sinh(pi() * (1 - 2 * y / n))));
  south numeric := degrees(atan(sinh(pi() * (1 - 2 * (y + 1) / n))));
BEGIN
  RETURN ST_Transform(ST_MakeEnvelope(west, south, east, north, 4326), srid);
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;
