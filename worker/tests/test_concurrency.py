from __future__ import annotations

import socket
import sys
import threading
import time
import types
from concurrent.futures import ThreadPoolExecutor
from importlib import metadata
from pathlib import Path

import httpx2 as httpx
import pytest
import uvicorn

from app.engines.basic_pitch import BasicPitchTranscriber
from app import main as main_module
from app.main import app

REPO_ROOT = Path(__file__).resolve().parents[2]
C_MAJOR_WAV = REPO_ROOT / "fixtures" / "c-major-chord.wav"
SLEEP_S = 0.5
HEALTH_BUDGET_S = 0.15


def _install_stub(monkeypatch: pytest.MonkeyPatch, sleep_s: float) -> dict[str, object]:
    state: dict[str, object] = {
        "model_inits": 0,
        "predict_passed_model": [],
        "in_predict": threading.Event(),
    }

    class Model:
        def __init__(self, model_path: object) -> None:
            state["model_inits"] = int(state["model_inits"]) + 1
            self.model_path = model_path

    def predict(
        audio_path: object,
        model_or_model_path: object = "ICASSP_2022_MODEL_PATH",
        **_kwargs: object,
    ) -> tuple[dict, None, list[tuple[float, float, int, float]]]:
        passed_model = isinstance(model_or_model_path, Model)
        if not passed_model:
            Model(model_or_model_path)
        passed = state["predict_passed_model"]
        assert isinstance(passed, list)
        passed.append(passed_model)
        in_predict = state["in_predict"]
        assert isinstance(in_predict, threading.Event)
        in_predict.set()
        if sleep_s:
            time.sleep(sleep_s)
        notes = [
            (0.0, 2.0, 60, 0.8),
            (0.0, 2.0, 64, 0.8),
            (0.0, 2.0, 67, 0.8),
        ]
        return {}, None, notes

    inference = types.ModuleType("basic_pitch.inference")
    inference.Model = Model
    inference.predict = predict
    pkg = types.ModuleType("basic_pitch")
    pkg.ICASSP_2022_MODEL_PATH = "ICASSP_2022_MODEL_PATH"
    pkg.inference = inference
    monkeypatch.setitem(sys.modules, "basic_pitch", pkg)
    monkeypatch.setitem(sys.modules, "basic_pitch.inference", inference)

    real_version = metadata.version

    def version(name: str) -> str:
        if name == "basic-pitch":
            return "0.4.0"
        return real_version(name)

    monkeypatch.setattr(metadata, "version", version)
    monkeypatch.setattr("app.engines.basic_pitch.version", version)
    if hasattr(main_module._transcriber, "_model"):
        main_module._transcriber._model = None
    if hasattr(main_module._transcriber, "_engine_version"):
        main_module._transcriber._engine_version = None
    return state


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def _start_worker() -> tuple[uvicorn.Server, threading.Thread, str]:
    port = _free_port()
    config = uvicorn.Config(app, host="127.0.0.1", port=port, log_level="error")
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{port}"
    deadline = time.monotonic() + 10.0
    last_exc: Exception | None = None
    while time.monotonic() < deadline:
        try:
            response = httpx.get(f"{base}/health", timeout=1.0)
            if response.status_code == 200:
                return server, thread, base
        except httpx.HTTPError as exc:
            last_exc = exc
        time.sleep(0.05)
    raise RuntimeError(f"worker never became healthy: {last_exc}")


def _stop_worker(server: uvicorn.Server, thread: threading.Thread) -> None:
    server.should_exit = True
    thread.join(timeout=5.0)


def _post(base: str) -> httpx.Response:
    return httpx.post(
        f"{base}/v1/transcriptions",
        files={"audio": ("c-major-chord.wav", C_MAJOR_WAV.read_bytes(), "audio/wav")},
        timeout=10.0,
    )


def test_health_stays_fast_during_transcribe(monkeypatch: pytest.MonkeyPatch) -> None:
    state = _install_stub(monkeypatch, SLEEP_S)
    server, thread, base = _start_worker()
    try:
        in_predict = state["in_predict"]
        assert isinstance(in_predict, threading.Event)
        in_predict.clear()
        poster = threading.Thread(target=_post, args=(base,))
        poster.start()
        assert in_predict.wait(timeout=5.0)
        started = time.perf_counter()
        response = httpx.get(f"{base}/health", timeout=SLEEP_S + 5.0)
        elapsed = time.perf_counter() - started
        poster.join(timeout=SLEEP_S + 5.0)
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
        assert elapsed < HEALTH_BUDGET_S
    finally:
        _stop_worker(server, thread)


def test_two_uploads_are_not_serialized_on_the_event_loop(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install_stub(monkeypatch, SLEEP_S)
    server, thread, base = _start_worker()
    try:
        started = time.perf_counter()
        with ThreadPoolExecutor(max_workers=2) as pool:
            first = pool.submit(_post, base)
            second = pool.submit(_post, base)
            responses = [first.result(), second.result()]
        elapsed = time.perf_counter() - started
        assert [item.status_code for item in responses] == [200, 200]
        for body in (item.json() for item in responses):
            assert body["engine"] == "basic_pitch"
            pitches = sorted(note["pitch_midi"] for note in body["note_events"])
            assert pitches == [60, 64, 67]
            assert body["tempo_bpm"] is None
            assert body["key_guess"] is None
            assert all(note["confidence"] == note["velocity"] for note in body["note_events"])
        assert elapsed < SLEEP_S * 1.5
    finally:
        _stop_worker(server, thread)


def test_basic_pitch_loads_model_once_and_passes_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    state = _install_stub(monkeypatch, sleep_s=0.0)
    transcriber = BasicPitchTranscriber()
    transcriber.transcribe(C_MAJOR_WAV)
    transcriber.transcribe(C_MAJOR_WAV)
    assert state["model_inits"] == 1
    assert state["predict_passed_model"] == [True, True]
