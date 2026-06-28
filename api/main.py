"""
Reportes ZAJUNA — FastAPI application entry point.
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from api.config import settings
from api.database import init_control_db
from api.routers import auth, programados, reportes, solicitudes

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.secret_key == "change-me-in-production":
        raise RuntimeError("REPORTES_SECRET_KEY no configurado — cambia el valor por defecto en .env")
    init_control_db()
    logger.info("Reportes ZAJUNA iniciado. Puerto 8089.")
    yield


_docs_url = "/api/docs" if settings.docs_enabled else None
_redoc_url = "/api/redoc" if settings.docs_enabled else None

app = FastAPI(
    title="Reportes ZAJUNA",
    description="Sistema de reportes administrativos para Moodle/ZAJUNA",
    version="1.0.0",
    docs_url=_docs_url,
    redoc_url=_redoc_url,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(reportes.router)
app.include_router(solicitudes.router)
app.include_router(programados.router)


# ── Health ────────────────────────────────────────────────────────────────────

from datetime import datetime, timezone

@app.get("/api/health")
def health() -> dict:
    return {"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()}


# ── Frontend static assets + SPA ──────────────────────────────────────────────

from fastapi.responses import FileResponse

FRONTEND_DIR = Path(__file__).parent.parent / "frontend"

_STATIC_TYPES = {
    ".css": "text/css",
    ".js":  "application/javascript",
    ".ico": "image/x-icon",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".woff2": "font/woff2",
    ".woff":  "font/woff",
}


@app.get("/styles.css", include_in_schema=False)
def serve_css():
    return FileResponse(FRONTEND_DIR / "styles.css", media_type="text/css")


@app.get("/app.js", include_in_schema=False)
def serve_js():
    return FileResponse(FRONTEND_DIR / "app.js", media_type="application/javascript")


def _inject_base_path(html: str) -> str:
    base = settings.reportes_base_path.rstrip("/")
    return html.replace("__REPORTES_BASE__", base)


@app.get("/", response_class=HTMLResponse)
@app.get("/{path:path}", response_class=HTMLResponse, include_in_schema=False)
def serve_spa(path: str = "") -> HTMLResponse:
    index = FRONTEND_DIR / "index.html"
    if not index.exists():
        return HTMLResponse("<h1>Frontend no encontrado</h1>", status_code=404)
    return HTMLResponse(_inject_base_path(index.read_text(encoding="utf-8")))
