from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "2b8a41a5284d"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "telemetry_events",
        sa.Column("event_id", sa.UUID(), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
        sa.Column("schema_version", sa.String(length=16), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("procedure_id", sa.String(length=128), nullable=False),
        sa.Column("procedure_version", sa.String(length=64), nullable=True),
        sa.Column("session_id", sa.UUID(), nullable=True),
        sa.Column("stage_id", sa.String(length=64), nullable=True),
        sa.Column("device", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("metrics", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("prompt", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("habitus", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("exposure", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("performance", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("event_id"),
    )


def downgrade() -> None:
    op.drop_table("telemetry_events")
