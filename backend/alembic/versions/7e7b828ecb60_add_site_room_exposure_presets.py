from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "7e7b828ecb60"
down_revision: Union[str, Sequence[str], None] = "79e8a31c75c1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "sites",
        sa.Column("site_id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("site_id"),
    )
    op.create_table(
        "rooms",
        sa.Column("site_id", sa.String(length=64), nullable=False),
        sa.Column("room_id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["site_id"], ["sites.site_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("site_id", "room_id"),
    )
    op.create_table(
        "room_exposure_protocols",
        sa.Column("site_id", sa.String(length=64), nullable=False),
        sa.Column("room_id", sa.String(length=64), nullable=False),
        sa.Column("procedure_id", sa.String(length=128), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["site_id", "room_id"],
            ["rooms.site_id", "rooms.room_id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("site_id", "room_id", "procedure_id"),
    )


def downgrade() -> None:
    op.drop_table("room_exposure_protocols")
    op.drop_table("rooms")
    op.drop_table("sites")
