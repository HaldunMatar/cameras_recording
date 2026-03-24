# Camera Recorder — Python Backend

FastAPI backend for the **Camera Recorder Flutter (Material 3)** frontend.

---

## Files

| File | Purpose |
|---|---|
| `main.py` | FastAPI app — all routes |
| `recorder.py` | ffmpeg process manager, one thread per camera |
| `models.py` | Pydantic schemas matching Flutter models exactly |
| `requirements.txt` | Python dependencies |
| `cam-recorder.service` | systemd unit |
| `install.sh` | One-shot setup script |

---

## Deploy

### 1 — Copy to server

```bash
scp -r cam_backend/  YOUR_USER@YOUR_SERVER_IP:~/cam_recorder
```

### 2 — Run install script (once)

```bash
ssh YOUR_USER@YOUR_SERVER_IP
cd ~/cam_recorder
chmod +x install.sh
bash install.sh
```

The script installs `python3`, `ffmpeg`, creates a virtualenv, installs
Python deps, registers the systemd service, and starts it automatically.

### 3 — Verify

```bash
curl http://localhost:8765/health
# {"ok":true,"cameras":3,"active_recordings":0,...}
```

---

## Service commands

```bash
sudo systemctl status  cam-recorder   # current state
sudo systemctl restart cam-recorder   # apply config changes
sudo systemctl stop    cam-recorder   # stop
journalctl -u cam-recorder -f         # live logs
```

---

## Configuration

Cameras are stored in `config.json` (auto-created on first run with the
original three cameras from the old script).

```json
{
  "cameras": {
    "entrance1": {
      "rtsp_url": "rtsp://admin:Admin_1234@10.130.35.95:554/...",
      "label": "Entrance 1"
    }
  }
}
```

You can add/edit cameras at runtime from the Flutter UI (no restart needed),
or edit `config.json` directly and restart the service.

### Environment variables

Set in the systemd service file (`cam-recorder.service`):

| Variable | Default | Description |
|---|---|---|
| `RECORDINGS_DIR` | `~/cam_recorder/recordings` | Where MP4 files are saved |
| `CONFIG_FILE` | `~/cam_recorder/config.json` | Camera config |
| `HLS_DIR` | `/tmp/hls` | Temporary HLS segments for live preview |

---

## API reference

### Health
```
GET /health
→ { ok, cameras, active_recordings, storage_free_gb, storage_used_gb }
```

### Cameras
```
GET  /cameras                   probe all cameras (concurrent ffprobe)
GET  /cameras/{name}/probe      probe single camera
POST /cameras                   add/update  { name, rtsp_url, label? }
DEL  /cameras/{name}            remove
```

### Recordings
```
POST /recordings/start
Body: {
  "camera_names": ["entrance1","exit"],
  "duration_seconds": 3600,
  "width": 960, "height": 540,
  "fps": 15, "crf": 23,
  "schedule": { "start_hour":9, "start_minute":0,
                "end_hour":22,  "end_minute":0 }   ← optional
}

POST /recordings/stop/{cam_name}
POST /recordings/stop_all
GET  /recordings/status              all cameras
GET  /recordings/status/{cam_name}   single camera
```

### Files
```
GET  /files                  list all recordings (?cam_name=entrance1)
DEL  /files/{filename}       delete one file
DEL  /files                  batch delete (body: ["f1.mp4","f2.mp4"])
GET  /files/{filename}/download   stream MP4 to client
```

### Streaming / preview
```
GET /stream/{name}/snapshot   single JPEG frame (used for camera thumbnails)
GET /stream/{name}/hls        start HLS, returns { hls_url }
```

### WebSocket
```
WS /ws
```
Connect once. Server pushes every 2 seconds:
```json
{
  "type": "status_update",
  "data": {
    "entrance1": {
      "cam_name": "entrance1",
      "state": "recording",
      "elapsed_seconds": 432,
      "progress": 0.12,
      "current_file": "recordings/entrance1_2025-06-11_09-00-00.mp4"
    }
  }
}
```

---

## Connect Flutter

Open `lib/services/api_service.dart` in the Flutter project and set:

```dart
const String kServerIp   = 'YOUR_SERVER_VPN_IP';  // ← change this
const int    kServerPort = 8765;
```

Then run `flutter pub get && flutter run`.

---

## Wire up the Flutter M3 frontend

The Flutter project expects these packages in `pubspec.yaml`:
```yaml
dependencies:
  dio: ^5.4.3
  web_socket_channel: ^2.4.0
  path_provider: ^2.1.3
```

The `api_service.dart` in the Flutter project matches every endpoint above.
Field names in the JSON responses match the Flutter `fromJson()` methods exactly.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Connection refused` on Flutter | Check VPN is active; verify `kServerIp` |
| All cameras show Offline | `ffprobe` timeout — check RTSP URLs in `config.json` |
| HLS preview blank | `ffmpeg` not installed: `ffmpeg -version` |
| Service won't start | `journalctl -u cam-recorder -n 50 --no-pager` |
| Disk fills up | Delete old files from Flutter Files tab; add cron job |
