-- WearHub Database Seed Script
-- Target Database: PostgreSQL 16
-- Data Volume:
--   10 Categories, 100 Sellers, 2,000 Products, 8,000 Variants, 5,000 Buyers, ~50,000 Orders, Reviews (~60% of completed items)

BEGIN;

-- Temporarily disable transition enforcement trigger for bulk historic order loading inside seed transaction
ALTER TABLE orders DISABLE TRIGGER trg_orders_enforce_transition;

-- 1. SEED CATEGORIES (10 Categories)
INSERT INTO categories (id, name, slug) VALUES
    (gen_random_uuid(), 'Traditional & Native Wear', 'traditional-native'),
    (gen_random_uuid(), 'Dresses & Gowns', 'dresses-gowns'),
    (gen_random_uuid(), 'Tops, Shirts & Blouses', 'tops-shirts-blouses'),
    (gen_random_uuid(), 'Trousers & Pants', 'trousers-pants'),
    (gen_random_uuid(), 'Skirts', 'skirts'),
    (gen_random_uuid(), 'Jumpsuits & Playsuits', 'jumpsuits-playsuits'),
    (gen_random_uuid(), 'Silk, Satin & Luxury Fabrics', 'silk-satin-luxury'),
    (gen_random_uuid(), 'Outerwear & Jackets', 'outerwear-jackets'),
    (gen_random_uuid(), 'Loungewear & Co-ords', 'loungewear-coords'),
    (gen_random_uuid(), 'Beach & Resort Wear', 'beach-resort');

CREATE TEMP TABLE tmp_categories ON COMMIT DROP AS
SELECT id, (row_number() OVER () - 1)::integer AS c_num FROM categories;
CREATE INDEX ON tmp_categories (c_num);

-- 2. SEED SELLERS (100 Sellers)
INSERT INTO sellers (id, shop_name, owner_name, email, phone)
SELECT
    gen_random_uuid(),
    'Boutique ' || i || ' ' || (ARRAY['Lagos', 'Eko', 'Ikeja', 'Lekki', 'VI', 'Yaba', 'Surulere', 'Ikoyi', 'Maryland', 'Victoria'])[1 + (i % 10)],
    'Owner ' || i || ' ' || (ARRAY['Adeyemi', 'Okonkwo', 'Balogun', 'Bello', 'Eze', 'Okafor', 'Danjuma', 'Lawal', 'Suleiman', 'Williams'])[1 + (i % 10)],
    'seller_' || i || '@wearhub.ng',
    '+23480' || lpad(i::text, 8, '0')
FROM generate_series(1, 100) AS i;

CREATE TEMP TABLE tmp_sellers ON COMMIT DROP AS
SELECT id, (row_number() OVER () - 1)::integer AS s_num FROM sellers;
CREATE INDEX ON tmp_sellers (s_num);

-- 3. SEED PRODUCTS (2,000 Products, 20 per seller)
INSERT INTO products (id, seller_id, name, description, is_active, rating_avg_x100, rating_count)
SELECT
    gen_random_uuid(),
    ts.id,
    (ARRAY['Floral Adire', 'Silk Kaftan', 'Ankara Maxi', 'Senator Suit', 'Linen Agbada', 'Velvet Slip', 'Cotton Kimono', 'Structured Blazer', 'Tiered Midi', 'Pleated Palazzo'])[1 + (i % 10)] || ' #' || i,
    'Premium quality ready-to-wear tailored in Lagos. Sourced with sustainable fabrics and durable stitching. Perfect for formal and casual Nigerian events.',
    true,
    0,
    0
FROM generate_series(1, 2000) AS i
JOIN tmp_sellers ts ON ts.s_num = ((i - 1) % 100);

-- 4. SEED PRODUCT_CATEGORIES (Each product in 1 to 2 categories)
INSERT INTO product_categories (product_id, category_id)
SELECT 
    p.id,
    tc.id
