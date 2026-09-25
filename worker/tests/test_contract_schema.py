import json
from pathlib import Path

from jsonschema import Draft7Validator

from app.engines.fake import build_demo_transcription

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_demo_transcription_matches_contract_schema() -> None:
    schema_path = REPO_ROOT / "contracts" / "transcription.schema.json"
    schema = json.loads(schema_path.read_text())

    payload = build_demo_transcription().model_dump(mode="json", exclude_none=True)
    example = json.loads((REPO_ROOT / "contracts" / "transcription.example.json").read_text())

    Draft7Validator.check_schema(schema)
    Draft7Validator(schema).validate(payload)
    Draft7Validator(schema).validate(example)
    assert payload["note_events"] == example["note_events"]


def _camel_case(snake: str) -> str:
    parts = snake.split("_")
    return parts[0] + "".join(part.capitalize() for part in parts[1:])


def _convert_from_snake_case(value: object) -> object:
    if isinstance(value, list):
        return [_convert_from_snake_case(item) for item in value]
    if isinstance(value, dict):
        return {_camel_case(key): _convert_from_snake_case(item) for key, item in value.items()}
    return value


def test_contract_keys_match_ios_convert_from_snake_case() -> None:
    schema = json.loads((REPO_ROOT / "contracts" / "transcription.schema.json").read_text())
    expected_result = {
        "engine": "engine",
        "engine_version": "engineVersion",
        "tempo_bpm": "tempoBpm",
        "key_guess": "keyGuess",
        "note_events": "noteEvents",
    }
    expected_note = {
        "pitch_midi": "pitchMidi",
        "onset_seconds": "onsetSeconds",
        "duration_seconds": "durationSeconds",
        "velocity": "velocity",
        "confidence": "confidence",
        "onset_uncertainty_seconds": "onsetUncertaintySeconds",
        "staff_hint": "staffHint",
    }
    assert schema["properties"].keys() == expected_result.keys()
    assert schema["definitions"]["note_event"]["properties"].keys() == expected_note.keys()
    for snake, camel in expected_result.items():
        assert _camel_case(snake) == camel
    for snake, camel in expected_note.items():
        assert _camel_case(snake) == camel


def test_live_post_json_maps_to_ios_transcription_fields() -> None:
    schema = json.loads((REPO_ROOT / "contracts" / "transcription.schema.json").read_text())
    payload = {
        "engine": "basic_pitch",
        "engine_version": "0.3.0",
        "tempo_bpm": None,
        "key_guess": None,
        "note_events": [
            {
                "pitch_midi": 60,
                "onset_seconds": 0.0,
                "duration_seconds": 2.0,
                "velocity": 0.5,
                "confidence": 0.5,
                "staff_hint": "treble",
            },
            {
                "pitch_midi": 64,
                "onset_seconds": 0.0,
                "duration_seconds": 2.0,
                "velocity": 0.4,
                "confidence": 0.4,
                "staff_hint": "treble",
            },
            {
                "pitch_midi": 67,
                "onset_seconds": 0.0,
                "duration_seconds": 2.0,
                "velocity": 0.6,
                "confidence": 0.6,
                "staff_hint": "treble",
            },
        ],
    }
    Draft7Validator(schema).validate(payload)

    mapped = _convert_from_snake_case(payload)
    assert mapped == {
        "engine": "basic_pitch",
        "engineVersion": "0.3.0",
        "tempoBpm": None,
        "keyGuess": None,
        "noteEvents": [
            {
                "pitchMidi": 60,
                "onsetSeconds": 0.0,
                "durationSeconds": 2.0,
                "velocity": 0.5,
                "confidence": 0.5,
                "staffHint": "treble",
            },
            {
                "pitchMidi": 64,
                "onsetSeconds": 0.0,
                "durationSeconds": 2.0,
                "velocity": 0.4,
                "confidence": 0.4,
                "staffHint": "treble",
            },
            {
                "pitchMidi": 67,
                "onsetSeconds": 0.0,
                "durationSeconds": 2.0,
                "velocity": 0.6,
                "confidence": 0.6,
                "staffHint": "treble",
            },
        ],
    }
