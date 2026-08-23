# Tdarr — Post-Deployment Setup Guide

Tdarr automates batch transcoding of media files using Intel QuickSync (VAAPI).
In this homelab it re-encodes video files >8 GB to H.264 (AVC) and applies
HDR→SDR tone mapping to avoid washed-out colors in VLC and Jellyfin.

> Web UI: http://tdarr.casita.local  
> Docs: https://docs.tdarr.io/

---

## 1. Create Host Directories

Run once on the Docker host before starting the container:

```bash
mkdir -p ${DOCKER_DATA_PATH}/arr/tdarr/{server,configs,logs,transcode-cache}
sudo chown -R 1000:1000 ${DOCKER_DATA_PATH}/arr/tdarr
```

> Replace `${DOCKER_DATA_PATH}` with `/home/casita/docker-data` if the variable
> is not set in your current shell.

---

## 2. Deploy

```bash
# From the repository root
docker compose up -d tdarr
docker logs -f tdarr
```

Wait until you see `Tdarr Server started` and `Internal node connected` in the logs.

---

## 3. Configure the Internal Node (Nodes Tab)

1. Open the Tdarr Web UI → **Nodes** tab.
2. Find **E580-Node** (the built-in node).
3. Set worker counts:
   - **GPU transcode workers**: 1
   - **CPU transcode workers**: 0
   - **Health check CPU workers**: 1
4. Click **Save**.

---

## 4. Add Libraries

Navigate to **Libraries** and create two libraries:

### Movies Library

| Field | Value |
|-------|-------|
| Source | `/media/movies` |
| Transcode cache | `/temp` |
| Output | `/media/movies` (overwrites original) |
| Scanner | FFprobe |

### TV Library

| Field | Value |
|-------|-------|
| Source | `/media/tv` |
| Transcode cache | `/temp` |
| Output | `/media/tv` (overwrites original) |
| Scanner | FFprobe |

---

## 5. Create a Flow

Navigate to **Flows** → **New Flow**. Name it `H264-VAAPI-8GB-HDR`.

### Recommended plugin sequence

1. **Filter by file size** — condition: size > 8 GB
2. **Filter by codec** — condition: video codec ≠ h264 (OR combined with size > 8 GB)
3. **Transcode** — use `h264_vaapi` encoder (see FFmpeg arguments below)
4. **Replace original file** — overwrite source with the transcoded output

Assign this Flow to both the Movies and TV libraries.

---

## 6. FFmpeg Arguments

### Option A — Hardware HDR→SDR Tone Mapping (preferred)

Uses `tonemap_vaapi` entirely on the GPU. Fastest; requires Intel Gen 8+ GPU
with proper VAAPI driver support.

```
-vaapi_device /dev/dri/renderD128 -hwaccel vaapi -hwaccel_output_format vaapi -i {{{args.inputPath}}} -vf 'tonemap_vaapi=format=nv12:t=bt709:m=bt709:p=bt709' -c:v h264_vaapi -b:v {bitrate} -c:a copy -c:s copy -map 0 {{{args.outputPath}}}
```

### Option B — Software Tone Mapping Fallback

Use if `tonemap_vaapi` fails or produces incorrect colors. Downloads frames from
GPU, tone-maps on CPU, re-uploads for encoding.

```
-i {{{args.inputPath}}} -vf 'hwdownload,format=p010le,tonemap=tonemap=hable:desat=0:peak=100,format=nv12,hwupload' -c:v h264_vaapi -b:v {bitrate} -c:a copy -c:s copy -map 0 {{{args.outputPath}}}
```

### Recommended Bitrates

| Resolution | Target Bitrate |
|------------|---------------|
| 1080p      | 4–6 Mbps      |
| 4K (UHD)   | 10–15 Mbps    |

---

## 7. Troubleshooting

### GPU not detected

```bash
# Check GPU devices inside the container
docker exec tdarr ls -la /dev/dri/

# Verify VAAPI is working
docker exec tdarr vainfo --display drm --device /dev/dri/renderD128
```

Expected output: a list of supported encode/decode profiles including `VAProfileH264`.

### Washed-out / faded colors after transcoding

Check the FFmpeg command in the Tdarr job logs for the presence of
`tonemap_vaapi` or `tonemap=hable`. If neither is present, the HDR→SDR
tone mapping is not being applied — review your Flow configuration.

### Disk full (transcode cache)

```bash
rm -rf ${DOCKER_DATA_PATH}/arr/tdarr/transcode-cache/*
```

### Files stuck in queue

1. Verify **GPU workers > 0** in the Nodes tab for E580-Node.
2. Check container logs:
   ```bash
   docker logs tdarr --tail 100
   ```
3. Ensure the `/dev/dri` devices exist and the `video` (44) and `render` (992)
   groups are correctly configured on the host.
