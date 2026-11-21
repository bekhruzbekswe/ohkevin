#!/usr/bin/env python3
"""Kokoro text-to-speech sidecar for the call server.

Started with the Python of an environment that has kokoro-onnx, and the folder holding
kokoro-v1.0.onnx and voices-v1.0.bin. Reads one JSON request per line on stdin
({"id", "text", "voice", "speed"}) and answers with one JSON line on stdout:
{"id", "path"} pointing at a WAV file, or {"id", "error"}.
"""
import json
import os
import signal
import subprocess
import sys
import tempfile

import onnxruntime as rt
import phonemizer
import soundfile as sf
from kokoro_onnx import Kokoro
from phonemizer.backend import EspeakBackend

model_dir = sys.argv[1]
out_dir = tempfile.mkdtemp(prefix="claude-voice-")


def _threads():
    """How many cores a sentence may use; 0 means every core (onnxruntime's own choice).

    VOICE_THREADS sets it: a number, or "all". Without it, this Mac's performance cores are used:
    on Apple Silicon the efficiency cores hold each run back (16 words took 1.31 s on all 10 cores
    of an M1 Pro, 0.96 s on its 8 fast ones, about 1.5 s on 4).
    """
    want = os.environ.get("VOICE_THREADS", "").strip().lower()
    if want == "all":
        return 0
    if want.isdigit() and int(want) > 0:
        return int(want)
    try:
        return int(subprocess.check_output(["sysctl", "-n", "hw.perflevel0.physicalcpu"], stderr=subprocess.DEVNULL))
    except Exception:
        return 0


options = rt.SessionOptions()
options.intra_op_num_threads = _threads()
session = rt.InferenceSession(os.path.join(model_dir, "kokoro-v1.0.onnx"), sess_options=options, providers=["CPUExecutionProvider"])
kokoro = Kokoro.from_session(session, os.path.join(model_dir, "voices-v1.0.bin"))

# kokoro-onnx calls phonemizer.phonemize(), which builds a new espeak backend on every call
# (about 0.6 s each on an M1 Pro). Keep one backend per language instead.
_backends = {}


def _phonemize(text, language="en-us", preserve_punctuation=True, with_stress=True, **_):
    backend = _backends.get(language)
    if backend is None:
        backend = _backends[language] = EspeakBackend(language, preserve_punctuation=preserve_punctuation, with_stress=with_stress)
    return backend.phonemize([text])[0]


phonemizer.phonemize = _phonemize
kokoro.create("Ready.", voice="bm_fable", lang="en-us")  # warm up so the first real sentence is fast
print(json.dumps({"ready": True, "voices": sorted(v for v in kokoro.get_voices() if v[0] in "ab"), "threads": options.intra_op_num_threads}), flush=True)

signal.signal(signal.SIGINT, signal.SIG_DFL)  # Ctrl-C in the terminal reaches this child too: quit quietly, the server ends the call
for line in sys.stdin:
    req = json.loads(line)
    try:
        voice = req.get("voice") or "bm_fable"
        lang = "en-gb" if voice.startswith("b") else "en-us"  # bf_/bm_ voices are British
        samples, rate = kokoro.create(req["text"], voice=voice, speed=req.get("speed", 1.0), lang=lang)
        path = os.path.join(out_dir, f"{req['id']}.wav")
        sf.write(path, samples, rate)
        print(json.dumps({"id": req["id"], "path": path}), flush=True)
    except Exception as err:  # one bad sentence must not end the call
        print(json.dumps({"id": req["id"], "error": str(err)}), flush=True)
