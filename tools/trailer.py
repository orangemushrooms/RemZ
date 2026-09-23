"""RemZ trailer: plan, validate, rehearse, record and edit. No recording by default.

Python 3.10+, Godot 4.7 editor; FFmpeg/FFprobe are needed only for record/edit.
All subprocess arguments are passed as arrays, never through a shell.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import math
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
STORYBOARD = ROOT / "godot/cinematics/trailer.json"
ERROR = re.compile(r"SCRIPT ERROR:|Parse Error:|(?m:^ERROR:)|TRAILER_FAILED")
KINDS = {"studio", "intro", "travel", "vista", "npc", "mushroom", "combat",
         "birds", "maze", "tower", "titan", "fireworks", "end"}
REQUIRED = {"studio", "intro", "mushroom", "combat", "birds", "maze", "npc",
            "tower", "titan", "fireworks"}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate_storyboard(data: dict) -> None:
    shots = data["shots"]
    if not shots or shots[0]["kind"] != "studio" or shots[1]["kind"] != "intro":
        raise ValueError("Studio and game intro must open the trailer.")
    ids = set()
    for shot in shots:
        name = shot["id"]
        if not re.fullmatch(r"[a-z0-9_]+", name) or name in ids:
            raise ValueError(f"Invalid or duplicate shot ID: {name}")
        ids.add(name)
        if shot["kind"] not in KINDS:
            raise ValueError(f"Unknown shot kind: {shot['kind']}")
        duration = shot["seconds"]
        if not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
            raise ValueError(f"Invalid duration: {name}")
        if shot.get("music", False) and shot["kind"] != "studio":
            raise ValueError("Only the studio card may contain music.")
        for cue in shot.get("cues", []):
            if not 0 <= cue["at"] < duration:
                raise ValueError(f"Cue outside shot: {name}")
        if shot.get("coop") and shot["kind"] == "studio":
            raise ValueError("Studio intro cannot be a co-op shot.")
    if not REQUIRED <= {s["kind"] for s in shots}:
        raise ValueError("The storyboard is missing requested gameplay features.")
    for kind in ("travel", "combat", "titan", "fireworks"):
        if not any(s["kind"] == kind and s.get("coop") for s in shots):
            raise ValueError(f"Missing multiplayer coverage: {kind}")
    duration = sum(s["seconds"] for s in shots)
    if not math.isclose(duration, 300.0, abs_tol=0.001):
        raise ValueError(f"The full trailer must be 300 seconds, got {duration}.")


def executable(value: str, label: str) -> str:
    located = shutil.which(value)
    if located:
        return located
    path = Path(value).expanduser()
    if path.is_file():
        return str(path.resolve())
    if value in {"ffmpeg", "ffprobe"}:
        # Reuse an already installed encoder; do not download or modify software.
        candidates = list((ROOT / "tools/bin").glob(value + ".exe"))
        local = Path(os.environ.get("LOCALAPPDATA", ""))
        if local.is_dir():
            candidates += list((local / "Overwolf/Extensions").glob(f"*/*/obs/bin/64bit/{value}.exe"))
        if candidates:
            return str(sorted(candidates)[-1].resolve())
    raise FileNotFoundError(f"{label} missing: {value}. Supply its path explicitly.")


def hidden_options() -> dict:
    if sys.platform != "win32":
        return {}
    info = subprocess.STARTUPINFO()
    info.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    info.wShowWindow = subprocess.SW_HIDE
    return {"startupinfo": info, "creationflags": subprocess.CREATE_NO_WINDOW}


def checked_run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, check=True, **hidden_options(), **kwargs)


def godot_command(args, folder: Path, role: str, mode: str) -> list[str]:
    command = [args.godot, "--path", str(ROOT / "godot"), "--log-file",
               str(folder / f"{role}.log"), "--script", "res://cinematics/run.gd"]
    if mode in {"check", "verify"} or role != "host":
        command += ["--headless"]
    else:
        command += ["--windowed", "--resolution", args.resolution, "--disable-vsync"]
    if role == "host" and mode in {"verify", "record"}:
        command += ["--fixed-fps", str(args.fps)]
    if mode == "record" and role == "host":
        command += ["--write-movie", str(folder / "raw.ogv")]
    command += ["--", "--trailer-run", "--smoke-test", "--no-intro", "--no-music",
                "--key-seed=4242", f"--quality={args.quality}", f"--trailer-mode={mode}",
                f"--trailer-role={role}", f"--trailer-port={args.port}",
                f"--trailer-folder={folder.as_posix()}", f"--trailer-fps={args.fps}"]
    if args.shots:
        command.append(f"--trailer-shots={args.shots}")
    if mode == "record":
        command.append("--profile-boot")
    if mode in {"check", "verify"} or role != "host":
        command.append("--no-foliage")
    return command


def run_session(args, mode: str) -> Path:
    if mode in {"verify", "record"}:
        # Only test availability; the game owns the actual ENet socket.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(("127.0.0.1", args.port))
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    folder = (ROOT / "artifacts/trailer" / f"{mode}-{stamp}").resolve()
    folder.mkdir(parents=True, exist_ok=False)
    (folder / "invocation.json").write_text(json.dumps({
        "mode": mode, "fps": args.fps, "resolution": args.resolution,
        "quality": args.quality, "shots": args.shots, "created": stamp,
    }, indent=2), encoding="utf-8")
    roles = ["host"] if mode == "check" else ["host", "c1", "c2", "c3"]
    processes = []
    handles = []
    print(f"{mode.upper()}: {folder}", flush=True)
    last_progress = ""
    began = time.monotonic()
    try:
        for role in roles:
            handle = (folder / f"{role}-console.log").open("w", encoding="utf-8")
            handles.append(handle)
            process = subprocess.Popen(godot_command(args, folder, role, mode), cwd=ROOT,
                                       stdout=handle, stderr=subprocess.STDOUT, **hidden_options())
            processes.append((role, process))
        while True:
            finished = True
            for role, process in processes:
                code = process.poll()
                if code is None:
                    finished = False
                elif code != 0:
                    raise RuntimeError(f"{role} exited with {code}; see {folder / (role + '.log')}")
                log_path = folder / f"{role}.log"
                if log_path.exists():
                    log = log_path.read_text(encoding="utf-8", errors="replace")
                    # Windows sandbox can deny certificate-store reads; this local ENet
                    # fixture uses no TLS. Keep all other engine errors fatal.
                    log = log.replace("ERROR: Failed to read the root certificate store.", "")
                    if ERROR.search(log):
                        raise RuntimeError(f"Game script error in {log_path}")
            progress = folder / "progress.json"
            if progress.exists():
                try:
                    status = read_json(progress)
                    message = status.get("message", "")
                    if message != last_progress:
                        print(message, flush=True)
                        last_progress = message
                except (json.JSONDecodeError, PermissionError):
                    pass  # A writer may currently be replacing the status file.
            if finished:
                break
            if time.monotonic() - began > args.timeout:
                raise TimeoutError(f"Trailer process timed out; logs: {folder}")
            time.sleep(0.25)
        result = read_json(folder / "result.json")
        if not result.get("passed"):
            raise RuntimeError(f"Trailer validation failed: {result}")
        for role in roles[1:]:
            report = read_json(folder / f"{role}-result.json")
            if not report.get("passed") or report.get("players") != 4:
                raise RuntimeError(f"Missing connected client: {role}")
        print(f"TRAILER_{mode.upper()}_PASS: {folder}", flush=True)
        return folder
    finally:
        # Only processes created by this invocation, never the user's game/editor.
        for _, process in processes:
            if process.poll() is None:
                process.terminate()
        for _, process in processes:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        for handle in handles:
            handle.close()


def probe_media(ffprobe: str, path: Path) -> dict:
    result = checked_run([ffprobe, "-v", "error", "-show_streams", "-show_format",
                          "-of", "json", str(path)], capture_output=True, text=True)
    return json.loads(result.stdout)


def edit(args, folder: Path) -> Path:
    manifest = read_json(folder / "edit.json")
    if manifest.get("mode") != "record" or not read_json(folder / "result.json").get("passed"):
        raise ValueError("Only a successful recording may be assembled.")
    source = folder / "raw.ogv"
    fps = int(manifest["fps"])
    clips = manifest.get("clips", [])
    if fps not in {30, 60} or not clips:
        raise ValueError("Empty or invalid edit list.")
    last_end = 0
    for clip in clips:
        if not re.fullmatch(r"[a-z0-9_]+", str(clip.get("id", ""))):
            raise ValueError("Invalid clip ID in edit list.")
        first, count = int(clip["first_frame"]), int(clip["frames"])
        if first < last_end or count <= 0:
            raise ValueError("Overlapping, out-of-order or empty clips.")
        last_end = first + count
    source_info = probe_media(args.ffprobe, source)
    types = {s["codec_type"] for s in source_info["streams"]}
    if not {"video", "audio"} <= types:
        raise ValueError("The recording must contain both game video and game audio.")
    if float(source_info["format"]["duration"]) + 1 / fps < last_end / fps:
        raise ValueError("The recording ends before the last required frame.")
    render_folder = folder / datetime.now().strftime("edit-%Y%m%d-%H%M%S-%f")
    render_folder.mkdir(exist_ok=False)
    files = []
    for index, shot in enumerate(manifest["clips"]):
        first, count = int(shot["first_frame"]), int(shot["frames"])
        seconds = count / fps
        output = render_folder / f"{index:02d}-{shot['id']}.mkv"
        # One source for both tracks. Frame ranges exclude loading, resets and networking waits.
        # Theora may represent repeated pictures as timestamp gaps. Reconstruct
        # the movie clock before indexing frames, including a held final picture.
        video = (f"fps={fps}:start_time=0,tpad=stop_mode=clone:stop=-1,"
                 f"trim=start_frame={first}:end_frame={first + count},setpts=PTS-STARTPTS")
        audio = (f"atrim=start={first / fps:.9f}:end={(first + count) / fps:.9f},"
                 "asetpts=PTS-STARTPTS,afade=t=in:d=0.008,"
                 f"afade=t=out:st={max(0, seconds - 0.012):.9f}:d=0.012")
        if shot["id"] == "studio":
            audio += f",afade=t=out:st={max(0, seconds - 0.6):.9f}:d=0.6"
        if shot["id"] == manifest["clips"][-1]["id"]:
            video += f",fade=t=out:st={max(0, seconds - 1):.9f}:d=1"
            audio += f",afade=t=out:st={max(0, seconds - 1):.9f}:d=1"
        checked_run([args.ffmpeg, "-v", "warning", "-nostdin", "-n", "-i", str(source),
                     "-filter_complex", f"[0:v]{video}[v];[0:a]{audio}[a]",
                     "-map", "[v]", "-map", "[a]", "-r", str(fps),
                     "-frames:v", str(count), "-t", f"{seconds:.9f}", "-c:v", "libx264", "-preset", "slow",
                     "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le",
                     "-ar", "48000", "-ac", "2", str(output)])
        files.append(output)
        print(f"CUT {index + 1}/{len(manifest['clips'])}: {shot['id']}", flush=True)
    concat = render_folder / "concat.txt"
    # File names are generated from the validated IDs; all entries are relative.
    concat.write_text("".join(f"file '{p.name}'\n" for p in files), encoding="utf-8")
    final = render_folder / "RemZ-Trailer.mp4"
    checked_run([args.ffmpeg, "-v", "warning", "-nostdin", "-n", "-f", "concat", "-safe", "1",
                 "-i", str(concat), "-c:v", "copy", "-c:a", "aac", "-b:a", "256k",
                 "-movflags", "+faststart", str(final)])
    info = probe_media(args.ffprobe, final)
    expected = sum(int(c["frames"]) for c in manifest["clips"]) / fps
    if abs(float(info["format"]["duration"]) - expected) > 0.5:
        raise RuntimeError("Export duration differs from the edit list; inspect the retained clips.")
    streams = info["streams"]
    if not {"video", "audio"} <= {s["codec_type"] for s in streams}:
        raise RuntimeError("Final export is missing video or sound.")
    (render_folder / "export-report.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    print(f"READY: {final}")
    return final


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", nargs="?", default="plan", choices=["plan", "check", "verify", "record", "edit"])
    parser.add_argument("--godot", default="C:/Users/miche/Desktop/Godot.exe")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--fps", type=int, choices=[30, 60], default=30)
    parser.add_argument("--resolution", choices=["1280x720", "1920x1080", "2560x1440"], default="1920x1080")
    parser.add_argument("--quality", type=int, choices=[0, 1, 2], default=2)
    parser.add_argument("--port", type=int, default=24739)
    parser.add_argument("--shots", default="", help="Comma-separated shot IDs; default: the whole 5-minute trailer")
    parser.add_argument("--timeout", type=float, default=7200, help="Wall-clock timeout in seconds")
    parser.add_argument("--take", type=Path, help="Existing recording directory for edit")
    args = parser.parse_args()
    data = read_json(STORYBOARD)
    validate_storyboard(data)
    if not 1024 <= args.port <= 65535 or args.timeout <= 0:
        parser.error("Port must be 1024..65535; timeout must be positive.")
    selected = set(args.shots.split(",")) if args.shots else {s["id"] for s in data["shots"]}
    unknown = selected - {s["id"] for s in data["shots"]}
    if unknown:
        parser.error(f"Unknown shots: {', '.join(sorted(unknown))}")
    if args.mode == "plan":
        elapsed = 0
        for shot in data["shots"]:
            if shot["id"] not in selected:
                continue
            print(f"{elapsed // 60:02.0f}:{elapsed % 60:02.0f}  {shot['seconds']:5.1f}s  "
                  f"{'KOOP' if shot.get('coop') else 'SOLO':4}  {shot['id']}: {shot['label']}")
            elapsed += shot["seconds"]
        print(f"Total: {elapsed:.1f}s. No game, recording or edit started.")
        return 0
    if args.mode in {"record", "edit"}:
        args.ffmpeg = executable(args.ffmpeg, "FFmpeg")
        args.ffprobe = executable(args.ffprobe, "FFprobe")
    if args.mode == "edit":
        if not args.take:
            parser.error("edit requires --take <recording directory>")
        edit(args, args.take.resolve())
    else:
        args.godot = executable(args.godot, "Godot")
        folder = run_session(args, args.mode)
        if args.mode == "record":
            edit(args, folder)
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    try:
        raise SystemExit(main())
    except (ValueError, OSError, RuntimeError, TimeoutError, subprocess.CalledProcessError) as error:
        print(f"TRAILER: {error}", file=sys.stderr)
        raise SystemExit(1)
