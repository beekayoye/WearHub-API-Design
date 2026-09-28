-- WearHub Database Schema Migration 001
-- Target Database: PostgreSQL 16
-- Currency: NGN (Minor units: kobo)

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Clean drop for idempotent migration
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS order_status_history CASCADE;
DROP TABLE IF EXISTS order_status_transitions CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS product_variants CASCADE;
DROP TABLE IF EXISTS product_categories CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS buyers CASCADE;
DROP TYPE IF EXISTS order_status CASCADE;

-- 1. ENUMS
CREATE TYPE order_status AS ENUM (
    'placed',
    'confirmed',
    'packed',
    'shipped',
    'delivered',
    'completed',
    'cancelled',
    'return_requested',
    'returned'
);

-- 2. TABLES

-- 2.1 buyers
CREATE TABLE buyers (
    id uuid DEFAULT gen_random_uuid(),
    full_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    delivery_address text NOT NULL,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_buyers PRIMARY KEY (id),
    CONSTRAINT uq_buyers_email UNIQUE (email),
    CONSTRAINT uq_buyers_phone UNIQUE (phone)
);

-- 2.2 sellers
CREATE TABLE sellers (
    id uuid DEFAULT gen_random_uuid(),
    shop_name text NOT NULL,
    owner_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_sellers PRIMARY KEY (id),
    CONSTRAINT uq_sellers_shop_name UNIQUE (shop_name),
    CONSTRAINT uq_sellers_email UNIQUE (email)
);

-- 2.3 categories
CREATE TABLE categories (
    id uuid DEFAULT gen_random_uuid(),
    name text NOT NULL,
    slug text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_categories PRIMARY KEY (id),
    CONSTRAINT uq_categories_name UNIQUE (name),
    CONSTRAINT uq_categories_slug UNIQUE (slug)
);

-- 2.4 products
CREATE TABLE products (
    id uuid DEFAULT gen_random_uuid(),
    seller_id uuid NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    rating_avg_x100 integer NOT NULL DEFAULT 0,
    rating_count integer NOT NULL DEFAULT 0,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_products PRIMARY KEY (id),
    CONSTRAINT fk_products_seller FOREIGN KEY (seller_id) REFERENCES sellers (id),
    CONSTRAINT uq_products_id_seller UNIQUE (id, seller_id)
);

-- 2.5 product_categories
CREATE TABLE product_categories (
    product_id uuid NOT NULL,
    category_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_product_categories PRIMARY KEY (product_id, category_id),
    CONSTRAINT fk_product_categories_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_product_categories_category FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE RESTRICT
);

-- 2.6 product_variants
CREATE TABLE product_variants (
    id uuid DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL,
    seller_id uuid NOT NULL,
    size text NOT NULL,
    colour text NOT NULL,
    sku text NOT NULL,
    price_minor bigint NOT NULL,
    currency char(3) NOT NULL DEFAULT 'NGN',
    stock_quantity integer NOT NULL,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_product_variants PRIMARY KEY (id),
    CONSTRAINT fk_product_variants_product FOREIGN KEY (product_id) REFERENCES products (id),
    CONSTRAINT fk_product_variants_seller FOREIGN KEY (seller_id) REFERENCES sellers (id),
    CONSTRAINT fk_product_variants_product_seller FOREIGN KEY (product_id, seller_id) REFERENCES products (id, seller_id),
    CONSTRAINT uq_product_variants_product_size_colour UNIQUE (product_id, size, colour),
    CONSTRAINT uq_product_variants_sku UNIQUE (sku),
    CONSTRAINT uq_product_variants_id_seller UNIQUE (id, seller_id),
    CONSTRAINT uq_product_variants_id_product UNIQUE (id, product_id),
    CONSTRAINT uq_product_variants_composite UNIQUE (id, seller_id, product_id, price_minor, currency),
    CONSTRAINT ck_product_variants_stock_nonneg CHECK (stock_quantity >= 0),
    CONSTRAINT ck_product_variants_price_positive CHECK (price_minor > 0),
    CONSTRAINT ck_product_variants_currency_upper CHECK (currency ~ '^[A-Z]{3}$')
);

