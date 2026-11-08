import importlib.util
import unittest
from pathlib import Path


class RasterCatalogTests(unittest.TestCase):
    def test_only_catalog_asset_ids_resolve(self):
        source = Path(__file__).resolve().parents[1] / "charts/titiler/files/catalog.py"
        self.assertTrue(source.is_file(), "Raster catalog implementation is missing")
        spec = importlib.util.spec_from_file_location("raster_catalog", source)
        catalog = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(catalog)
        assets = {"sample-raster": "samples/example.tif"}
        self.assertEqual(catalog.resolve_asset(assets, "sample-raster"), "s3://cog/samples/example.tif")
        for value in ("https://example.org/file.tif", "../sample-raster", "missing", ""):
            self.assertIsNone(catalog.resolve_asset(assets, value))
        for key in ("../other.tif", "/other.tif", "https://example.org/file.tif"):
            self.assertIsNone(catalog.resolve_asset({"sample-raster": key}, "sample-raster"))


if __name__ == "__main__":
    unittest.main()
