from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from worldcup_app.routes import router


WEB_DIST = Path("/app/web_dist")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: nothing to initialize (connections are per-request)
    yield
    # Shutdown: nothing to clean up


app = FastAPI(
    title="World Cup Prediction Pool",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# API routes
app.include_router(router)

# Serve React SPA (built assets) — must be last so /api routes take priority
if WEB_DIST.is_dir():
    app.mount("/", StaticFiles(directory=str(WEB_DIST), html=True), name="spa")
