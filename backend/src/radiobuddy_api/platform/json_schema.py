from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator


@dataclass(frozen=True)
class SchemaValidationError(Exception):
    schema_name: str
    message: str
    json_path: str | None = None

    def __str__(self) -> str:
        if self.json_path:
            return f"{self.schema_name}: {self.message} at {self.json_path}"
        return f"{self.schema_name}: {self.message}"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@lru_cache(maxsize=64)
def _load_schema(schema_filename: str) -> dict[str, Any]:
    schema_path = _repo_root() / "schemas" / schema_filename
    return json.loads(schema_path.read_text(encoding="utf-8"))


@lru_cache(maxsize=64)
def _validator(schema_filename: str) -> Draft202012Validator:
    schema = _load_schema(schema_filename)
    return Draft202012Validator(schema)


def validate_instance(schema_filename: str, instance: Any) -> None:
    validator = _validator(schema_filename)
    error = next(validator.iter_errors(instance), None)
    if error is None:
        return

    path = "/".join(str(p) for p in error.absolute_path) if error.absolute_path else None
    raise SchemaValidationError(schema_name=schema_filename, message=error.message, json_path=path)
