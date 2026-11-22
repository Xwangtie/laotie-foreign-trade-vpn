"""add password_encrypted

Revision ID: e1a3f5b09001
Revises: d39e0c24b001
Create Date: 2026-09-05 22:10:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e1a3f5b09001"
down_revision: Union[str, None] = "d39e0c24b001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("password_encrypted", sa.String(length=512), nullable=True)
        )


def downgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("password_encrypted")
