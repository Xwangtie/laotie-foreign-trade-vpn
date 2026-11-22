"""add user vpn_ip

Revision ID: 9c2f1f7e1c4b
Revises: f5a5a2d03001
Create Date: 2026-09-06 18:20:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "9c2f1f7e1c4b"
down_revision: Union[str, None] = "f5a5a2d03001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("vpn_ip", sa.String(length=64), nullable=True)
        )


def downgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("vpn_ip")
