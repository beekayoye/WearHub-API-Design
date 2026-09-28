# WearHub REST API Specification

This document provides the complete API contracts for the WearHub fashion marketplace. All endpoints adhere to versioned REST design (`/v1/...`), strict JSON schemas, camelCase naming conventions, and explicit error definitions.

---

## 1. Global Conventions & Standards

### 1.1 Base URL & Transport
- **Base URL**: `https://api.wearhub.ng/v1`
- **Transport**: HTTPS / HTTP/2
- **Character Encoding**: UTF-8

### 1.2 Authentication & Headers
- **Authentication**: `Authorization: Bearer <jwt_token>` (identifies user ID and role: `buyer`, `seller`, `admin`).
- **Content Type**: `Content-Type: application/json`
- **Idempotency Key**: `Idempotency-Key: <uuid-string>` (mandatory on `POST /v1/orders`).

### 1.3 Money Format
Monetary values are represented as minor integer units (kobo) paired with ISO-4217 uppercase currency codes:
```json
{
  "amountMinor": 2500000,
  "currency": "NGN"
}
```

### 1.4 Standard Error Response Shape
Every non-2xx error returns a structured RFC-7807 compliant JSON object:
```json
{
  "error": {
    "code": "INVALID_STATE",
    "message": "Human readable explanation of the error condition.",
    "details": [
      {
        "field": "stockQuantity",
        "issue": "Insufficient available inventory"
      }
    ]
  }
}
```

### 1.5 Common HTTP Error Codes
- **`400 BAD_REQUEST`**: Malformed JSON or syntax failure.
- **`401 UNAUTHORIZED`**: Missing or expired Bearer token.
- **`403 FORBIDDEN`**: Insufficient role privileges (e.g. buyer attempting to confirm an order).
- **`404 NOT_FOUND`**: Target resource identifier does not exist.
- **`409 CONFLICT`**: State conflict (e.g. out of stock, illegal status transition).
- **`422 UNPROCESSABLE_ENTITY`**: Semantic validation failure (e.g. mixed sellers in single checkout).
- **`429 TOO_MANY_REQUESTS`**: Rate limit exceeded (standard sliding window).
- **`500 INTERNAL_SERVER_ERROR`**: Unhandled platform failure.

### 1.6 Idempotency Semantics
1. **Order Creation (`POST /v1/orders`)**: Requires `Idempotency-Key: <UUID>`.
   - Re-sending the identical payload with the same key returns the previously created order (`200 OK` or `201 Created`).
   - Re-sending a different payload with an existing key returns `422 IDEMPOTENCY_KEY_PAYLOAD_MISMATCH`.
2. **Order Lifecycle Mutations**: Status change endpoints (`/confirm`, `/pack`, `/ship`, `/deliver`, `/cancel`) are naturally idempotent. If an order is already in the target status, the server returns the existing order object with `200 OK`.

### 1.7 Standard Pagination Envelope
All listing endpoints use cursor pagination with a maximum `limit` of 100:
```json
{
  "data": [],
  "pagination": {
    "limit": 20,
    "nextCursor": "ZXlKaWRI...",
    "hasMore": true
  }
}
```

---

## 2. Core Action Contracts (A1–A5)

---

### Action A1: Catalog Discovery & Order Placement

#### 2.1.1 `GET /v1/categories/{categoryId}/products`
Fetch garments listed under a specific taxonomy category.

- **Query Parameters**:
  - `limit` (integer, optional, default 20, max 100)
  - `cursor` (string, optional)
  - `sortBy` (string, optional: `createdAt:desc`, `price:asc`, `price:desc`, `rating:desc`)
  - `minPriceMinor` (integer, optional)
  - `maxPriceMinor` (integer, optional)