FROM (
    SELECT id, (row_number() OVER () - 1)::integer AS p_num FROM products
) p
CROSS JOIN LATERAL generate_series(0, (p.p_num % 2)) AS cat_idx
JOIN tmp_categories tc ON tc.c_num = ((p.p_num + cat_idx) % 10);

-- 5. SEED PRODUCT_VARIANTS (8,000 Variants: 4 variants per product: S, M, L, XL)
INSERT INTO product_variants (
    id,
    product_id,
    seller_id,
    size,
    colour,
    sku,
    price_minor,
    currency,
    stock_quantity
)
SELECT
    gen_random_uuid(),
    p.id,
    p.seller_id,
    v.size,
    v.colour,
    'SKU-' || lpad(row_number() OVER ()::text, 7, '0'),
    ((8000 + ((p_num * 17 + v_idx * 31) % 52000)) * 100)::bigint, -- 800,000 to 6,000,000 kobo
    'NGN',
    ((p_num * 7 + v_idx * 11) % 51)::integer -- stock 0 to 50
FROM (
    SELECT id, seller_id, row_number() OVER () AS p_num FROM products
) p
CROSS JOIN LATERAL (
    VALUES 
        (1, 'S',  'Indigo'),
        (2, 'M',  'Indigo'),
        (3, 'L',  'Sunset Orange'),
        (4, 'XL', 'Sunset Orange')
) AS v(v_idx, size, colour);

-- 6. SEED BUYERS (5,000 Buyers)
INSERT INTO buyers (id, full_name, email, phone, delivery_address)
SELECT
    gen_random_uuid(),
    'Buyer ' || i || ' ' || (ARRAY['Adeleke', 'Chukwu', 'Ibrahim', 'Ogunleye', 'Abubakar', 'Nwosu', 'Dada', 'Soyinka', 'Akinyemi', 'Babatunde'])[1 + (i % 10)],
    'buyer_' || i || '@wearhub.ng',
    '+23470' || lpad(i::text, 8, '0'),
    'Plot ' || (1 + (i % 80)) || ', ' || (ARRAY['Admiralty Way, Lekki', 'Allen Avenue, Ikeja', 'Bode Thomas, Surulere', 'Awolowo Road, Ikoyi', 'Herbert Macaulay, Yaba', 'Ozumba Mbadiwe, VI', 'Isaac John, GRA Ikeja', 'Ahmadu Bello Way, VI'])[1 + (i % 8)] || ', Lagos'
FROM generate_series(1, 5000) AS i;

CREATE TEMP TABLE tmp_buyers ON COMMIT DROP AS
SELECT id, (row_number() OVER () - 1)::integer AS b_num FROM buyers;
CREATE INDEX ON tmp_buyers (b_num);

-- 7. SEED ORDERS & ORDER_ITEMS (~50,000 Orders)
CREATE TEMP TABLE tmp_orders ON COMMIT DROP AS
SELECT
    gen_random_uuid() AS id,
    tb.id AS buyer_id,
    ts.id AS seller_id,
    CASE 
        WHEN i <= 60 THEN 'placed'::order_status
        WHEN i <= 120 THEN 'confirmed'::order_status
        WHEN i <= 180 THEN 'packed'::order_status
        WHEN i <= 240 THEN 'shipped'::order_status
        WHEN i <= 300 THEN 'delivered'::order_status
        WHEN i <= 4800 THEN 'cancelled'::order_status
        WHEN i <= 7300 THEN 'returned'::order_status
        ELSE 'completed'::order_status
    END AS status,
    'NGN'::char(3) AS currency,
    250000::bigint AS delivery_fee_minor,
    'Plot ' || (1 + (i % 80)) || ', Lekki Phase 1, Lagos' AS delivery_address_snapshot,
    CASE
        WHEN i <= 300 THEN (now() - ((i % 7) || ' days')::interval - ((i * 13 % 1440) || ' minutes')::interval)
        ELSE (now() - ((i % 180) || ' days')::interval - ((i * 17 % 1440) || ' minutes')::interval)
    END AS placed_at,
    (1 + (i % 3)) AS item_count,
    i AS order_seq
