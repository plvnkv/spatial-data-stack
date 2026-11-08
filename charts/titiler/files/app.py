import json
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from titiler.core.factory import TilerFactory

from catalog import resolve_asset

assets = json.loads(Path("/etc/titiler/assets.json").read_text())
app = FastAPI()


def catalog_path(request: Request, asset: str) -> str:
    if "url" in request.query_params:
        raise HTTPException(status_code=400, detail="Use a catalog asset ID")
    path = resolve_asset(assets, asset)
    if path is None:
        raise HTTPException(status_code=404, detail="Unknown raster")
    return path


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/catalog")
def catalog() -> list[str]:
    return sorted(assets)


app.include_router(TilerFactory(path_dependency=catalog_path, router_prefix="/cog").router, prefix="/cog")