- **Response `200 OK`**:
```json
{
  "data": [
    {
      "id": "7b7e8ef6-c22e-4cf4-a083-d9d300ebbc33",
      "sellerId": "09f69748-0b54-46da-b7ec-aa6a4f91d09e",
      "name": "Lagos Floral Adire Silk Dress",
      "description": "Hand-dyed pure silk maxi dress designed in Lagos.",
      "isActive": true,
      "ratingAvg": 4.85,
      "ratingCount": 24,
      "priceRange": {
        "minPrice": { "amountMinor": 3500000, "currency": "NGN" },
        "maxPrice": { "amountMinor": 4200000, "currency": "NGN" }
      },
      "availableSizes": ["S", "M", "L", "UK 12"],
      "availableColours": ["Indigo", "Sunset Orange"]
    }
  ],
  "pagination": {
    "limit": 20,
    "nextCursor": "eyJwbGFjZWRBdCI6IjIwMjYtMDktMjdUMjI6MDA6MDAuMDAwWiIsImlkIjoiN2I3ZThlZjYtYzIyZS00Y2Y0LWEwODMtZDlkMzAwZWJiYzMzIn0=",
    "hasMore": false
  }
}
```
- **Errors**: `400 BAD_REQUEST`, `404 CATEGORY_NOT_FOUND`.

---

#### 2.1.2 `GET /v1/products/{productId}`
Retrieve full product details including all active size and colour variants with live stock availability.

- **Path Parameters**: `productId` (UUID)
- **Response `200 OK`**:
```json
{
  "id": "7b7e8ef6-c22e-4cf4-a083-d9d300ebbc33",
  "sellerId": "09f69748-0b54-46da-b7ec-aa6a4f91d09e",
  "seller": {
    "shopName": "Eko Couture",
    "ownerName": "Folake Johnson"
  },
  "name": "Lagos Floral Adire Silk Dress",
  "description": "Hand-dyed pure silk maxi dress tailored for ready-to-wear comfort.",
  "isActive": true,
  "ratingAvg": 4.85,
  "ratingCount": 24,
  "variants": [
    {
      "id": "6a96f1d2-0695-4674-9c4c-35a0f62eec41",
      "size": "M",
      "colour": "Indigo",
      "sku": "EKO-ADR-M-IND",
      "price": { "amountMinor": 3500000, "currency": "NGN" },
      "stockQuantity": 8
    },
    {
      "id": "8a32d1d2-1245-4674-9c4c-35a0f62eec99",
      "size": "L",
      "colour": "Indigo",
      "sku": "EKO-ADR-L-IND",
      "price": { "amountMinor": 3500000, "currency": "NGN" },
      "stockQuantity": 0
    }
  ],
  "categories": [
    { "id": "11111111-2222-3333-4444-555555555555", "name": "Dresses", "slug": "dresses" }
  ],
  "createdAt": "2026-09-20T10:00:00.000Z"
}
```
- **Errors**: `400 BAD_REQUEST`, `404 PRODUCT_NOT_FOUND`.

---

#### 2.1.3 `POST /v1/orders`
Place a ready-to-wear order with locked prices and conditional stock reservation (**R1**, **R2**, **R3**, **R4**).

- **Headers**:
  - `Authorization: Bearer <buyer_jwt>` (Required)
  - `Idempotency-Key: <UUID>` (Required)