FROM generate_series(1, 50000) AS i
JOIN tmp_buyers tb ON tb.b_num = ((i - 1) % 5000)
JOIN tmp_sellers ts ON ts.s_num = ((i - 1) % 100);

-- Prepare temporary fast lookup table of seller variants
CREATE TEMP TABLE tmp_seller_variants ON COMMIT DROP AS
SELECT 
    v.id AS variant_id,
    v.seller_id,
    v.product_id,
    p.name AS product_name,
    v.size,
    v.colour,
    v.price_minor,
    v.currency,
    (row_number() OVER (PARTITION BY v.seller_id ORDER BY v.id) - 1)::integer AS v_num,
    count(*) OVER (PARTITION BY v.seller_id)::integer AS v_total
FROM product_variants v
JOIN products p ON p.id = v.product_id;

CREATE INDEX ON tmp_seller_variants (seller_id, v_num);

-- Generate items into a temporary staging table to compute exact subtotals upfront
CREATE TEMP TABLE tmp_order_items ON COMMIT DROP AS
SELECT
    gen_random_uuid() AS id,
    o.id AS order_id,
    o.seller_id,
    tsv.variant_id,
    tsv.product_id,
    tsv.product_name AS product_name_snapshot,
    tsv.size AS size_snapshot,
    tsv.colour AS colour_snapshot,
    (1 + ((o.order_seq + item_idx) % 2))::integer AS quantity,
    tsv.price_minor AS unit_price_minor,
    tsv.currency,
    ((1 + ((o.order_seq + item_idx) % 2))::bigint * tsv.price_minor) AS line_total_minor,
    o.placed_at AS created_at,
    o.placed_at AS updated_at
FROM tmp_orders o
CROSS JOIN LATERAL generate_series(1, o.item_count) AS item_idx
JOIN tmp_seller_variants tsv 
  ON tsv.seller_id = o.seller_id 
 AND tsv.v_num = ((o.order_seq * 3 + item_idx) % tsv.v_total);

CREATE INDEX ON tmp_order_items (order_id);

-- Compute order subtotals
CREATE TEMP TABLE tmp_order_subtotals ON COMMIT DROP AS
SELECT order_id, SUM(line_total_minor) AS subtotal_minor
FROM tmp_order_items
GROUP BY order_id;

CREATE INDEX ON tmp_order_subtotals (order_id);

-- Insert into orders table directly with correct precomputed subtotal_minor
INSERT INTO orders (
    id,
    buyer_id,
    seller_id,
    status,
    currency,
    subtotal_minor,
    delivery_fee_minor,
    delivery_address_snapshot,
    placed_at,
    confirmed_at,
    packed_at,
    shipped_at,
    delivered_at,
    completed_at,
    cancelled_at,
    cancelled_by,
    created_at,
    updated_at
)
SELECT
    o.id,
    o.buyer_id,
    o.seller_id,
    o.status,
    o.currency,
    tos.subtotal_minor,
    o.delivery_fee_minor,
    o.delivery_address_snapshot,
    o.placed_at,
    CASE WHEN o.status IN ('confirmed', 'packed', 'shipped', 'delivered', 'completed', 'return_requested', 'returned') THEN o.placed_at + interval '2 hours' ELSE NULL END,
    CASE WHEN o.status IN ('packed', 'shipped', 'delivered', 'completed', 'return_requested', 'returned') THEN o.placed_at + interval '6 hours' ELSE NULL END,
    CASE WHEN o.status IN ('shipped', 'delivered', 'completed', 'return_requested', 'returned') THEN o.placed_at + interval '12 hours' ELSE NULL END,
    CASE WHEN o.status IN ('delivered', 'completed', 'return_requested', 'returned') THEN o.placed_at + interval '24 hours' ELSE NULL END,
    CASE WHEN o.status IN ('completed') THEN o.placed_at + interval '8 days' ELSE NULL END,
    CASE WHEN o.status = 'cancelled' THEN o.placed_at + interval '3 hours' ELSE NULL END,
    CASE WHEN o.status = 'cancelled' THEN 'buyer' ELSE NULL END,
    o.placed_at,
    o.placed_at
