"""
Pydantic schemas — field names match the Flutter model fromJson() keys exactly.
"""
from __future__ import annotations
from datetime import time as dt_time
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


# ── Recording state ───────────────────────────────────────────────────────────

class RecordingState(str, Enum):
    IDLE      = "idle"
    STARTING  = "starting"
    RECORDING = "recording"
    SCHEDULED = "scheduled"
    ERROR     = "error"


# ── Camera ────────────────────────────────────────────────────────────────────

class CameraIn(BaseModel):
    """POST /cameras body"""
    name:     str
    rtsp_url: str
    label:    Optional[str] = None


class CameraInfo(BaseModel):
    """GET /cameras  and  GET /cameras/{name}/probe  response"""
    name:     str
    rtsp_url: str
    label:    Optional[str] = None
    online:   bool          = False
    width:    Optional[int] = None
    height:   Optional[int] = None
    fps:      Optional[int] = None
    codec:    Optional[str] = None
    error:    Optional[str] = None


# ── Schedule ──────────────────────────────────────────────────────────────────

class ScheduleIn(BaseModel):
    start_hour:   int = Field(9,  ge=0, le=23)
    start_minute: int = Field(0,  ge=0, le=59)
    end_hour:     int = Field(22, ge=0, le=23)
    end_minute:   int = Field(0,  ge=0, le=59)

    def is_active(self) -> bool:
        from datetime import datetime
        now = datetime.now().time()
        start = dt_time(self.start_hour,  self.start_minute)
        end   = dt_time(self.end_hour,    self.end_minute)
        return start <= now <= end

    def seconds_until_start(self) -> float:
        from datetime import datetime, timedelta
        now = datetime.now()
        start = dt_time(self.start_hour, self.start_minute)
        nxt   = datetime.combine(now.date(), start)
        if now.time() >= dt_time(self.end_hour, self.end_minute):
            nxt += timedelta(days=1)
        return max(0.0, (nxt - now).total_seconds())


# ── Start recording request ───────────────────────────────────────────────────

class StartRecordingIn(BaseModel):
    """POST /recordings/start body — matches Flutter StartRecordingRequest.toJson()"""
    camera_names:     list[str]
    duration_seconds: int                 = Field(3600, ge=60,  le=86400)
    width:            int                 = Field(960,  ge=320, le=3840)
    height:           int                 = Field(540,  ge=180, le=2160)
    fps:              int                 = Field(15,   ge=1,   le=60)
    crf:              int                 = Field(23,   ge=0,   le=51)
    schedule:         Optional[ScheduleIn] = None


# ── Recording status ──────────────────────────────────────────────────────────

class RecordingStatus(BaseModel):
    """Pushed via WebSocket and returned by GET /recordings/status"""
    cam_name:        str
    state:           RecordingState
    current_file:    Optional[str]   = None
    started_at:      Optional[str]   = None
    elapsed_seconds: Optional[int]   = None
    progress:        Optional[float] = None
    error:           Optional[str]   = None


# ── File info ─────────────────────────────────────────────────────────────────

class FileInfo(BaseModel):
    """GET /files response — matches Flutter RecordingFile.fromJson()"""
    filename:         str
    cam_name:         str
    size_bytes:       int
    size_mb:          float
    created_at:       str
    duration_seconds: Optional[int] = None
    is_recording:     bool          = False