- **Request Body**:
```json
{
  "sellerId": "09f69748-0b54-46da-b7ec-aa6a4f91d09e",
  "deliveryAddress": "Block 4, Flat 12, Lekki Phase 1, Lagos",
  "items": [
    {
      "variantId": "6a96f1d2-0695-4674-9c4c-35a0f62eec41",
      "quantity": 2
    }
  ]
}
```
- **Response `201 Created`**:
```json
{
  "id": "e4b6dc50-137b-4ec9-8d14-0d507127e7eb",
  "buyerId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "sellerId": "09f69748-0b54-46da-b7ec-aa6a4f91d09e",
  "status": "placed",
  "deliveryAddressSnapshot": "Block 4, Flat 12, Lekki Phase 1, Lagos",
  "subtotal": { "amountMinor": 7000000, "currency": "NGN" },
  "deliveryFee": { "amountMinor": 250000, "currency": "NGN" },
  "total": { "amountMinor": 7250000, "currency": "NGN" },
  "items": [
    {
      "id": "5c9b4e18-6927-4c07-b371-70bf89be8c89",
      "variantId": "6a96f1d2-0695-4674-9c4c-35a0f62eec41",
      "productId": "7b7e8ef6-c22e-4cf4-a083-d9d300ebbc33",
      "productNameSnapshot": "Lagos Floral Adire Silk Dress",
      "sizeSnapshot": "M",
      "colourSnapshot": "Indigo",
      "quantity": 2,
      "unitPrice": { "amountMinor": 3500000, "currency": "NGN" },
      "lineTotal": { "amountMinor": 7000000, "currency": "NGN" }
    }
  ],
  "placedAt": "2026-09-27T22:30:00.000Z",
  "createdAt": "2026-09-27T22:30:00.000Z"
}
```
- **Errors**:
  - `400 BAD_REQUEST`: Missing mandatory fields or malformed payload.
  - `401 UNAUTHORIZED`: Unauthenticated user.
  - `409 OUT_OF_STOCK`: Atomic conditional update failed because `stock_quantity < requested quantity`.
  - `422 MIXED_SELLERS`: Cart items belong to different sellers (**R4**).
  - `422 VARIANT_UNAVAILABLE`: Variant is inactive or soft-deleted.
  - `422 IDEMPOTENCY_KEY_PAYLOAD_MISMATCH`: Key reused with altered payload.
- **Idempotency**: Fully idempotent when providing the same `Idempotency-Key` and matching body.

---

### Action A2: Seller Order Fulfillment Lifecycle

#### 2.2.1 `POST /v1/orders/{orderId}/confirm`
Seller confirms readiness to fulfill the placed order.
- **Headers**: `Authorization: Bearer <seller_jwt>`
- **Response `200 OK`**: Updated order object with `status: "confirmed"`, `confirmedAt: "2026-09-27T22:35:00.000Z"`.
- **Errors**: `403 FORBIDDEN` (not order seller), `404 ORDER_NOT_FOUND`, `409 INVALID_TRANSITION` (current status != `placed`).
- **Idempotency**: Safe to repeat; returns 200 if already `confirmed`.

---

#### 2.2.2 `POST /v1/orders/{orderId}/pack`
Seller marks the order packed and ready for logistics dispatch.
- **Headers**: `Authorization: Bearer <seller_jwt>`
- **Response `200 OK`**: Updated order object with `status: "packed"`, `packedAt: "2026-09-27T22:45:00.000Z"`.
- **Errors**: `403 FORBIDDEN`, `404 ORDER_NOT_FOUND`, `409 INVALID_TRANSITION` (current status != `confirmed`).
- **Idempotency**: Safe to repeat; returns 200 if already `packed`.

---

#### 2.2.3 `POST /v1/orders/{orderId}/ship`
Seller transfers parcel to delivery courier for Lagos transit.
- **Headers**: `Authorization: Bearer <seller_jwt>`
- **Response `200 OK`**: Updated order object with `status: "shipped"`, `shippedAt: "2026-09-27T23:00:00.000Z"`.
- **Errors**: `403 FORBIDDEN`, `404 ORDER_NOT_FOUND`, `409 INVALID_TRANSITION` (current status != `packed`).
- **Idempotency**: Safe to repeat; returns 200 if already `shipped`.

---

### Action A3: Real-Time Order Tracking

