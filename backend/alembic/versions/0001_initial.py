"""Create Apple authorization and Plaid connection tables."""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("sessions", sa.Column("digest", sa.Text, primary_key=True),
                    sa.Column("owner", sa.Text, nullable=False), sa.Column("expires", sa.BigInteger, nullable=False))
    op.create_index("ix_sessions_owner", "sessions", ["owner"])
    op.create_table("apple_challenges", sa.Column("nonce", sa.Text, primary_key=True),
                    sa.Column("expires", sa.BigInteger, nullable=False))
    op.create_index("ix_apple_challenges_expires", "apple_challenges", ["expires"])
    op.create_table("connections", sa.Column("id", sa.Text, primary_key=True),
                    sa.Column("item", sa.Text, nullable=False, unique=True),
                    sa.Column("owner", sa.Text, nullable=False), sa.Column("token", sa.LargeBinary, nullable=False),
                    sa.Column("name", sa.Text, nullable=False))
    op.create_index("ix_connections_owner", "connections", ["owner"])


def downgrade():
    op.drop_table("connections")
    op.drop_table("apple_challenges")
    op.drop_table("sessions")
