-- WearHub Defensive Integrity Test Suite
-- Target Database: PostgreSQL 16
-- This file contains SQL statements demonstrating database-level enforcement of business invariants.
-- Every statement below is designed to fail and be rejected by PostgreSQL constraints/triggers.

\set VERBOSITY verbose

-- ============================================================================
-- 1. PREVENT NEGATIVE STOCK / OVER-SELLING (Requirements R1, R2, Action A1)
-- Rule: Variant stock cannot go below zero under any concurrency or race condition.
-- Expected Failure: ck_product_variants_stock_nonneg
-- ============================================================================

SELECT id AS sample_variant_id 
FROM product_variants 
LIMIT 1 \gset

-- Setup: Set stock quantity to exactly 1
UPDATE product_variants 
SET stock_quantity = 1 
WHERE id = :'sample_variant_id';

-- Violation: Attempt to deduct 2 units from 1 available stock
UPDATE product_variants 
SET stock_quantity = stock_quantity - 2 
WHERE id = :'sample_variant_id';


-- ============================================================================
-- 2. VERIFIED PURCHASE REVIEWS ONLY ON COMPLETED ORDERS (Requirement R10, Action A5)
-- Rule: A buyer can only review an item if the parent order is in 'completed' status.
-- Expected Failure: fk_reviews_order_completed
-- ============================================================================

SELECT 
    oi.id AS shipped_item_id, 
    oi.order_id AS shipped_order_id, 
    oi.product_id AS shipped_product_id, 
    o.buyer_id AS shipped_buyer_id, 
    o.status AS shipped_order_status 
FROM order_items oi 
JOIN orders o ON o.id = oi.order_id 
WHERE o.status = 'shipped' 
LIMIT 1 \gset

-- Violation: Submit review on an order that is still in transit ('shipped')
INSERT INTO reviews (
    id, 
    order_item_id, 
    order_id, 
    product_id, 
    buyer_id, 
    order_status, 
    stars, 
    comment
) VALUES (
    gen_random_uuid(), 
    :'shipped_item_id', 
    :'shipped_order_id', 
    :'shipped_product_id', 
    :'shipped_buyer_id', 
    :'shipped_order_status', 
    5, 
    'Attempting review prior to order completion.'
);


-- ============================================================================
-- 3. FORBIDDEN ORDER TRANSITION: SHIPPED TO CANCELLED (Requirement R6, Actions A2, A4)
-- Rule: Once an order has been dispatched ('shipped'), it cannot be directly cancelled.
-- Expected Failure: order_transition_illegal (raised by trg_orders_enforce_transition)
-- ============================================================================

SELECT id AS sample_shipped_order_id 
FROM orders 
WHERE status = 'shipped' 
LIMIT 1 \gset

-- Violation: Direct cancellation of an order currently in transit with courier
UPDATE orders 
SET status = 'cancelled', 
    cancelled_by = 'buyer' 
WHERE id = :'sample_shipped_order_id';


-- ============================================================================
-- 4. SINGLE-SELLER ORDER PURITY (Requirement R4, Action A1)
-- Rule: An order belongs to exactly one seller. Line items from a different seller are rejected.
-- Expected Failure: fk_order_items_variant_seller
-- ============================================================================

SELECT 
    o.id AS cross_order_id, 
    o.seller_id AS cross_order_seller_id, 
    v.id AS different_seller_variant_id, 
    v.product_id AS different_seller_product_id, 
    v.price_minor AS diff_price_minor, 
    v.currency AS diff_currency 
FROM orders o 
CROSS JOIN LATERAL (
    SELECT id, product_id, price_minor, currency 
    FROM product_variants 
    WHERE seller_id <> o.seller_id 
    LIMIT 1
) v
LIMIT 1 \gset

-- Violation: Insert line item referencing a variant belonging to a different boutique
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
    currency
) VALUES (
    gen_random_uuid(), 
    :'cross_order_id', 
    :'cross_order_seller_id', 
    :'different_seller_variant_id', 
    :'different_seller_product_id', 
    'Illicit Cross-Seller Variant', 
    'M', 
    'Indigo', 
    1, 
    :'diff_price_minor', 
    :'diff_currency'
);


-- ============================================================================
-- 5. DEFERRED ORDER SUBTOTAL INTEGRITY (Requirement R3, Action A1)
-- Rule: orders.subtotal_minor must equal the sum of child order_items line totals at COMMIT.
-- Expected Failure: order_subtotal_mismatch (raised by deferred constraint trigger)
-- ============================================================================

SELECT id AS subtotal_test_order_id 
FROM orders 
WHERE status = 'completed' 
LIMIT 1 \gset

-- Violation: Modify order subtotal to tamper with pricing before COMMIT
BEGIN;
UPDATE orders 
SET subtotal_minor = subtotal_minor + 5000000 
WHERE id = :'subtotal_test_order_id';
COMMIT;


-- ============================================================================
-- 6. FORBIDDEN ORDER TRANSITION: COMPLETED TO RETURN_REQUESTED (Requirement R8, Action A4)
-- Rule: 'completed' status indicates the 7-day return window has closed; returns are forbidden.
-- Expected Failure: order_transition_illegal (raised by trg_orders_enforce_transition)
-- ============================================================================

SELECT id AS sample_completed_order_id 
FROM orders 
WHERE status = 'completed' 
LIMIT 1 \gset

-- Violation: Attempt to request return on an order whose 7-day return window expired
UPDATE orders 
SET status = 'return_requested' 
WHERE id = :'sample_completed_order_id';