#### 2.3.1 `GET /v1/orders/{orderId}`
Fetch order status and chronological timeline.
- **Headers**: `Authorization: Bearer <jwt_token>` (Buyer or Seller of this order, or Admin)
- **Response `200 OK`**:
```json
{
  "id": "e4b6dc50-137b-4ec9-8d14-0d507127e7eb",
  "status": "shipped",
  "placedAt": "2026-09-27T22:30:00.000Z",
  "confirmedAt": "2026-09-27T22:35:00.000Z",
  "packedAt": "2026-09-27T22:45:00.000Z",
  "shippedAt": "2026-09-27T23:00:00.000Z",
  "history": [
    { "fromStatus": null, "toStatus": "placed", "changedByRole": "buyer", "at": "2026-09-27T22:30:00.000Z" },
    { "fromStatus": "placed", "toStatus": "confirmed", "changedByRole": "seller", "at": "2026-09-27T22:35:00.000Z" },
    { "fromStatus": "confirmed", "toStatus": "packed", "changedByRole": "seller", "at": "2026-09-27T22:45:00.000Z" },
    { "fromStatus": "packed", "toStatus": "shipped", "changedByRole": "seller", "at": "2026-09-27T23:00:00.000Z" }
  ]
}
```
- **Errors**: `403 FORBIDDEN`, `404 ORDER_NOT_FOUND`.

---

#### 2.3.2 `GET /v1/orders/{orderId}/live` (Server-Sent Events)
Stream live order status updates directly to buyer client (**R7**).
- **Headers**:
  - `Authorization: Bearer <buyer_jwt>`
  - `Accept: text/event-stream`
  - `Last-Event-ID: <event_id>` (optional on reconnect)
- **Response Stream (`200 OK`, `Content-Type: text/event-stream`)**:
```http
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

id: 1727478000000
event: status_change
data: {"orderId":"e4b6dc50-137b-4ec9-8d14-0d507127e7eb","fromStatus":"packed","toStatus":"shipped","at":"2026-09-27T23:00:00.000Z","changedByRole":"seller"}

id: 1727481600000
event: status_change
data: {"orderId":"e4b6dc50-137b-4ec9-8d14-0d507127e7eb","fromStatus":"shipped","toStatus":"delivered","at":"2026-09-28T00:00:00.000Z","changedByRole":"system"}
```

---

### Action A4: Delivery, Returns & Buyer Cancellation

#### 2.4.1 `POST /v1/orders/{orderId}/deliver`
Logistics courier confirms delivery and cash collection.
- **Headers**: `Authorization: Bearer <admin_or_courier_jwt>`
- **Response `200 OK`**: Updated order with `status: "delivered"`, `deliveredAt: "2026-09-28T14:00:00.000Z"`.
- **Errors**: `409 INVALID_TRANSITION` (status != `shipped`).

---

#### 2.4.2 `POST /v1/orders/{orderId}/return-request`
Buyer requests a return within 7 days of delivery (**R8**).
- **Headers**: `Authorization: Bearer <buyer_jwt>`
- **Request Body**:
```json
{
  "reason": "Size UK 12 did not fit as expected."
}
```
- **Response `200 OK`**: Updated order with `status: "return_requested"`.
- **Errors**:
  - `403 FORBIDDEN`: Not the buyer of this order.
  - `409 RETURN_WINDOW_CLOSED`: Invoked > 7 days after `delivered_at` or order status != `delivered`.
  - `409 INVALID_TRANSITION`: Order not in `delivered` state.

---

#### 2.4.3 `POST /v1/orders/{orderId}/cancel`
Buyer cancels unfulfilled order (**R6**). Stock is automatically restored (**R9**).
- **Headers**: `Authorization: Bearer <buyer_jwt>`
- **Request Body**:
```json
{
  "reason": "Changed my mind before dispatch."
}
```
- **Response `200 OK`**: Updated order with `status: "cancelled"`, `cancelledBy: "buyer"`, `cancelledAt: "2026-09-27T22:40:00.000Z"`.
- **Errors**:
  - `409 ALREADY_SHIPPED`: Order is in `shipped` or `delivered` state; cancellation forbidden.
  - `409 INVALID_TRANSITION`: Order already terminal (`cancelled`, `completed`, `returned`).

---

### Action A5: Verified Reviews & Product Ratings

