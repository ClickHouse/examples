"""Create the three booking tables and explicit runtime grants."""

from pathlib import Path

from alembic import op

revision = "001_initial"
down_revision = None
branch_labels = None
depends_on = None

SQL_DIRECTORY = Path(__file__).resolve().parents[2] / "sql"


def upgrade() -> None:
    # These files are intentionally readable without knowing Alembic or Python.
    op.execute((SQL_DIRECTORY / "migrations" / "001_initial.sql").read_text())
    op.execute((SQL_DIRECTORY / "grants.sql").read_text())


def downgrade() -> None:
    op.execute((SQL_DIRECTORY / "migrations" / "001_initial_down.sql").read_text())
