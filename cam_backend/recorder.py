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

CONFIG_FILE    = Path(os.getenv("CONFIG_FILE",    "config.json"))
RECORDINGS_DIR = Path(os.getenv("RECORDINGS_DIR", "recordings"))
HLS_DIR        = Path(os.getenv("HLS_DIR",        "/tmp/hls"))

RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
HLS_DIR.mkdir(parents=True, exist_ok=True)

SUPPORTED_EXTS = ("*.mp4", "*.ts")


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

        self.duration = 3600
        self.width    = 960
        self.height   = 540
        self.fps      = 15
        self.crf      = 23
        self.format   = "ts"
        self.schedule: Optional[ScheduleIn] = None

    def start(
        self,
        duration: int,
        width: int,
        height: int,
        fps: int,
        crf: int,
        schedule: Optional[ScheduleIn],
        fmt: str = "ts",
    ) -> tuple[bool, str]:
        if self.state in (RecordingState.RECORDING, RecordingState.STARTING):
            return False, "Already recording"
        self.duration = duration
        self.width    = width
        self.height   = height
        self.fps      = fps
        self.crf      = crf
        self.format   = fmt if fmt in ("ts", "mp4") else "ts"
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

    def _loop(self) -> None:
        print(f"[{self.cam_name}] Recording thread started (format={self.format})")
        while not self._stop.is_set():
            if self.schedule and not self.schedule.is_active():
                self.state = RecordingState.SCHEDULED
                secs = self.schedule.seconds_until_start()
                self._stop.wait(timeout=secs)
                continue
            self._record_one_segment()
            if not self.schedule:
                break
        print(f"[{self.cam_name}] Recording thread done")
        self.state = RecordingState.IDLE

    def _record_one_segment(self) -> None:
        """
        Records using ffmpeg -f segment -strftime 1.

        ffmpeg writes a series of files stamped with the real wall-clock time,
        e.g. entrance1_2025-06-11_09-00-00.ts, entrance1_2025-06-11_09-01-00.ts …

        self.current_file stores the strftime PATTERN (not a real file).
        That is intentional — list_files() globs real files from disk;
        is_recording is determined by recorder state + cam name, not by
        comparing paths to the pattern.

        Why mp4 needs special flags
        ───────────────────────────
        A plain MP4 written with -f segment is valid but each segment is only
        fully seekable after its moov atom is written at close time.
        frag_keyframe+empty_moov+default_base_moof writes a self-contained
        fragment at every keyframe so the file is playable while it is open
        AND immediately after download — no "moov atom not found" error.
        """
        ext = self.format  # "ts" or "mp4"

        # strftime pattern passed to ffmpeg
        pattern_path = RECORDINGS_DIR / f"{self.cam_name}_%Y-%m-%d_%H-%M-%S.{ext}"

        self.current_file = pattern_path
        self.started_at   = datetime.now()
        self.state        = RecordingState.RECORDING
        self.error        = None

        # ── video encode args ─────────────────────────────────────────
        if self.width >= 9999:
            encode_args = ["-c:v", "copy"]
        else:
            encode_args = [
                "-vf", f"scale={self.width}:{self.height}",
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-crf", str(self.crf),
            ]

        # ── container / mux args ──────────────────────────────────────
        # .ts  — mpegts is inherently byte-stream-safe; no extra flags needed
        # .mp4 — fragment every keyframe so each segment is self-contained
        if ext == "ts":
            container_args: list[str] = []
        else:
            container_args = [
                "-movflags", "+frag_keyframe+empty_moov+default_base_moof",
            ]

        cmd = [
            "ffmpeg",
            "-rtsp_transport", "tcp",
            "-i",                self.rtsp_url,
            "-f",                "segment",
            # "-segment_time",     str(15),
            "-segment_time",     str(self.duration),
            "-strftime",         "1",
            "-reset_timestamps", "1",
            *encode_args,
            "-r",  str(self.fps),
            *container_args,
            "-an",
            "-y",
            str(pattern_path),
        ]

        print(f"[{self.cam_name}] ffmpeg: {' '.join(cmd)}")

        self.process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

        for line in iter(self.process.stdout.readline, b""):
            if self._stop.is_set():
                self._terminate()
                break

        self.process.wait()

        # ── Verify ───────────────────────────────────────────────────
        # pattern_path is not a real file; look for any segment created
        written = sorted(
            RECORDINGS_DIR.glob(f"{self.cam_name}_*.{ext}"),
            key=lambda p: p.stat().st_mtime,
        )
        if written:
            if self.on_complete:
                self.on_complete(self.cam_name, str(written[-1]))
        else:
            self.error = "No output files created — check RTSP URL / network"
            self.state = RecordingState.ERROR

    def _terminate(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()


class RecorderManager:

    def __init__(self) -> None:
        self._lock      = threading.Lock()
        self.cameras:   dict[str, dict]             = {}
        self.recorders: dict[str, CameraRecorder]   = {}
        self._hls:      dict[str, subprocess.Popen] = {}
        self._load_config()

    def _load_config(self) -> None:
        if CONFIG_FILE.exists():
            data = json.loads(CONFIG_FILE.read_text())
            self.cameras = data.get("cameras", {})
        else:
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

    async def probe_all(self) -> list[CameraInfo]:
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
                    name=name, rtsp_url=self.cameras[name]["rtsp_url"],
                    label=self.cameras[name].get("label"),
                    online=False, error=str(result),
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
        return await loop.run_in_executor(None, self._probe_sync, name, cam["rtsp_url"])

    def _probe_sync(self, name: str, url: str) -> CameraInfo:
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
                capture_output=True, timeout=8,
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
            return CameraInfo(name=name, rtsp_url=url, label=label,
                              online=False, error=str(exc))

    def start(self, req: StartRecordingIn) -> dict[str, dict]:
        results: dict[str, dict] = {}
        fmt = getattr(req, "format", "ts") or "ts"
        for cam_name in req.camera_names:
            cam = self.cameras.get(cam_name)
            if not cam:
                results[cam_name] = {"ok": False, "error": "Camera not found in config"}
                continue
            with self._lock:
                if cam_name not in self.recorders:
                    self.recorders[cam_name] = CameraRecorder(
                        cam_name    = cam_name,
                        rtsp_url    = cam["rtsp_url"],
                        on_complete = self._on_complete,
                    )
            ok, msg = self.recorders[cam_name].start(
                duration = req.duration_seconds,
                width    = req.width,
                height   = req.height,
                fps      = req.fps,
                crf      = req.crf,
                schedule = req.schedule,
                fmt      = fmt,
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
        size_mb = round(Path(filepath).stat().st_size / (1024 * 1024), 1)
        print(f"[{cam_name}] Saved {Path(filepath).name}  ({size_mb} MB)")

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

    def _cam_from_stem(self, stem: str) -> str:
        """
        Extract camera name from a stem like entrance1_2025-06-11_09-00-00.
        We split on the first occurrence of _20 (covers years 2000-2099).
        """
        idx = stem.find("_20")
        if idx > 0:
            return stem[:idx]
        parts = stem.rsplit("_", 2)
        return parts[0] if len(parts) >= 3 else stem

    def list_files(self, cam_name: Optional[str] = None) -> list[FileInfo]:
        """
        List all .mp4 and .ts recordings, newest first.

        is_recording is True only for the NEWEST file belonging to a camera
        that is currently in RECORDING state.
        """
        all_paths: list[Path] = []
        for ext_glob in SUPPORTED_EXTS:
            if cam_name:
                # e.g. entrance1_*.mp4
                ext = ext_glob.lstrip("*")          # ".mp4" or ".ts"
                all_paths.extend(RECORDINGS_DIR.glob(f"{cam_name}_*{ext}"))
            else:
                all_paths.extend(RECORDINGS_DIR.glob(ext_glob))

        all_paths = sorted(set(all_paths),
                           key=lambda p: p.stat().st_mtime, reverse=True)

        # Cameras currently recording
        recording_cams: set[str] = {
            n for n, r in self.recorders.items()
            if r.state == RecordingState.RECORDING
        }

        # Newest file per camera (for is_recording flag)
        newest_per_cam: dict[str, Path] = {}
        for p in all_paths:
            fc = self._cam_from_stem(p.stem)
            if fc not in newest_per_cam:
                newest_per_cam[fc] = p

        files: list[FileInfo] = []
        for p in all_paths:
            stat     = p.stat()
            file_cam = self._cam_from_stem(p.stem)
            is_rec   = (
                file_cam in recording_cams
                and newest_per_cam.get(file_cam) == p
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
        file_cam = self._cam_from_stem(path.stem)
        rec = self.recorders.get(file_cam)
        if rec and rec.state == RecordingState.RECORDING:
            # Only block deletion of the newest (currently-being-written) file
            ext = path.suffix.lstrip(".")
            cam_files = sorted(
                RECORDINGS_DIR.glob(f"{file_cam}_*.{ext}"),
                key=lambda p: p.stat().st_mtime, reverse=True,
            )
            if cam_files and cam_files[0] == path:
                return False, "Cannot delete — file is currently being recorded"
        path.unlink()
        return True, f"Deleted {filename}"

    # ── HLS live stream ───────────────────────────────────────────────────────

    async def ensure_hls(self, cam_name: str, rtsp_url: str) -> str:
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
            "-f", "hls", "-hls_time", "2", "-hls_list_size", "5",
            "-hls_flags", "delete_segments+append_list",
            str(out_dir / "stream.m3u8"),
        ]
        self._hls[cam_name] = subprocess.Popen(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        await asyncio.sleep(3)
        return f"/hls/{cam_name}/stream.m3u8"

    async def snapshot(self, rtsp_url: str) -> Optional[bytes]:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self._snapshot_sync, rtsp_url)

    def _snapshot_sync(self, url: str) -> Optional[bytes]:
        try:
            result = subprocess.run(
                ["ffmpeg", "-rtsp_transport", "tcp", "-i", url,
                 "-vframes", "1", "-f", "image2pipe", "-vcodec", "mjpeg", "pipe:1"],
                capture_output=True, timeout=10,
            )
            return result.stdout if result.returncode == 0 else None
        except Exception:
            return None

    def free_gb(self) -> float:
        return round(shutil.disk_usage(RECORDINGS_DIR).free / (1024 ** 3), 2)

    def used_gb(self) -> float:
        total = sum(
            p.stat().st_size
            for ext in SUPPORTED_EXTS
            for p in RECORDINGS_DIR.glob(ext)
            if p.is_file()
        )
        return round(total / (1024 ** 3), 2)