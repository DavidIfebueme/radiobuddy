from __future__ import annotations

from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool

from alembic import context
from radiobuddy_api.features.site_presets import models as _site_presets_models
from radiobuddy_api.features.telemetry import models as _telemetry_models
from radiobuddy_api.platform.config import settings
from radiobuddy_api.platform.db.base import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

_ = (_telemetry_models, _site_presets_models)


def _get_database_url() -> str:
    url = settings.database_url
    if not url:
        raise RuntimeError(
            "RADIOBUDDY_DATABASE_URL is not set. "
            "Example: postgresql+psycopg://radiobuddy:change_me@localhost:5432/radiobuddy"
        )
    return url


target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = _get_database_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    configuration = config.get_section(config.config_ini_section, {})
    configuration["sqlalchemy.url"] = _get_database_url()

    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
