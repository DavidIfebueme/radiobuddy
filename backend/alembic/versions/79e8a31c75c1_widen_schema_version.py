from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "79e8a31c75c1"
down_revision: Union[str, Sequence[str], None] = "2b8a41a5284d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.alter_column(
        "telemetry_events",
        "schema_version",
        existing_type=sa.VARCHAR(length=16),
        type_=sa.String(length=64),
        existing_nullable=False,
    )


def downgrade() -> None:
    op.alter_column(
        "telemetry_events",
        "schema_version",
        existing_type=sa.String(length=64),
        type_=sa.VARCHAR(length=16),
        existing_nullable=False,
    )
