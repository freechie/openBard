import json
from pathlib import Path

from jsonschema import Draft7Validator

from app.engines.fake import build_demo_transcription

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_demo_transcription_matches_contract_schema() -> None:
    schema_path = REPO_ROOT / "contracts" / "transcription.schema.json"
    schema = json.loads(schema_path.read_text())

    payload = build_demo_transcription().model_dump(mode="json")
    example = json.loads((REPO_ROOT / "contracts" / "transcription.example.json").read_text())

    Draft7Validator.check_schema(schema)
    Draft7Validator(schema).validate(payload)
    Draft7Validator(schema).validate(example)
    assert payload["note_events"] == example["note_events"]