FROM tmp_orders o
JOIN tmp_order_subtotals tos ON tos.order_id = o.id;

-- Insert staging items into real order_items table
INSERT INTO order_items (
    id,
    order_id,
    seller_id,
    variant_id,
    product_id,
    product_name_snapshot,
    size_snapshot,
    colour_snapshot,
    quantity,
    unit_price_minor,
    currency,
    created_at,
    updated_at
)
SELECT
    id,
    order_id,
    seller_id,
    variant_id,
    product_id,
    product_name_snapshot,
    size_snapshot,
    colour_snapshot,
    quantity,
    unit_price_minor,
    currency,
    created_at,
    updated_at
FROM tmp_order_items;

-- 8. SEED REVIEWS (~60% of items in completed orders)
INSERT INTO reviews (
    id,
    order_item_id,
    order_id,
    product_id,
    buyer_id,
    order_status,
    stars,
    comment,
    created_at,
    updated_at
)
SELECT
    gen_random_uuid(),
    oi.id,
    o.id,
    oi.product_id,
    o.buyer_id,
    'completed'::order_status,
    (1 + ((row_num * 13) % 5))::smallint, -- stars 1 to 5
    (ARRAY[
        'Superb ready-to-wear finish! Perfect fit for my event.',
        'Fabric quality is outstanding. Fast delivery in Lagos.',
        'Great colours and comfortable material.',
        'Good stitching and true to size.',
        'Satisfied with the purchase, will order from this boutique again.'
    ])[1 + (row_num % 5)],
    o.placed_at + interval '9 days',
    o.placed_at + interval '9 days'
FROM (
    SELECT 
        oi.id,
        oi.order_id,
        oi.product_id,
        row_number() OVER () AS row_num
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.status = 'completed'
) oi
JOIN orders o ON o.id = oi.order_id
WHERE (oi.row_num % 10) < 6; -- 60% of completed items

-- Sync product average ratings and review counts from the seeded reviews
UPDATE products p
SET rating_avg_x100 = r.avg_x100,
    rating_count = r.cnt,
    updated_at = now()
FROM (
    SELECT 
        product_id,
        ROUND(AVG(stars) * 100)::integer AS avg_x100,
        COUNT(*)::integer AS cnt
    FROM reviews
    WHERE deleted_at IS NULL
    GROUP BY product_id
) r
WHERE p.id = r.product_id;

-- Force deferred constraint checks to execute now so pending trigger events are cleared
SET CONSTRAINTS ALL IMMEDIATE;

-- Re-enable transition enforcement trigger before COMMIT
ALTER TABLE orders ENABLE TRIGGER trg_orders_enforce_transition;

COMMIT;

-- Analyze database statistics for optimal query planning
ANALYZE;

-- Print row counts for all tables
SELECT 'buyers' AS table_name, count(*) AS row_count FROM buyers
UNION ALL SELECT 'sellers', count(*) FROM sellers
UNION ALL SELECT 'categories', count(*) FROM categories
UNION ALL SELECT 'products', count(*) FROM products
UNION ALL SELECT 'product_categories', count(*) FROM product_categories
UNION ALL SELECT 'product_variants', count(*) FROM product_variants
UNION ALL SELECT 'orders', count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items
UNION ALL SELECT 'order_status_transitions', count(*) FROM order_status_transitions
UNION ALL SELECT 'order_status_history', count(*) FROM order_status_history
UNION ALL SELECT 'reviews', count(*) FROM reviews
ORDER BY table_name;
