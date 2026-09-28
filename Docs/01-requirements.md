# WearHub Requirements

## 1. What WearHub Does
WearHub is a ready-to-wear fashion marketplace based in Lagos, Nigeria (currency NGN). Fashion brands and boutiques (sellers) list clothes in fixed sizes and colours, while shoppers (buyers) browse inventory, place orders, track delivery in real time, and pay cash on delivery.

## 2. User Roles
- **Buyer**: Needs to browse ready-to-wear clothing in specific sizes/colours, place orders with locked prices, track fulfillment live, pay on delivery, and review completed purchases.
- **Seller**: Needs to list products with size/colour variants and stock, receive seller-specific orders, update fulfillment states (confirm, pack, ship), and process returns.
- **Admin**: Needs to oversee platform activity, manage taxonomy/categories, monitor order transitions, and maintain dispute resolution standards.

## 3. Core Actions
- **A1**: A buyer places an order for items in a chosen size and colour. Stock is reserved and prices are locked.
- **A2**: The seller confirms, packs and ships the order.
- **A3**: The buyer tracks the order live.
- **A4**: The order is delivered, then completed (or the buyer requests a return within 7 days).
- **A5**: The buyer reviews an item from a completed order.

## 4. Functional Requirements
- **R1 [A1] - Variant Stock Availability**: A buyer selects items by specific size and colour; variants with zero stock quantity cannot be ordered.
- **R2 [A1] - Concurrency & Oversell Protection**: The last item in stock is sold exactly once under concurrent order attempts using atomic conditional decrement.
- **R3 [A1] - Price & Detail Snapshots**: Unit prices, product names, sizes, and colours are locked and snapshot into the order item at checkout; future seller catalog edits do not alter existing orders.
- **R4 [A1] - Single-Seller Orders**: Each order belongs to exactly one seller; checking out items from multiple sellers splits the cart into distinct orders per seller.
- **R5 [A1, A3] - Order History**: Buyers can view their order history sorted in descending chronological order (newest first).
- **R6 [A2, A4] - Buyer Cancellation**: A buyer can cancel an order while it is in `placed`, `confirmed`, or `packed` state; cancellation is strictly forbidden once marked `shipped`.
- **R7 [A3] - Real-Time Tracking**: Buyers receive live status updates via Server-Sent Events (SSE) as orders transition across states.
- **R8 [A4] - Return Window & Auto-Completion**: After an order is `delivered`, a buyer has exactly 7 days to request a return (`return_requested`); if no return is requested within 7 days, the order automatically transitions to `completed`.
- **R9 [A2, A4] - Stock Restocking**: Cancelled orders and accepted returns (`returned`) automatically restore reserved quantities back into active variant stock.
- **R10 [A5] - Verified Purchase Reviews**: A buyer can submit exactly one review per order item (rated 1 to 5 stars) only after the parent order reaches `completed` status.

## 5. Non-Goals
- **No Online Payment Processing**: All orders use pay on delivery; the platform records monetary amounts in NGN minor units (kobo) without third-party payment gateways.
- **No Made-to-Measure Clothing**: Only fixed, pre-defined size and colour variants are supported.
- **No Native Mobile Application**: Scope is constrained to backend REST API design and PostgreSQL data modeling.
- **No In-App Chat**: No direct messaging between buyers and sellers is supported.
