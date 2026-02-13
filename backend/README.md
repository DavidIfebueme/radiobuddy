
# Radio Buddy Backend

## Run (dev)

- Install deps: `uv sync`
- Start API: `uv run uvicorn radiobuddy_api.main:app --reload`

## Test

- `uv run pytest`

## Environment

- `RADIOBUDDY_DATABASE_URL` (required once DB-backed features are enabled)
	- Example: `postgresql+psycopg://radiobuddy:change_me@localhost:5432/radiobuddy`

- `RADIOBUDDY_ADMIN_API_KEY` (required for write/admin endpoints)
	- Used as `X-API-Key` header

- `RADIOBUDDY_DO_MODEL_ACCESS_KEY` (optional for `/ai/positioning/analyze`)
	- DigitalOcean Gradient serverless inference model access key

- `RADIOBUDDY_DO_MODEL_ID` (optional, default `llama3.3-70b-instruct`)

- `RADIOBUDDY_DO_INFERENCE_TIMEOUT_SECONDS` (optional, default `8.0`)

## Seed demo data

- `uv run python scripts/seed_demo.py`

