"""add embed_password flag

Revision ID: f2b7c0d3a901
Revises: e1a3f5b09001
Create Date: 2026-09-05 23:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f2b7c0d3a901"
down_revision: Union[str, None] = "e1a3f5b09001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "embed_password",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("1"),
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("embed_password")
