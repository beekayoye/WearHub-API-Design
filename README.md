# WearHub

API design and data model for a ready-to-wear fashion marketplace in Lagos (NGN).
This is a design assignment: the documents are graded, and only the PostgreSQL schema is built.

**Final submission:** `docs/FINAL.md` (and `docs/FINAL.pdf`)

## Stack

| Layer | Choice |
| --- | --- |
| Database | PostgreSQL 16 (Docker) |
| Schema | Plain SQL. `db/migrations/001_schema.sql` is the single source of truth |
| API | REST under `/v1`, designed only (see `docs/04-api.md`) |
| Real-time | Server-Sent Events, designed only |
| Payments | None (pay on delivery). Amounts are stored in kobo |

## Folders

| Folder | What goes in it |
| --- | --- |
| `docs/` | Requirements, data model, decisions, API design, query plans, final document |
| `db/migrations/` | `001_schema.sql` (tables, constraints, indexes, triggers) |
| `db/` | `seed.sql`, `queries.sql`, `invalid.sql` |
| `evidence/` | ER diagram, state machine, query plan and rejection screenshots |
| `.agent/rules/` | Workspace rules the Antigravity agents followed |

## Start the database

1. Copy `.env.example` to `.env`.
2. Start PostgreSQL:
```bash
   docker compose up -d
```
3. Check it is running:
```bash
   docker exec -it weardb psql -U postgres -d wearhub -c "select 1"
```

## Build and prove the schema

```bash
docker exec -i weardb psql -U postgres -d wearhub -v ON_ERROR_STOP=1 < db/migrations/001_schema.sql
docker exec -i weardb psql -U postgres -d wearhub -v ON_ERROR_STOP=1 < db/seed.sql
docker exec -i weardb psql -U postgres -d wearhub < db/queries.sql
```

- `seed.sql` loads about 50,000 orders.
- `queries.sql` runs the five queries. Q1 and Q4 print EXPLAIN plans that use named indexes.

## Invalid states (these must fail)

`db/invalid.sql` tries to break the rules. **Every block is expected to fail** with a named constraint. Run it block by block in `psql`:

```bash
docker exec -it weardb psql -U postgres -d wearhub
```

| Attempt | Expected rejection |
| --- | --- |
| Sell more than the stock | `ck_product_variants_stock_nonneg` |
| Review an order that is not completed | `fk_reviews_order_completed` |
| Change a shipped order to cancelled | `order_transition_illegal` |

Screenshots are in `evidence/reject-1.png` to `reject-3.png`.

## Start over with an empty database

```bash
docker compose down -v
docker compose up -d
```
