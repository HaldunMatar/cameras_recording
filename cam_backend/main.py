"""
Camera Recorder API
===================
FastAPI backend for the Camera Recorder Flutter (Material 3) frontend.

Endpoints
---------
GET  /health
GET  /cameras                    → list + probe all cameras
GET  /cameras/{name}/probe       → probe single camera
POST /cameras                    → add / update a camera
DEL  /cameras/{name}             → remove a camera

POST /recordings/start           → start 1-N cameras
POST /recordings/stop/{name}     → stop one camera
POST /recordings/stop_all        → stop all
GET  /recordings/status          → all statuses (dict)
GET  /recordings/status/{name}   → single camera status

GET  /files                      → list recordings (?cam_name=filter)
DEL  /files/{filename}           → delete one file
DEL  /files                      → delete many (body: list[str])
GET  /files/{filename}/download  → stream MP4 to Flutter

GET  /stream/{name}/snapshot     → JPEG frame (for camera thumbnail)
GET  /stream/{name}/hls          → start HLS, returns m3u8 URL

WS   /ws                         → real-time status push every 2 s
"""
import asyncio
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

from recorder import RecorderManager, HLS_DIR
from models import (
    CameraIn, CameraInfo,
    StartRecordingIn, RecordingStatus, FileInfo,
)

# ─────────────────────────────────────────────────────────────────────────────

