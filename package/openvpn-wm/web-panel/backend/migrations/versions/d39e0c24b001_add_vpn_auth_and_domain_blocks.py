"""add vpn auth + domain blocks

Revision ID: d39e0c24b001
Revises: b91f7c2a2f10
Create Date: 2026-09-05 21:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d39e0c24b001"
down_revision: Union[str, None] = "b91f7c2a2f10"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("password_hash", sa.String(length=255), nullable=True)
        )

    with op.batch_alter_table("sessions", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("virtual_ip", sa.String(length=64), nullable=True)
        )

    op.create_table(
        "blocked_domains",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("domain", sa.String(length=255), nullable=False),
        sa.Column("remark", sa.String(length=255), nullable=True),
        sa.Column("created_by_admin_id", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["created_by_admin_id"], ["admins.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "domain", name="uq_blocked_user_domain"),
    )
    with op.batch_alter_table("blocked_domains", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_blocked_domains_domain"), ["domain"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_blocked_domains_user_id"), ["user_id"], unique=False
        )

    op.create_table(
        "vpn_auth_log",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("username", sa.String(length=32), nullable=False),
        sa.Column("success", sa.Boolean(), nullable=False),
        sa.Column("reason", sa.String(length=64), nullable=True),
        sa.Column("real_ip", sa.String(length=64), nullable=True),
        sa.Column("virtual_ip", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    with op.batch_alter_table("vpn_auth_log", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_vpn_auth_log_created_at"), ["created_at"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_vpn_auth_log_success"), ["success"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_vpn_auth_log_user_id"), ["user_id"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_vpn_auth_log_username"), ["username"], unique=False
        )


def downgrade() -> None:
    op.drop_table("vpn_auth_log")
    op.drop_table("blocked_domains")
    with op.batch_alter_table("sessions", schema=None) as batch_op:
        batch_op.drop_column("virtual_ip")
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("password_hash")
