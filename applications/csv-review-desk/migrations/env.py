from alembic import context
from reviewdesk.database import make_engine
from reviewdesk.models import Base

with make_engine().connect() as connection:
    context.configure(
        connection=connection, target_metadata=Base.metadata, version_table_schema="csv_review"
    )
    with context.begin_transaction():
        context.run_migrations()