-- 2.7 orders
CREATE TABLE orders (
    id uuid DEFAULT gen_random_uuid(),
    buyer_id uuid NOT NULL,
    seller_id uuid NOT NULL,
    status order_status NOT NULL DEFAULT 'placed',
    currency char(3) NOT NULL DEFAULT 'NGN',
    subtotal_minor bigint NOT NULL DEFAULT 0,
    delivery_fee_minor bigint NOT NULL DEFAULT 0,
    total_minor bigint GENERATED ALWAYS AS (subtotal_minor + delivery_fee_minor) STORED,
    delivery_address_snapshot text NOT NULL,
    placed_at timestamptz NOT NULL DEFAULT now(),
    confirmed_at timestamptz,
    packed_at timestamptz,
    shipped_at timestamptz,
    delivered_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    cancelled_by text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_orders PRIMARY KEY (id),
    CONSTRAINT fk_orders_buyer FOREIGN KEY (buyer_id) REFERENCES buyers (id),
    CONSTRAINT fk_orders_seller FOREIGN KEY (seller_id) REFERENCES sellers (id),
    CONSTRAINT uq_orders_id_seller UNIQUE (id, seller_id),
    CONSTRAINT uq_orders_id_currency UNIQUE (id, currency),
    CONSTRAINT uq_orders_id_buyer_status UNIQUE (id, buyer_id, status),
    CONSTRAINT ck_orders_subtotal_nonneg CHECK (subtotal_minor >= 0),
    CONSTRAINT ck_orders_delivery_fee_nonneg CHECK (delivery_fee_minor >= 0),
    CONSTRAINT ck_orders_currency_upper CHECK (currency ~ '^[A-Z]{3}$')
);

-- 2.8 order_items
CREATE TABLE order_items (
    id uuid DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL,
    seller_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    product_name_snapshot text NOT NULL,
    size_snapshot text NOT NULL,
    colour_snapshot text NOT NULL,
    quantity integer NOT NULL,
    unit_price_minor bigint NOT NULL,
    currency char(3) NOT NULL DEFAULT 'NGN',
    line_total_minor bigint GENERATED ALWAYS AS (unit_price_minor * quantity) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_order_items PRIMARY KEY (id),
    CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders (id),
    CONSTRAINT fk_order_items_seller FOREIGN KEY (seller_id) REFERENCES sellers (id),
    CONSTRAINT fk_order_items_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id),
    CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES products (id),
    CONSTRAINT fk_order_items_order_seller FOREIGN KEY (order_id, seller_id) REFERENCES orders (id, seller_id),
    CONSTRAINT fk_order_items_variant_seller FOREIGN KEY (variant_id, seller_id) REFERENCES product_variants (id, seller_id),
    CONSTRAINT fk_order_items_variant_product FOREIGN KEY (variant_id, product_id) REFERENCES product_variants (id, product_id),
    CONSTRAINT fk_order_items_order_currency FOREIGN KEY (order_id, currency) REFERENCES orders (id, currency),
    CONSTRAINT uq_order_items_order_variant UNIQUE (order_id, variant_id),
    CONSTRAINT uq_order_items_id_order UNIQUE (id, order_id),
    CONSTRAINT uq_order_items_id_product UNIQUE (id, product_id),
    CONSTRAINT ck_order_items_quantity_positive CHECK (quantity > 0),
    CONSTRAINT ck_order_items_unit_price_positive CHECK (unit_price_minor > 0),
    CONSTRAINT ck_order_items_currency_upper CHECK (currency ~ '^[A-Z]{3}$')
);

-- 2.9 order_status_transitions
CREATE TABLE order_status_transitions (
    from_status order_status NOT NULL,
    to_status order_status NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_order_status_transitions PRIMARY KEY (from_status, to_status)
);

