"""Trailer contract and actual FFmpeg trim/audio integration, using generated colours.

No game window, screen recording, or external Python dependencies.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import types
import unittest
from datetime import datetime

spec = importlib.util.spec_from_file_location("trailer", Path(__file__).parents[1] / "trailer.py")
trailer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trailer)


class StoryboardTests(unittest.TestCase):
    def test_duration_and_multiplayer_coverage(self):
        data = trailer.read_json(trailer.STORYBOARD)
        trailer.validate_storyboard(data)
        self.assertEqual(sum(s["seconds"] for s in data["shots"]), 300)

    def test_gameplay_music_is_rejected(self):
        data = trailer.read_json(trailer.STORYBOARD)
        data["shots"][1]["music"] = True
        with self.assertRaisesRegex(ValueError, "Only the studio"):
            trailer.validate_storyboard(data)

    def test_missing_coop_titan_is_rejected(self):
        data = trailer.read_json(trailer.STORYBOARD)
        for shot in data["shots"]:
            if shot["kind"] == "titan":
                shot["coop"] = False
        with self.assertRaisesRegex(ValueError, "multiplayer coverage: titan"):
            trailer.validate_storyboard(data)

    def test_out_of_range_cue_is_rejected(self):
        data = trailer.read_json(trailer.STORYBOARD)
        shot = next(s for s in data["shots"] if s.get("cues"))
        shot["cues"][0]["at"] = shot["seconds"]
        with self.assertRaisesRegex(ValueError, "Cue outside"):
            trailer.validate_storyboard(data)


class EncoderTests(unittest.TestCase):
    def test_real_frame_trim_and_audio_export(self):
        try:
            ffmpeg = trailer.executable("ffmpeg", "FFmpeg")
            ffprobe = trailer.executable("ffprobe", "FFprobe")
        except FileNotFoundError as error:
            self.skipTest(str(error))
        folder = trailer.ROOT / "artifacts/trailer" / datetime.now().strftime("encoder-test-%Y%m%d-%H%M%S-%f")
        folder.mkdir(parents=True)
        # Black represents loading. The two retained shots must be red, then blue.
        graph = ("color=black:s=160x90:r=30:d=1[b];"
                 "color=red:s=160x90:r=30:d=1[r];"
                 "color=blue:s=160x90:r=30:d=1[u];"
                 "[b][r][u]concat=n=3:v=1:a=0")
        trailer.checked_run([ffmpeg, "-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", graph,
                             "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3",
                             "-c:v", "libtheora", "-q:v", "8", "-c:a", "libvorbis",
                             "-ac", "2", "-shortest", str(folder / "raw.ogv")])
        (folder / "result.json").write_text(json.dumps({"passed": True}), encoding="utf-8")
        (folder / "edit.json").write_text(json.dumps({"mode": "record", "fps": 30, "clips": [
            {"id": "red", "first_frame": 30, "frames": 30},
            {"id": "blue", "first_frame": 60, "frames": 30},
        ]}), encoding="utf-8")
        output = trailer.edit(types.SimpleNamespace(ffmpeg=ffmpeg, ffprobe=ffprobe), folder)
        info = trailer.probe_media(ffprobe, output)
        self.assertAlmostEqual(float(info["format"]["duration"]), 2.0, delta=0.1)
        video = next(s for s in info["streams"] if s["codec_type"] == "video")
        audio = next(s for s in info["streams"] if s["codec_type"] == "audio")
        self.assertEqual(int(video["nb_frames"]), 60)
        self.assertEqual(audio["codec_name"], "aac")
        pixels = trailer.checked_run([ffmpeg, "-v", "error", "-i", str(output), "-vf",
                                      "select='eq(n,0)+eq(n,30)',scale=1:1", "-fps_mode", "passthrough",
                                      "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
                                     stdout=subprocess.PIPE).stdout
        self.assertEqual(len(pixels), 6)
        self.assertGreater(pixels[0], 180)  # Starts on red, not loading black.
        self.assertLess(pixels[2], 30)
        self.assertGreater(pixels[5], 180)  # Second shot starts on blue.
        self.assertLess(pixels[3], 30)
        pcm = trailer.checked_run([ffmpeg, "-v", "error", "-i", str(output), "-vn", "-f", "s16le",
                                   "-ac", "1", "pipe:1"], stdout=subprocess.PIPE).stdout
        self.assertTrue(any(pcm), "The captured audio must not become silence.")

    @unittest.skipUnless(os.environ.get("REMZ_TEST_MOVIE_CLOCK") == "1", "Opt-in synthetic Godot movie test")
    def test_godot_movie_clock(self):
        godot = trailer.executable(os.environ.get("REMZ_TEST_GODOT", "C:/Users/miche/Desktop/Godot.exe"), "Godot")
        ffmpeg = trailer.executable("ffmpeg", "FFmpeg")
        ffprobe = trailer.executable("ffprobe", "FFprobe")
        folder = trailer.ROOT / "artifacts/trailer" / datetime.now().strftime("clock-test-%Y%m%d-%H%M%S-%f")
        folder.mkdir(parents=True)
        (folder / "project.godot").write_text('''config_version=5
[application]
config/name="RemZMovieClockTest"
[display]
window/size/viewport_width=160
window/size/viewport_height=90
window/size/mode=0
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding="utf-8")
        script = Path(__file__).with_name("trailer_clock.gd").read_text(encoding="utf-8")
        (folder / "clock.gd").write_text(script, encoding="utf-8")
        result = trailer.checked_run([godot, "--path", str(folder), "--script", "res://clock.gd",
                                      "--windowed", "--resolution", "160x90", "--audio-driver", "Dummy",
                                      "--write-movie", str(folder / "clock.ogv"), "--fixed-fps", "30"],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        (folder / "godot.log").write_bytes(result.stdout)
        self.assertNotIn(b"SCRIPT ERROR", result.stdout)
        self.assertNotIn(b"Playback can only happen", result.stdout)
        pixels = trailer.checked_run([ffmpeg, "-v", "error", "-i", str(folder / "clock.ogv"),
                                      "-vf", "fps=30,select='eq(n,29)+eq(n,30)+eq(n,59)+eq(n,60)',scale=1:1",
                                      "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
                                     stdout=subprocess.PIPE).stdout
        self.assertEqual(len(pixels), 12)
        self.assertLess(max(pixels[:3]), 20, "Frame 29 must still be black.")
        self.assertGreater(pixels[3], 200, "Engine frame 30 must equal movie frame 30.")
        self.assertGreater(pixels[6], 200, "Frame 59 must still be red.")
        self.assertGreater(pixels[11], 200, "Engine frame 60 must equal movie frame 60.")
        info = trailer.probe_media(ffprobe, folder / "clock.ogv")
        self.assertIn("audio", {s["codec_type"] for s in info["streams"]})
        pcm = trailer.checked_run([ffmpeg, "-v", "error", "-i", str(folder / "clock.ogv"), "-vn",
                                   "-f", "s16le", "-ac", "1", "pipe:1"], stdout=subprocess.PIPE).stdout
        self.assertTrue(any(pcm), "Godot must capture the generated sound, not just an empty audio stream.")


if __name__ == "__main__":
    unittest.main()