app = FastAPI(title="Camera Recorder API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve HLS segment files at /hls/<cam_name>/stream.m3u8
app.mount("/hls", StaticFiles(directory=str(HLS_DIR)), name="hls")

manager = RecorderManager()


# ─────────────────────────────────────────────────────────────────────────────
# WebSocket — broadcast status every 2 seconds
# ─────────────────────────────────────────────────────────────────────────────

class _WSPool:
    def __init__(self) -> None:
        self._sockets: list[WebSocket] = []

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self._sockets.append(ws)

    def remove(self, ws: WebSocket) -> None:
        if ws in self._sockets:
            self._sockets.remove(ws)

    async def broadcast(self, payload: dict) -> None:
        dead: list[WebSocket] = []
        for ws in list(self._sockets):
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.remove(ws)

    @property
    def count(self) -> int:
        return len(self._sockets)


_pool = _WSPool()


async def _status_broadcast_loop() -> None:
    while True:
        await asyncio.sleep(2)
        if _pool.count:
            await _pool.broadcast({
                "type": "status_update",
                "data": manager.all_statuses(),
            })


@app.on_event("startup")
async def _startup() -> None:
    asyncio.create_task(_status_broadcast_loop())


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await _pool.connect(ws)
    try:
        while True:
            msg = await ws.receive_json()
            action = msg.get("action")
            if action == "ping":
                await ws.send_json({"type": "pong"})
            elif action == "subscribe":
                # Send an immediate snapshot on connect
                await ws.send_json({
                    "type": "status_update",
                    "data": manager.all_statuses(),
                })
    except WebSocketDisconnect:
        _pool.remove(ws)


# ─────────────────────────────────────────────────────────────────────────────
# Health
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health() -> dict:
    return {
        "ok":               True,
        "cameras":          len(manager.cameras),
        "active_recordings": manager.active_count(),
        "storage_free_gb":  manager.free_gb(),
        "storage_used_gb":  manager.used_gb(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Cameras
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/cameras", response_model=list[CameraInfo])
async def list_cameras():
    """
    Probe every configured camera with ffprobe (concurrent).
    Returns online/offline status + resolution/fps/codec for each.
    Flutter calls this on CamerasScreen load and on refresh.
    """
    return await manager.probe_all()


@app.get("/cameras/{name}/probe", response_model=CameraInfo)
async def probe_camera(name: str):
    """Re-probe a single camera."""
    if not manager.get_camera(name):
        raise HTTPException(404, f"Camera '{name}' not found")
    return await manager.probe_one(name)


@app.post("/cameras", status_code=201)
async def add_camera(body: CameraIn):
    """Add or update a camera. Persisted to config.json immediately."""
    manager.upsert_camera(body)
    return {"ok": True, "name": body.name}


@app.delete("/cameras/{name}")
async def remove_camera(name: str):
    manager.remove_camera(name)
    return {"ok": True}


# ─────────────────────────────────────────────────────────────────────────────
# Recordings
# ─────────────────────────────────────────────────────────────────────────────

@app.post("/recordings/start")
async def start_recording(req: StartRecordingIn):
    """
    Start recording for one or more cameras.
    Each camera runs in its own thread with its own ffmpeg process.
    Supports an optional daily schedule (start_hour/end_hour).
    """
    return manager.start(req)


@app.post("/recordings/stop/{cam_name}")
async def stop_recording(cam_name: str):
    ok, msg = manager.stop(cam_name)
    if not ok:
        raise HTTPException(400, msg)
    return {"ok": True, "message": msg}


@app.post("/recordings/stop_all")
async def stop_all():
    return manager.stop_all()


@app.get("/recordings/status", response_model=dict)
async def all_statuses():
    return manager.all_statuses()


@app.get("/recordings/status/{cam_name}", response_model=RecordingStatus)
async def camera_status(cam_name: str):
    status = manager.get_status(cam_name)
    if not status:
        raise HTTPException(404, "Camera not found or has never recorded")
    return status


# ─────────────────────────────────────────────────────────────────────────────
# Files
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/files", response_model=list[FileInfo])
async def list_files(cam_name: str | None = None):
    """
    List all MP4 recordings, newest first.
    Optional ?cam_name=entrance1 to filter by camera.
    Flutter FilesScreen calls this on load, refresh, and after filter changes.
    """
    return manager.list_files(cam_name)


@app.delete("/files/{filename}")
async def delete_file(filename: str):
    ok, msg = manager.delete_file(filename)
    if not ok:
        raise HTTPException(404, msg)
    return {"ok": True, "message": msg}


@app.delete("/files")
async def delete_files(filenames: list[str]):
    """Batch delete. Body: ["file1.mp4", "file2.mp4"]"""
    return {
        fn: {"ok": ok, "message": msg}
        for fn in filenames
        for ok, msg in [manager.delete_file(fn)]
    }


@app.get("/files/{filename}/download")
async def download_file(filename: str):
    """
    Stream the file to the client for local saving.
    Supports both .mp4 and .ts files.
    """
    path = manager.get_file_path(filename)
    if not path:
        raise HTTPException(404, "File not found")
    # Correct MIME type per extension
    # video/mp2t is the IANA type for MPEG-TS
    media_type = "video/mp2t" if filename.endswith(".ts") else "video/mp4"
    return FileResponse(
        path        = str(path),
        media_type  = media_type,
        filename    = filename,
        headers     = {"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Live preview
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/stream/{cam_name}/snapshot")
async def snapshot(cam_name: str):
    """
    Return a single JPEG frame from the camera.
    Flutter's CameraCard calls this URL via Image.network()
    to show a live thumbnail.
    """
    cam = manager.get_camera(cam_name)
    if not cam:
        raise HTTPException(404, "Camera not found")
    data = await manager.snapshot(cam["rtsp_url"])
    if not data:
        raise HTTPException(503, "Cannot reach camera — check RTSP URL")
    return StreamingResponse(
        iter([data]),
        media_type = "image/jpeg",
        headers    = {"Cache-Control": "no-cache"},
    )


@app.get("/stream/{cam_name}/hls")
async def hls_stream(cam_name: str):
    """
    Ensure an HLS segmenter is running for this camera.
    Returns {"hls_url": "/hls/<name>/stream.m3u8"}.
    Flutter prepends kBaseUrl to build the full playback URL.
    """
    cam = manager.get_camera(cam_name)
    if not cam:
        raise HTTPException(404, "Camera not found")
    url = await manager.ensure_hls(cam_name, cam["rtsp_url"])
    return {"hls_url": url}