-- 2.10 order_status_history
CREATE TABLE order_status_history (
    id uuid DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL,
    from_status order_status,
    to_status order_status NOT NULL,
    changed_by_role text NOT NULL,
    reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_order_status_history PRIMARY KEY (id),
    CONSTRAINT fk_order_status_history_order FOREIGN KEY (order_id) REFERENCES orders (id)
);

-- 2.11 reviews
CREATE TABLE reviews (
    id uuid DEFAULT gen_random_uuid(),
    order_item_id uuid NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    buyer_id uuid NOT NULL,
    order_status order_status NOT NULL,
    stars smallint NOT NULL,
    comment text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_reviews PRIMARY KEY (id),
    CONSTRAINT uq_reviews_order_item UNIQUE (order_item_id),
    CONSTRAINT fk_reviews_buyer FOREIGN KEY (buyer_id) REFERENCES buyers (id),
    CONSTRAINT fk_reviews_product FOREIGN KEY (product_id) REFERENCES products (id),
    CONSTRAINT fk_reviews_order_item_order FOREIGN KEY (order_item_id, order_id) REFERENCES order_items (id, order_id),
    CONSTRAINT fk_reviews_order_item_product FOREIGN KEY (order_item_id, product_id) REFERENCES order_items (id, product_id),
    CONSTRAINT fk_reviews_order_completed FOREIGN KEY (order_id, buyer_id, order_status) REFERENCES orders (id, buyer_id, status),
    CONSTRAINT ck_reviews_order_status_completed CHECK (order_status = 'completed'),
    CONSTRAINT ck_reviews_stars CHECK (stars BETWEEN 1 AND 5)
);

-- 3. REFERENCE DATA: 11 Allowed Transitions
INSERT INTO order_status_transitions (from_status, to_status) VALUES
    ('placed', 'confirmed'),
    ('placed', 'cancelled'),
    ('confirmed', 'packed'),
    ('confirmed', 'cancelled'),
    ('packed', 'shipped'),
    ('packed', 'cancelled'),
    ('shipped', 'delivered'),
    ('delivered', 'completed'),
    ('delivered', 'return_requested'),
    ('return_requested', 'returned'),
    ('return_requested', 'completed');

-- 4. FUNCTIONS & TRIGGERS

-- 4.1 Automated updated_at Function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_buyers_updated_at BEFORE UPDATE ON buyers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_sellers_updated_at BEFORE UPDATE ON sellers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_categories_updated_at BEFORE UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_product_categories_updated_at BEFORE UPDATE ON product_categories FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_product_variants_updated_at BEFORE UPDATE ON product_variants FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_order_items_updated_at BEFORE UPDATE ON order_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_order_status_transitions_updated_at BEFORE UPDATE ON order_status_transitions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_order_status_history_updated_at BEFORE UPDATE ON order_status_history FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_reviews_updated_at BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 4.2 State Machine Transition Enforcer Trigger
CREATE OR REPLACE FUNCTION enforce_order_transition()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'placed' THEN
            RAISE EXCEPTION USING 
                ERRCODE = 'check_violation',
                CONSTRAINT = 'order_transition_illegal',
                MESSAGE = 'New orders must start in placed status';
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.status IS DISTINCT FROM OLD.status THEN
            IF NOT EXISTS (
                SELECT 1 
                FROM order_status_transitions 
                WHERE from_status = OLD.status AND to_status = NEW.status
            ) THEN
                RAISE EXCEPTION USING 
                    ERRCODE = 'check_violation',
                    CONSTRAINT = 'order_transition_illegal',
                    MESSAGE = 'Illegal order status transition from ' || OLD.status || ' to ' || NEW.status;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_enforce_transition
    BEFORE INSERT OR UPDATE OF status ON orders
    FOR EACH ROW
    EXECUTE FUNCTION enforce_order_transition();

-- 4.3 Deferred Order Subtotal Integrity Check
CREATE OR REPLACE FUNCTION check_order_subtotal()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id uuid;
    v_expected_subtotal bigint;
    v_calculated_subtotal bigint;