#### 2.5.1 `POST /v1/order-items/{orderItemId}/review`
Buyer leaves a 1 to 5 star rating on a purchased item from a completed order (**R10**).
- **Headers**: `Authorization: Bearer <buyer_jwt>`
- **Request Body**:
```json
{
  "stars": 5,
  "comment": "Exceptional silk quality and fast delivery in Ikeja!"
}
```
- **Response `201 Created`**:
```json
{
  "id": "f1d45c8e-561b-4f91-a1e7-8b01c34a2e5d",
  "orderItemId": "5c9b4e18-6927-4c07-b371-70bf89be8c89",
  "productId": "7b7e8ef6-c22e-4cf4-a083-d9d300ebbc33",
  "buyerId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "stars": 5,
  "comment": "Exceptional silk quality and fast delivery in Ikeja!",
  "createdAt": "2026-09-28T18:00:00.000Z"
}
```
- **Errors**:
  - `400 BAD_REQUEST`: Stars outside 1..5 range.
  - `403 FORBIDDEN`: Buyer did not purchase this order item.
  - `409 ORDER_NOT_COMPLETED`: Parent order status != `completed` (**R10**).
  - `409 ALREADY_REVIEWED`: A review already exists for this `orderItemId`.

---

#### 2.5.2 `GET /v1/products/{productId}/reviews`
Retrieve paginated reviews for a garment.
- **Query Parameters**: `limit` (max 100), `cursor`, `stars` (1..5 filter).
- **Response `200 OK`**:
```json
{
  "data": [
    {
      "id": "f1d45c8e-561b-4f91-a1e7-8b01c34a2e5d",
      "buyerName": "Amina B.",
      "stars": 5,
      "comment": "Exceptional silk quality and fast delivery in Ikeja!",
      "createdAt": "2026-09-28T18:00:00.000Z"
    }
  ],
  "pagination": { "limit": 20, "nextCursor": null, "hasMore": false }
}
```

---

## 3. Resource Management & Administration Endpoints

### 3.1 Buyers
- `POST /v1/buyers`: Register buyer. Body: `{ fullName, email, phone, deliveryAddress }`. Returns `201 Created`.
- `GET /v1/buyers/{buyerId}`: Fetch buyer profile. Returns `200 OK`.
- `PATCH /v1/buyers/{buyerId}`: Update profile. Body: `{ fullName?, phone?, deliveryAddress? }`. Returns `200 OK`.
- `DELETE /v1/buyers/{buyerId}`: Anonymise PII (NDPA compliance) and soft-delete account. Returns `204 No Content`.

### 3.2 Sellers
- `POST /v1/sellers`: Register boutique shop. Body: `{ shopName, ownerName, email, phone }`. Returns `201 Created`.
- `GET /v1/sellers/{sellerId}`: Fetch boutique public profile. Returns `200 OK`.
- `PATCH /v1/sellers/{sellerId}`: Update details. Returns `200 OK`.
- `DELETE /v1/sellers/{sellerId}`: Soft-delete shop. Returns `204 No Content`.

### 3.3 Categories
- `POST /v1/categories`: Admin create category. Body: `{ name, slug }`. Returns `201 Created`.
- `GET /v1/categories`: List all categories with cursor pagination. Returns `200 OK`.
- `GET /v1/categories/{categoryId}`: Fetch single category. Returns `200 OK`.
- `PATCH /v1/categories/{categoryId}`: Update category name/slug. Returns `200 OK`.
- `DELETE /v1/categories/{categoryId}`: Hard delete (fails with 409 if active products linked). Returns `204 No Content`.

### 3.4 Products & Product Categories
- `POST /v1/products`: Seller create product. Body: `{ name, description, isActive }`. Returns `201 Created`.
- `PATCH /v1/products/{productId}`: Seller update product details. Returns `200 OK`.
- `DELETE /v1/products/{productId}`: Soft delete product. Returns `204 No Content`.
- `POST /v1/products/{productId}/categories`: Link product to category. Body: `{ categoryId }`. Returns `201 Created`.
- `DELETE /v1/products/{productId}/categories/{categoryId}`: Unlink category. Returns `204 No Content`.

