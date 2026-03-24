"""
RecorderManager
===============
One CameraRecorder per camera, each running its own daemon thread.
FastAPI calls the manager from async route handlers; blocking work
(ffprobe, ffmpeg, snapshots) is offloaded to a thread-pool executor
so the event loop is never blocked.
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
import threading
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

from models import (
    CameraIn, CameraInfo, FileInfo,
    RecordingState, RecordingStatus, ScheduleIn, StartRecordingIn,
)

# ── Path config (overridable via env vars) ────────────────────────────────────

CONFIG_FILE    = Path(os.getenv("CONFIG_FILE",    "config.json"))
RECORDINGS_DIR = Path(os.getenv("RECORDINGS_DIR", "recordings"))
HLS_DIR        = Path(os.getenv("HLS_DIR",        "/tmp/hls"))

RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
HLS_DIR.mkdir(parents=True, exist_ok=True)


# ─────────────────────────────────────────────────────────────────────────────
# CameraRecorder — one ffmpeg process per camera
# ─────────────────────────────────────────────────────────────────────────────

class CameraRecorder:
    """Manages a single camera: recording loop runs in a daemon thread."""

    def __init__(
        self,
        cam_name: str,
        rtsp_url: str,
        on_complete: Optional[Callable[[str, str], None]] = None,
    ):
        self.cam_name    = cam_name
        self.rtsp_url    = rtsp_url
        self.on_complete = on_complete

        self.state         = RecordingState.IDLE
        self.process: Optional[subprocess.Popen] = None
        self.thread:  Optional[threading.Thread] = None
        self.current_file: Optional[Path]        = None
        self.started_at:   Optional[datetime]    = None
        self.error:        Optional[str]         = None
        self._stop         = threading.Event()

        # Set by start()
        self.duration = 3600
        self.width    = 960
        self.height   = 540
        self.fps      = 15
        self.crf      = 23
        self.schedule: Optional[ScheduleIn] = None

    # ── Public ────────────────────────────────────────────────────────────────

    def start(
        self,
        duration: int,
        width: int,
        height: int,
        fps: int,
        crf: int,
        schedule: Optional[ScheduleIn],
    ) -> tuple[bool, str]:
        if self.state in (RecordingState.RECORDING, RecordingState.STARTING):
            return False, "Already recording"
        self.duration = duration
        self.width    = width
        self.height   = height
        self.fps      = fps
        self.crf      = crf
        self.schedule = schedule
        self._stop.clear()
        self.state  = RecordingState.STARTING
        self.thread = threading.Thread(
            target=self._loop,
            daemon=True,
            name=f"rec-{self.cam_name}",
        )
        self.thread.start()
        return True, "Recording started"

    def stop(self) -> tuple[bool, str]:
        if self.state not in (
            RecordingState.RECORDING,
            RecordingState.STARTING,
            RecordingState.SCHEDULED,
        ):
            return False, "Not currently recording"
        self._stop.set()
        self._terminate()
        self.state = RecordingState.IDLE
        return True, "Stopped"

    def status(self) -> RecordingStatus:
        elapsed  = None
        progress = None
        if self.started_at and self.state == RecordingState.RECORDING:
            elapsed  = int((datetime.now() - self.started_at).total_seconds())
            progress = min(1.0, elapsed / self.duration) if self.duration else None
        return RecordingStatus(
            cam_name        = self.cam_name,
            state           = self.state,
            current_file    = str(self.current_file) if self.current_file else None,
            started_at      = self.started_at.isoformat() if self.started_at else None,
            elapsed_seconds = elapsed,
            progress        = progress,
            error           = self.error,
        )

    # ── Internal loop ─────────────────────────────────────────────────────────

    def _loop(self) -> None:
        print(f"[{self.cam_name}] 🎬 Recording thread started")
        while not self._stop.is_set():
            print(f"[{self.cam_name}] 🎬 Starting recording loop with schedule={self.schedule}")
            # Honor schedule: if outside window, sleep until start time
            if self.schedule and not self.schedule.is_active():
                print(f"[{self.cam_name}] ⏰ Outside schedule window, sleeping until start time")
                self.state = RecordingState.SCHEDULED
                secs = self.schedule.seconds_until_start()
                print(f"[{self.cam_name}] ⏰ Sleeping for {secs:.0f} seconds")
                self._stop.wait(timeout=secs)
                continue
            print(f"[{self.cam_name}] 🎬 Starting recording segment")        
            self._record_one_segment()

            # No schedule = record once then exit
            if not self.schedule:
                print(f"[{self.cam_name}] 🎬 Finished recording (no schedule), exiting loop")
                break
        print(f"[{self.cam_name}] 🎬 Recording thread exiting")
        self.state = RecordingState.IDLE

    def _record_one_segment(self) -> None:
        ts  = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        out = RECORDINGS_DIR / f"{self.cam_name}_{ts}.mp4"

        self.current_file = out
        self.started_at   = datetime.now()
        self.state        = RecordingState.RECORDING
        self.error        = None

        # Build ffmpeg command
        # width >= 9999 is the sentinel for "keep original resolution"
        if self.width >= 9999:
            encode_args = ["-c:v", "copy"]
        else:
            encode_args = [
                "-vf", f"scale={self.width}:{self.height}",
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-crf", str(self.crf),
            ]

        cmd = [
            "ffmpeg",
            "-rtsp_transport", "tcp",
            "-i", self.rtsp_url,
             "-t", str(10),
            # "-t", str(self.duration),
            *encode_args,
            "-r", str(self.fps),
            "-movflags", "+faststart",
            "-an",   # no audio
            "-y",    # overwrite
            str(out),
        ]
        print(f"[{self.cam_name}] 🎬 Running ffmpeg command: {' '.join(cmd)}")

        self.process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

        # Drain stdout so the pipe buffer never fills
        for line in iter(self.process.stdout.readline, b""):
            if self._stop.is_set():
                self._terminate()
                break

        self.process.wait()

        # Verify output
        if out.exists() and out.stat().st_size > 0:
            if self.on_complete:
                self.on_complete(self.cam_name, str(out))
        else:
            self.error = "Output file is empty — check RTSP URL / network"
            self.state = RecordingState.ERROR

    def _terminate(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()


# ─────────────────────────────────────────────────────────────────────────────
# RecorderManager — used by FastAPI route handlers
# ─────────────────────────────────────────────────────────────────────────────

class RecorderManager:

    def __init__(self) -> None:
        self._lock      = threading.Lock()
        self.cameras:   dict[str, dict]             = {}
        self.recorders: dict[str, CameraRecorder]   = {}
        self._hls:      dict[str, subprocess.Popen] = {}
        self._load_config()

    # ── Configuration ─────────────────────────────────────────────────────────

    def _load_config(self) -> None:
        if CONFIG_FILE.exists():
            data = json.loads(CONFIG_FILE.read_text())
            self.cameras = data.get("cameras", {})
        else:
            # Bootstrap with the cameras from the original script
            self.cameras = {
                "entrance1": {
                    "rtsp_url": "rtsp://admin:Admin_1234@10.130.35.95:554/cam/realmonitor?channel=1&subtype=1",
                    "label": "Entrance 1",
                },
                "entrance2": {
                    "rtsp_url": "rtsp://admin:Admin_1234@10.130.35.94:554/cam/realmonitor?channel=1&subtype=1",
                    "label": "Entrance 2",
                },
                "exit": {
                    "rtsp_url": "rtsp://admin:Admin_1234@10.130.35.96:554/cam/realmonitor?channel=1&subtype=0",
                    "label": "Exit Gate",
                },
            }
            self._save_config()

    def _save_config(self) -> None:
        CONFIG_FILE.write_text(
            json.dumps({"cameras": self.cameras}, indent=2, ensure_ascii=False)
        )

    def upsert_camera(self, body: CameraIn) -> None:
        with self._lock:
            self.cameras[body.name] = {
                "rtsp_url": body.rtsp_url,
                "label":    body.label or body.name,
            }
            self._save_config()

    def remove_camera(self, name: str) -> None:
        with self._lock:
            self.cameras.pop(name, None)
            self._save_config()

    def get_camera(self, name: str) -> Optional[dict]:
        return self.cameras.get(name)

    # ── Camera probing ────────────────────────────────────────────────────────

    async def probe_all(self) -> list[CameraInfo]:
        """Probe all cameras concurrently in a thread-pool executor."""
        loop = asyncio.get_event_loop()
        tasks = [
            loop.run_in_executor(None, self._probe_sync, name, cam["rtsp_url"])
            for name, cam in self.cameras.items()
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        out = []
        for name, result in zip(self.cameras.keys(), results):
            if isinstance(result, Exception):
                out.append(CameraInfo(
                    name     = name,
                    rtsp_url = self.cameras[name]["rtsp_url"],
                    label    = self.cameras[name].get("label"),
                    online   = False,
                    error    = str(result),
                ))
            else:
                out.append(result)
        return out

    async def probe_one(self, name: str) -> CameraInfo:
        cam = self.cameras.get(name)
        if not cam:
            return CameraInfo(name=name, rtsp_url="", online=False,
                              error="Not found in config")
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, self._probe_sync, name, cam["rtsp_url"]
        )

    def _probe_sync(self, name: str, url: str) -> CameraInfo:
        """Blocking ffprobe call — always run in executor, never in event loop."""
        label = self.cameras.get(name, {}).get("label", name)
        try:
            result = subprocess.run(
                [
                    "ffprobe", "-v", "error",
                    "-select_streams", "v:0",
                    "-show_entries", "stream=width,height,r_frame_rate,codec_name",
                    "-of", "json",
                    "-rtsp_transport", "tcp",
                    url,
                ],
                capture_output=True,
                timeout=8,
            )
            info   = json.loads(result.stdout.decode(errors="ignore"))
            stream = info["streams"][0]
            num, den = stream.get("r_frame_rate", "15/1").split("/")
            fps = round(int(num) / max(int(den), 1))
            return CameraInfo(
                name=name, rtsp_url=url, label=label, online=True,
                width=stream.get("width"), height=stream.get("height"),
                fps=fps, codec=stream.get("codec_name"),
            )
        except Exception as exc:
            return CameraInfo(
                name=name, rtsp_url=url, label=label,
                online=False, error=str(exc),
            )

    # ── Recording control ─────────────────────────────────────────────────────

    def start(self, req: StartRecordingIn) -> dict[str, dict]:
        results: dict[str, dict] = {}
        for cam_name in req.camera_names:
            cam = self.cameras.get(cam_name)
            if not cam:
                results[cam_name] = {"ok": False, "error": "Camera not found in config"}
                continue
            with self._lock:
                if cam_name not in self.recorders:
                    self.recorders[cam_name] = CameraRecorder(
                        cam_name   = cam_name,
                        rtsp_url   = cam["rtsp_url"],
                        on_complete = self._on_complete,
                    )
            ok, msg = self.recorders[cam_name].start(
                duration = req.duration_seconds,
                width    = req.width,
                height   = req.height,
                fps      = req.fps,
                crf      = req.crf,
                schedule = req.schedule,
            )
            results[cam_name] = {"ok": ok, "message": msg}
        return results

    def stop(self, cam_name: str) -> tuple[bool, str]:
        rec = self.recorders.get(cam_name)
        if not rec:
            return False, "No recorder found for this camera"
        return rec.stop()

    def stop_all(self) -> dict[str, dict]:
        return {
            name: {"ok": ok, "message": msg}
            for name, rec in self.recorders.items()
            for ok, msg in [rec.stop()]
        }

    def _on_complete(self, cam_name: str, filepath: str) -> None:
        """Called from recording thread when a segment finishes."""
        size_mb = round(Path(filepath).stat().st_size / (1024 * 1024), 1)
        print(f"[{cam_name}] ✅  Saved {Path(filepath).name}  ({size_mb} MB)")
        # ← Add FCM push notification here when ready

    # ── Status ────────────────────────────────────────────────────────────────

    def get_status(self, cam_name: str) -> Optional[RecordingStatus]:
        rec = self.recorders.get(cam_name)
        return rec.status() if rec else None

    def all_statuses(self) -> dict[str, dict]:
        return {
            name: rec.status().model_dump()
            for name, rec in self.recorders.items()
        }

    def active_count(self) -> int:
        return sum(
            1 for r in self.recorders.values()
            if r.state == RecordingState.RECORDING
        )

    # ── File management ───────────────────────────────────────────────────────

    def list_files(self, cam_name: Optional[str] = None) -> list[FileInfo]:
        pattern = f"{cam_name}_*.mp4" if cam_name else "*.mp4"
        files: list[FileInfo] = []
        for p in sorted(
            RECORDINGS_DIR.glob(pattern),
            key=lambda x: x.stat().st_mtime,
            reverse=True,
        ):
            stat     = p.stat()
            parts    = p.stem.rsplit("_", 2)
            file_cam = parts[0] if len(parts) >= 3 else "unknown"
            is_rec   = any(
                r.current_file == p and r.state == RecordingState.RECORDING
                for r in self.recorders.values()
            )
            files.append(FileInfo(
                filename     = p.name,
                cam_name     = file_cam,
                size_bytes   = stat.st_size,
                size_mb      = round(stat.st_size / (1024 * 1024), 2),
                created_at   = datetime.fromtimestamp(stat.st_mtime).isoformat(),
                is_recording = is_rec,
            ))
        return files

    def get_file_path(self, filename: str) -> Optional[Path]:
        p = RECORDINGS_DIR / filename
        return p if p.exists() else None

    def delete_file(self, filename: str) -> tuple[bool, str]:
        path = RECORDINGS_DIR / filename
        if not path.exists():
            return False, "File not found"
        # Guard: don't delete a file while it's being written
        for r in self.recorders.values():
            if r.current_file == path and r.state == RecordingState.RECORDING:
                return False, "Cannot delete — file is currently being recorded"
        path.unlink()
        return True, f"Deleted {filename}"

    # ── HLS live stream ───────────────────────────────────────────────────────

    async def ensure_hls(self, cam_name: str, rtsp_url: str) -> str:
        """Start an HLS segment writer for a camera (idempotent)."""
        proc = self._hls.get(cam_name)
        if proc and proc.poll() is None:
            return f"/hls/{cam_name}/stream.m3u8"

        out_dir = HLS_DIR / cam_name
        out_dir.mkdir(exist_ok=True)
        cmd = [
            "ffmpeg", "-rtsp_transport", "tcp", "-i", rtsp_url,
            "-c:v", "libx264", "-preset", "ultrafast",
            "-tune", "zerolatency", "-crf", "30",
            "-r", "10", "-vf", "scale=640:360",
            "-f", "hls",
            "-hls_time", "2",
            "-hls_list_size", "5",
            "-hls_flags", "delete_segments+append_list",
            str(out_dir / "stream.m3u8"),
        ]
        self._hls[cam_name] = subprocess.Popen(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        await asyncio.sleep(3)   # wait for first segments to be written
        return f"/hls/{cam_name}/stream.m3u8"

    async def snapshot(self, rtsp_url: str) -> Optional[bytes]:
        """Grab a single JPEG frame (async wrapper around blocking ffmpeg call)."""
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self._snapshot_sync, rtsp_url)

    def _snapshot_sync(self, url: str) -> Optional[bytes]:
        try:
            result = subprocess.run(
                [
                    "ffmpeg", "-rtsp_transport", "tcp",
                    "-i", url,
                    "-vframes", "1",
                    "-f", "image2pipe",
                    "-vcodec", "mjpeg",
                    "pipe:1",
                ],
                capture_output=True,
                timeout=10,
            )
            return result.stdout if result.returncode == 0 else None
        except Exception:
            return None

    # ── Storage info ──────────────────────────────────────────────────────────

    def free_gb(self) -> float:
        return round(shutil.disk_usage(RECORDINGS_DIR).free / (1024 ** 3), 2)

    def used_gb(self) -> float:
        total = sum(
            p.stat().st_size
            for p in RECORDINGS_DIR.glob("*.mp4")
            if p.is_file()
        )
        return round(total / (1024 ** 3), 2)
