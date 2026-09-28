-- WearHub Core Action SQL Queries (A1 - A5)
-- Target Database: PostgreSQL 16
-- Uses \gset for dynamic parameter extraction across arbitrary seed datasets

-- ============================================================================
-- 0. DYNAMIC SAMPLE PARAMETER EXTRACTION
-- ============================================================================

-- Sample Category ID for Q1 (A1)
SELECT id AS sample_category_id 
FROM categories 
ORDER BY id 
LIMIT 1 \gset

-- Sample Seller ID with open orders for Q2 (A2)
SELECT seller_id AS sample_seller_id 
FROM orders 
WHERE status IN ('placed', 'confirmed', 'packed') 
LIMIT 1 \gset

-- Sample Order ID for Q3 (A3)
SELECT id AS sample_order_id 
FROM orders 
LIMIT 1 \gset

-- Sample Buyer ID and Cursor Anchor for Q4 (A4)
SELECT buyer_id AS sample_buyer_id, placed_at AS sample_cursor_placed_at, id AS sample_cursor_order_id 
FROM orders 
ORDER BY placed_at DESC 
LIMIT 1 \gset

-- Sample Product ID with reviews for Q5 (A5)
SELECT id AS sample_product_id 
FROM products 
WHERE rating_count > 0 
LIMIT 1 \gset

-- ============================================================================
-- Q1 (Action A1): Active products in one category, newest first, 20 per page,
--                 with lowest variant price and cached rating.
-- Target Index: idx_product_categories_category (category_id, product_id)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    p.id AS product_id,
    p.name AS product_name,
    p.rating_avg_x100,
    p.rating_count,
    MIN(pv.price_minor) AS min_price_minor,
    p.created_at
FROM product_categories pc
JOIN products p ON p.id = pc.product_id
JOIN product_variants pv ON pv.product_id = p.id AND pv.deleted_at IS NULL
WHERE pc.category_id = :'sample_category_id'
  AND p.is_active = true
  AND p.deleted_at IS NULL
GROUP BY p.id, p.name, p.rating_avg_x100, p.rating_count, p.created_at
ORDER BY p.created_at DESC
LIMIT 20;

-- ============================================================================
-- Q2 (Action A2): A seller's open orders (placed, confirmed, packed), oldest first.
-- Target Index: idx_orders_seller_open (seller_id, placed_at) WHERE status IN ('placed','confirmed','packed')
-- ============================================================================
SELECT 
    id AS order_id,
    buyer_id,
    status,
    subtotal_minor,
    delivery_fee_minor,
    total_minor,
    placed_at
FROM orders
WHERE seller_id = :'sample_seller_id'
  AND status IN ('placed', 'confirmed', 'packed')
ORDER BY placed_at ASC;

-- ============================================================================
-- Q3 (Action A3): One order with its items and status history for tracking screen.
-- Target Indexes: pk_orders (id), pk_order_items (id), idx_order_status_history_order (order_id, created_at)
-- ============================================================================
SELECT 
    o.id AS order_id,
    o.status,
    o.delivery_address_snapshot,
    o.subtotal_minor,
    o.delivery_fee_minor,
    o.total_minor,
    o.placed_at,
    o.confirmed_at,
    o.packed_at,
    o.shipped_at,
    o.delivered_at,
    (
        SELECT json_agg(json_build_object(
            'id', oi.id,
            'productName', oi.product_name_snapshot,
            'size', oi.size_snapshot,
            'colour', oi.colour_snapshot,
            'quantity', oi.quantity,
            'unitPriceMinor', oi.unit_price_minor,
            'lineTotalMinor', oi.line_total_minor
        ))
        FROM order_items oi
        WHERE oi.order_id = o.id
    ) AS items,
    (
        SELECT json_agg(json_build_object(
            'fromStatus', h.from_status,
            'toStatus', h.to_status,
            'changedByRole', h.changed_by_role,
            'reason', h.reason,
            'createdAt', h.created_at
        ) ORDER BY h.created_at ASC)
        FROM order_status_history h
        WHERE h.order_id = o.id
    ) AS history
FROM orders o
WHERE o.id = :'sample_order_id';

-- ============================================================================
-- Q4 (Action A4): A buyer's order history, newest first, 20 per page (keyset cursor).
-- Target Index: idx_orders_buyer_placed (buyer_id, placed_at DESC, id DESC)
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    id AS order_id,
    seller_id,
    status,
    subtotal_minor,
    delivery_fee_minor,
    total_minor,
    placed_at
FROM orders
WHERE buyer_id = :'sample_buyer_id'
  AND (placed_at < :'sample_cursor_placed_at' 
       OR (placed_at = :'sample_cursor_placed_at' AND id < :'sample_cursor_order_id'))
ORDER BY placed_at DESC, id DESC
LIMIT 20;

-- ============================================================================
-- Q5 (Action A5): A product's latest 20 reviews.
-- Target Index: idx_reviews_product_created (product_id, created_at DESC)
-- ============================================================================
SELECT 
    r.id AS review_id,
    r.buyer_id,
    r.stars,
    r.comment,
    r.created_at
FROM reviews r
WHERE r.product_id = :'sample_product_id'
  AND r.deleted_at IS NULL
ORDER BY r.created_at DESC
LIMIT 20;