### 3.5 Product Variants & Inventory
- `POST /v1/products/{productId}/variants`: Create variant. Body: `{ size, colour, sku, priceMinor, currency, stockQuantity }`. Returns `201 Created`.
- `PATCH /v1/products/{productId}/variants/{variantId}`: Update variant price or stock. Body: `{ priceMinor?, stockQuantityDelta? }`. Returns `200 OK`.
- `DELETE /v1/products/{productId}/variants/{variantId}`: Soft delete variant. Returns `204 No Content`.

### 3.6 Order Queries
- `GET /v1/orders`: List orders with cursor pagination, filtered by role:
  - Buyer: Returns orders placed by authenticated buyer (`placed_at DESC`, **R5**).
  - Seller: Returns orders received by seller shop (`status`, `placed_at`).
  - Query parameters: `status`, `limit` (max 100), `cursor`, `startDate`, `endDate`. Returns `200 OK`.

---

## 4. API Architectural Analysis: Over-Fetching & Technology Choice

### 4.1 Heavy REST Response vs Lightweight Client Need
When a mobile buyer browses a category grid (e.g. "Dresses"), the UI only requires:
- Product Title
- Minimum Starting Price
- Thumbnail Image URL
- Star Rating

#### Full REST Endpoint Payload (`GET /v1/products/{productId}`):
```json
{
  "id": "7b7e8ef6-c22e-4cf4-a083-d9d300ebbc33",
  "sellerId": "09f69748-0b54-46da-b7ec-aa6a4f91d09e",
  "seller": {
    "shopName": "Eko Couture",
    "ownerName": "Folake Johnson",
    "email": "contact@ekocouture.ng",
    "phone": "+2348012345678"
  },
  "name": "Lagos Floral Adire Silk Dress",
  "description": "Hand-dyed pure silk maxi dress tailored for ready-to-wear comfort. Fabric sourced directly from Abeokuta artisans. Dry clean only. Available in multiple vibrant tones.",
  "isActive": true,
  "ratingAvg": 4.85,
  "ratingCount": 24,
  "variants": [
    { "id": "6a96f1d2-0695-4674-9c4c-35a0f62eec41", "size": "S", "colour": "Indigo", "sku": "EKO-ADR-S-IND", "price": { "amountMinor": 3500000, "currency": "NGN" }, "stockQuantity": 4 },
    { "id": "6a96f1d2-0695-4674-9c4c-35a0f62eec42", "size": "M", "colour": "Indigo", "sku": "EKO-ADR-M-IND", "price": { "amountMinor": 3500000, "currency": "NGN" }, "stockQuantity": 8 },
    { "id": "6a96f1d2-0695-4674-9c4c-35a0f62eec43", "size": "L", "colour": "Indigo", "sku": "EKO-ADR-L-IND", "price": { "amountMinor": 3500000, "currency": "NGN" }, "stockQuantity": 0 },
    { "id": "6a96f1d2-0695-4674-9c4c-35a0f62eec44", "size": "XL", "colour": "Indigo", "sku": "EKO-ADR-XL-IND", "price": { "amountMinor": 3800000, "currency": "NGN" }, "stockQuantity": 2 }
  ],
  "categories": [
    { "id": "11111111-2222-3333-4444-555555555555", "name": "Dresses", "slug": "dresses" },
    { "id": "22222222-3333-4444-5555-666666666666", "name": "Silk Wear", "slug": "silk-wear" }
  ],
  "recentReviews": [
    { "id": "f1d45c8e-561b-4f91-a1e7-8b01c34a2e5d", "stars": 5, "comment": "Great fabric!" }
  ],
  "createdAt": "2026-09-20T10:00:00.000Z",
  "updatedAt": "2026-09-26T14:10:00.000Z"
}
```
*Payload size: ~1,850 bytes per item. In a 50-item grid, that equates to ~92.5 KB of over-fetched JSON data.*

