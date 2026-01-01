
# Radio Buddy Backend

## Run (dev)

- Install deps: `uv sync`
- Start API: `uv run uvicorn radiobuddy_api.main:app --reload`

## Test

- `uv run pytest`

## Environment

- `RADIOBUDDY_DATABASE_URL` (required once DB-backed features are enabled)
	- Example: `postgresql+psycopg://radiobuddy:change_me@localhost:5432/radiobuddy`

