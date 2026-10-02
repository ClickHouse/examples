from alembic import context

from semantic_notes.database import make_engine

engine = make_engine()
with engine.connect() as connection:
    context.configure(connection=connection, version_table_schema="semantic_notes")
    with context.begin_transaction():
        context.run_migrations()
engine.dispose()
