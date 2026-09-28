# WearHub

API design and data model for a ready-to-wear fashion marketplace in Lagos (NGN).
This is a design assignment: the documents are graded, and only the PostgreSQL schema is built.

## Folders

| Folder | What goes in it |
| --- | --- |
| `Docs/` | Requirements, data model, decisions, API design, query plans, final document |
| `db/migrations/` | `001_schema.sql` (tables, constraints, indexes, triggers) |
| `db/` | `seed.sql`, `queries.sql`, `invalid.sql` |
| `evidence/` | ER diagram, state machine, query plan and rejection screenshots |
| `prisma/` | `schema.prisma` with models, relations, enums, and constraint mappings |

## Start the database

1. Ensure the PostgreSQL container is running:
   ```bash
   docker exec -it weardb psql -U postgres -d wearhub -c "select 1"
   ```

## Run the SQL files

```bash
docker exec -i weardb psql -U postgres -d wearhub -v ON_ERROR_STOP=1 < db/migrations/001_schema.sql
docker exec -i weardb psql -U postgres -d wearhub -v ON_ERROR_STOP=1 < db/seed.sql
docker exec -i weardb psql -U postgres -d wearhub < db/queries.sql
```

Run `db/invalid.sql` to verify database invariant constraints.
