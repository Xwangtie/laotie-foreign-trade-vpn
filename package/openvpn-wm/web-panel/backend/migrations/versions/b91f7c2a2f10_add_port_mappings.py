"""add port_mappings

Revision ID: b91f7c2a2f10
Revises: a44803841a39
Create Date: 2026-09-04 09:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b91f7c2a2f10"
down_revision: Union[str, None] = "a44803841a39"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "port_mappings",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("dest_ip", sa.String(length=64), nullable=False),
        sa.Column("ext_port", sa.Integer(), nullable=False),
        sa.Column("int_port", sa.Integer(), nullable=False),
        sa.Column("protocol", sa.String(length=8), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("remark", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint(
            "protocol IN ('tcp','udp','tcpudp')", name="ck_portmap_protocol"
        ),
        sa.CheckConstraint(
            "status IN ('active','disabled')", name="ck_portmap_status"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("ext_port", name="uq_portmap_ext_port"),
    )
    with op.batch_alter_table("port_mappings", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_port_mappings_user_id"), ["user_id"], unique=False
        )


def downgrade() -> None:
    op.drop_table("port_mappings")