BEGIN
    IF TG_TABLE_NAME = 'orders' THEN
        v_order_id := COALESCE(NEW.id, OLD.id);
    ELSE
        v_order_id := COALESCE(NEW.order_id, OLD.order_id);
    END IF;

    SELECT subtotal_minor INTO v_expected_subtotal FROM orders WHERE id = v_order_id;

    IF v_expected_subtotal IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(line_total_minor), 0)
    INTO v_calculated_subtotal
    FROM order_items
    WHERE order_id = v_order_id;

    IF v_expected_subtotal <> v_calculated_subtotal THEN
        RAISE EXCEPTION USING 
            ERRCODE = 'check_violation',
            CONSTRAINT = 'order_subtotal_mismatch',
            MESSAGE = 'Order subtotal (' || v_expected_subtotal || ') does not match sum of item line totals (' || v_calculated_subtotal || ')';
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_orders_subtotal_matches
    AFTER INSERT OR UPDATE ON orders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION check_order_subtotal();

CREATE CONSTRAINT TRIGGER trg_order_items_subtotal_matches
    AFTER INSERT OR UPDATE OR DELETE ON order_items
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION check_order_subtotal();

-- 4.4 Order Status History Audit Trigger
CREATE OR REPLACE FUNCTION log_order_status_history()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_status_history (
            order_id,
            from_status,
            to_status,
            changed_by_role,
            reason
        ) VALUES (
            NEW.id,
            NULL,
            NEW.status,
            'buyer',
            'Order placed'
        );
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.status IS DISTINCT FROM OLD.status THEN
            INSERT INTO order_status_history (
                order_id,
                from_status,
                to_status,
                changed_by_role,
                reason
            ) VALUES (
                NEW.id,
                OLD.status,
                NEW.status,
                COALESCE(NEW.cancelled_by, 'system'),
                CASE 
                    WHEN NEW.status = 'cancelled' THEN 'Order cancelled'
                    WHEN NEW.status = 'return_requested' THEN 'Return requested'
                    ELSE 'Status transition to ' || NEW.status
                END
            );
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_log_history
    AFTER INSERT OR UPDATE OF status ON orders
    FOR EACH ROW
    EXECUTE FUNCTION log_order_status_history();

-- 4.5 Rating Aggregation Sync Trigger on Reviews
CREATE OR REPLACE FUNCTION sync_product_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_product_id uuid;
    v_avg_x100 integer;
    v_count integer;
BEGIN
    v_product_id := COALESCE(NEW.product_id, OLD.product_id);

    SELECT 
        COALESCE(ROUND(AVG(stars) * 100)::integer, 0),
        COUNT(*)::integer
    INTO 
        v_avg_x100,
        v_count
    FROM reviews
    WHERE product_id = v_product_id AND deleted_at IS NULL;

    UPDATE products
    SET rating_avg_x100 = v_avg_x100,
        rating_count = v_count,
        updated_at = now()
    WHERE id = v_product_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reviews_sync_rating
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW
    EXECUTE FUNCTION sync_product_rating();

-- 5. INDEXES (Named specifically in Docs/03 section 7)

-- A1 Browse a category
CREATE INDEX idx_product_categories_category ON product_categories (category_id, product_id);

-- A2 Seller's open orders
CREATE INDEX idx_orders_seller_open ON orders (seller_id, placed_at) WHERE status IN ('placed', 'confirmed', 'packed');

-- A3 Order tracking
CREATE INDEX idx_order_status_history_order ON order_status_history (order_id, created_at);

-- A4 Buyer's order history
CREATE INDEX idx_orders_buyer_placed ON orders (buyer_id, placed_at DESC, id DESC);

-- A4 Auto-complete job
CREATE INDEX idx_orders_delivered ON orders (delivered_at) WHERE status = 'delivered';

-- A5 Product reviews
CREATE INDEX idx_reviews_product_created ON reviews (product_id, created_at DESC);
