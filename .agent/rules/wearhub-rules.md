# WearHub workspace rules (API design and data modeling assignment)

## What this project is

- A DESIGN assignment for WearHub, a ready-to-wear fashion marketplace in Lagos (currency NGN). Sellers (fashion brands and boutiques) list clothes in fixed sizes and colours. Buyers order them and pay on delivery.
- It is graded on the documents. Only the PostgreSQL schema is implemented, then proven with seed data, queries, query plans and rejected invalid inserts.
- NEVER write app server code, UI, mobile code, or payment integration. There is no payment provider. The database only records amounts.
- Work only on the files the current task names. Do not create extra files.

## The five important actions (use these IDs everywhere)

- A1: A buyer places an order for items in a chosen size and colour. Stock is reserved and prices are locked.
- A2: The seller confirms, packs and ships the order.
- A3: The buyer tracks the order live.
- A4: The order is delivered, then completed (or the buyer requests a return within 7 days).
- A5: The buyer reviews an item from a completed order.

Every requirement (R1, R2...) and every design decision must cite one of these. Model from the requirements forward, never from screens backwards.

## Fixed decisions (never change these)

- Tables, with these exact names: buyers, sellers, categories, products, product_categories, product_variants, orders, order_items, order_status_transitions, order_status_history, reviews.
- Many-to-many join tables, each with its own primary key, foreign keys, created_at and updated_at:
  - product_categories links products and categories. Primary key (product_id, category_id).
  - order_items links orders and product_variants. Unique (order_id, variant_id), quantity > 0.
- A product has variants. Each variant is one size + colour with its own price and stock. Unique (product_id, size, colour).
- One order belongs to exactly one seller. A buyer who shops from two sellers gets two orders.
- Order statuses (Postgres enum order_status): placed, confirmed, packed, shipped, delivered, completed, cancelled, return_requested, returned.
- Allowed transitions, exactly 11 rows in order_status_transitions:
  - placed to confirmed, placed to cancelled
  - confirmed to packed, confirmed to cancelled
  - packed to shipped, packed to cancelled
  - shipped to delivered
  - delivered to completed, delivered to return_requested
  - return_requested to returned, return_requested to completed (return rejected)
- Everything else is forbidden and enforced by trigger trg_orders_enforce_transition.
- Non-obvious forbidden transitions to explain:
  - shipped to cancelled: the clothes have left the seller. Cancelling would lose track of goods in transit. The buyer must use a return.
  - completed to return_requested: completed means the 7-day return window has closed.
  - delivered to cancelled: the buyer has the goods. Cancelling would erase a real sale.
- Delivered orders move to completed automatically 7 days after delivered_at if no return was requested.

## Database rules

- PostgreSQL 16. Plain SQL files. Migration file: db/migrations/001_schema.sql.
- IDs: uuid DEFAULT gen_random_uuid(). Never SERIAL, never sequential.
- Money: BIGINT in minor units (kobo) with a CHAR(3) currency column in the same row. Never DECIMAL, FLOAT or NUMERIC for money. Money column names end in _minor.
- Money columns: product_variants.price_minor; order_items.unit_price_minor and line_total_minor; orders.subtotal_minor, delivery_fee_minor and total_minor.
- Every table has created_at and updated_at (timestamptz NOT NULL DEFAULT now()). Soft-deletable tables also have deleted_at. Every table's delete choice has a written reason. Orders, order_items and order_status_history are never deleted.
- Status is never free text: enum + transitions table + trigger.
- Name every constraint and index: pk_, fk_, uq_, ck_, idx_, trg_.
- Required constraint names (use exactly these):
  - ck_product_variants_stock_nonneg: stock_quantity >= 0. Stock can never go negative.
  - uq_product_variants_product_size_colour: no duplicate size + colour for one product.
  - fk_order_items_variant_seller and fk_order_items_order_seller: every item in an order comes from that order's seller.
  - trg_orders_subtotal_matches and trg_order_items_subtotal_matches: deferred constraint triggers that raise order_subtotal_mismatch if orders.subtotal_minor is not the sum of its items at COMMIT.
  - fk_reviews_order_completed: composite FK (order_id, buyer_id, order_status) to orders (id, buyer_id, status), plus CHECK order_status = 'completed'. A review needs a completed order by the same buyer.
  - uq_reviews_order_item: one review per order item.
  - order_transition_illegal: the transition trigger's error name.
- Deliberate denormalisations:
  - order_items.unit_price_minor, product_name_snapshot, size_snapshot and colour_snapshot are copied at order time. The receipt must not change when the seller edits the price or product.
  - orders.subtotal_minor is stored and checked by the deferred trigger.
  - products.rating_avg_x100 and rating_count are cached and kept in sync by a trigger.
  - seller_id and product_id copies on variants, order items and reviews exist so composite foreign keys can prove they match.
- total_minor and line_total_minor are GENERATED ALWAYS AS ... STORED columns.
- Stock is reserved with a conditional update: UPDATE product_variants SET stock_quantity = stock_quantity - :qty WHERE id = :id AND stock_quantity >= :qty. Zero rows updated means out of stock. The API returns 409 OUT_OF_STOCK.
- Only add an index if a named query from A1 to A5 needs it. No "just in case" indexes.

## API rules (design only, no code)

- REST, versioned paths /v1/..., JSON, camelCase fields.
- Money in JSON is an object: {"amountMinor": 2500000, "currency": "NGN"}.
- Every endpoint lists: method + path, request body with types and required fields, a response body example, EVERY error with its status code, and whether it is idempotent (and how, for mutations).
- POST /v1/orders requires an Idempotency-Key header. The same key returns the same order.
- Every list endpoint defines cursor pagination, filters, sorting and a max page size of 100.
- Real-time order tracking for A3 uses Server-Sent Events.

## How to behave

- Plain language, short sentences, no fluff.
- If something is not decided here, write [ASSUMPTION] next to it and tell the user.
- If a command fails, show the exact error and stop. Never weaken, disable or drop a constraint to make a seed or query pass. Fix the data instead.
- The only exception: inside the seed's own transaction, the status transition trigger may be disabled so past orders can be inserted in their final status. It must be re-enabled before COMMIT. The subtotal triggers stay on.
- Never fake evidence. Screenshots are taken by the user.
- After each task, explain what you made in 5 lines or fewer.