#### Equivalent Targeted GraphQL Query & Response:
```graphql
query CategoryProductCard($productId: ID!) {
  product(id: $productId) {
    name
    ratingAvg
    minPrice {
      amountMinor
      currency
    }
  }
}
```
```json
{
  "data": {
    "product": {
      "name": "Lagos Floral Adire Silk Dress",
      "ratingAvg": 4.85,
      "minPrice": { "amountMinor": 3500000, "currency": "NGN" }
    }
  }
}
```
*Payload size: ~110 bytes (a 94% reduction in bandwidth consumption).*

### 4.2 Architectural Decision: REST vs GraphQL for MVP
- **Decision**: **Retain REST for WearHub MVP.**
- **Rationale**:
  1. **Operational Simplicity**: REST endpoints benefit from out-of-the-box HTTP edge caching (Cloudflare/Fastly), reverse proxy CDN integration, and zero query parsing overhead.
  2. **Security & Rate Limiting**: Standard REST route-based rate limiting (`429`) is significantly simpler to defend than complex recursive GraphQL query depth and cost calculations.
- **Triggers for Adopting GraphQL / Backend-for-Frontend (BFF)**:
  1. **Multiple Diverse Client Formats**: Launching distinct React Native iOS/Android apps and lightweight mobile web with divergent screen layouts.
  2. **High Network Latency / Cellular Constraints**: 3G/4G bandwidth constraints in Lagos where round-trip latency and payload size degrade conversion rates.
  3. **Screen Composition Complexity**: When mobile screens require stitching data from 4+ independent backend services in a single view.

---

## 5. Real-Time Communication Architecture: SSE vs WebSockets

### 5.1 Protocol Comparison

| Dimension | Server-Sent Events (SSE) | WebSockets (WS) |
| :--- | :--- | :--- |
| **Directionality** | Unidirectional (Server -> Client) | Full Duplex Bidirectional (Client <-> Server) |
| **Transport Protocol** | Standard HTTP/1.1 or HTTP/2 | Custom `ws://` / `wss://` protocol upgrade |
| **Connection Recovery** | Built-in native browser reconnect with `Last-Event-ID` | Manual application-level reconnection and replay logic |
| **Proxy / Firewall Traversal** | 100% compliant with standard corporate proxies & CDNs | Often blocked or terminated by strict enterprise middleboxes |
| **Resource Overhead** | Low; multiplexes over existing HTTP/2 TCP streams | High; dedicated persistent TCP socket state per connection |

### 5.2 Architectural Decision & Rationale
- **Decision**: **WearHub adopts Server-Sent Events (SSE) for Action A3 (Order Tracking).**
- **Rationale**:
  1. **Unidirectional Match**: Order tracking is purely push notifications (the buyer client listens to status progression; buyer commands are standard HTTP POSTs).
  2. **Resilience over Mobile Networks**: In mobile environments with frequent network drops across Lagos cellular towers, SSE's automatic client reconnect and `Last-Event-ID` header guarantee seamless message catch-up without custom frontend state logic.

### 5.3 Event Protocol Specification
```http
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
X-Accel-Buffering: no

id: 1727478000000
event: order_status
data: {"orderId":"e4b6dc50-137b-4ec9-8d14-0d507127e7eb","status":"packed","at":"2026-09-27T22:45:00.000Z"}
```

### 5.4 Secondary Real-Time Use Case: Live Low-Stock Inventory Alerts
The same SSE pipeline powers real-time stock indicators on the product detail page:
```http
id: 1727478050000
event: variant_stock_update
data: {"variantId":"6a96f1d2-0695-4674-9c4c-35a0f62eec41","remainingStock":2,"alert":"Only 2 left in stock"}
```
This gives buyers immediate urgency cues while preventing checkout collisions (**R1**, **R2**).
