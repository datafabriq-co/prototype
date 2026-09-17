# Daily Revenue/COGS/Net Dashboard — Design

Status: Approved by user, ready for implementation planning
Date: 2026-09-17

## Summary

A single-table dashboard showing revenue, COGS, and net profit per day over
the most recent 14 days present in the source data. Orders and fulfillment
data arrive as CSVs in Azure Blob Storage; an Azure Function preprocesses
them on upload and caches the result in Redis; a second Azure Function
serves it over HTTP; a React/Vite client renders the table. Hosted entirely
on Azure.

## Source data

- `orders.csv`: `order_date, order_id, item, quantity, item_price`. Multiple
  rows per `order_id` (one per line item). ~1193 rows, 2026-07-01 to
  2026-08-30 in the current sample.
- `fulfillment.csv`: `fulfillment_date, order_id, shipping_cost`. One row
  per fulfilled order, joined to orders by `order_id`. Fewer rows than
  distinct orders (not every order has shipped yet). ~601 rows in the
  current sample.
- No per-item cost field exists anywhere in the data.

## Data model & preprocessing

**COGS definition:** COGS = `shipping_cost` from `fulfillment.csv`. There is
no other cost data available; this was an explicit scope decision (not a
margin estimate or per-item cost table).

**Join & aggregation, per Function invocation:**

1. Parse `orders.csv`; group line items by `order_id`. Per order:
   `revenue = Σ(item_price × quantity)` across its line items, and one
   `order_date`.
2. Parse `fulfillment.csv`; build a map `order_id → shipping_cost`.
3. Per order: `cogs = fulfillment_map[order_id] ?? 0`. Orders not yet
   fulfilled contribute $0 COGS (not excluded, not estimated) — COGS is
   attributed back to the order's `order_date`, not the fulfillment date,
   so a day's Net reflects orders placed that day regardless of when (or
   whether) they've since shipped.
4. Bucket orders into their `order_date`'s calendar day (UTC date portion
   of the ISO 8601 timestamp, e.g. `2026-07-01T02:05:46Z` → `2026-07-01`).
5. Per day: `revenue = Σ order revenue`, `cogs = Σ order cogs`,
   `net = revenue - cogs`. Round all three to 2 decimal places.
6. Select the most recent 14 distinct calendar days present in
   `orders.csv`. A day with zero orders still appears, with all values 0.

**Output** — a single JSON object, 14 keys, ISO date strings ascending,
each value `{ revenue, cogs, net }`:

```json
{
  "2026-08-17": { "revenue": 1234.56, "cogs": 88.10, "net": 1146.46 },
  "2026-08-18": { "revenue": 980.00, "cogs": 45.00, "net": 935.00 }
}
```

This object is exactly what's cached in Redis and exactly what the API
returns — no further transformation happens between preprocessing and the
client.

**Malformed rows:** a line item or fulfillment row that fails to parse
(missing field, non-numeric price/quantity/cost) is skipped and logged;
it does not fail the whole run. This only needs to be defensive, not
configurable — the sample data is clean.

## Architecture (Azure)

```
 [Blob Storage container]
   orders.csv, fulfillment.csv
        │  blob created/updated
        ▼
 [Function App]
   ├─ Preprocessor (Blob Trigger, Node/TS)
   │    reads BOTH current blobs on every trigger (either file changing
   │    invalidates the join), runs the aggregation above, writes the
   │    resulting JSON to Redis under a fixed key `metrics:last14`
   │
   └─ API (HTTP Trigger, Node/TS)
        GET /api/metrics → reads `metrics:last14` from Redis, returns it
        as-is. 503 if the key doesn't exist yet (nothing processed since
        deploy / fresh environment).
        │
        ▼
 [Azure Cache for Redis — Basic tier]
   single key, small JSON value — the shared store between the two
   Functions (Function instances don't share process memory, so Redis is
   the "in-memory storage" layer, not either Function's own heap)

 [Azure Static Web Apps]
   hosts the built Vite/React client, calls GET /api/metrics
   (via SWA's managed API proxy if the Function App is linked as its
   backend, otherwise via CORS — finalized during implementation)
```

Both Functions live in one Function App (one deployable) on a Consumption
or Flex Consumption plan.

**Why Redis over cheaper alternatives:** a Table Storage handoff would be
near-free, but Redis was chosen for cleaner separation between the
write path (preprocessor) and read path (API) and sub-millisecond reads.
Cost note: Azure Cache for Redis has no free tier — Basic tier starts
around $15-16/month for the smallest instance.

## API contract

`GET /api/metrics`
- `200 OK` — body is the 14-key date object described above.
- `503 Service Unavailable` — body `{ "error": "metrics not yet available" }`
  when Redis has no cached result yet.
- No authentication (prototype scope; can be added later via Static Web
  Apps auth or Function-level keys without changing the data model).

## Client (React + Vite + TypeScript)

- Single page, single component. Fetches `GET /api/metrics` on mount.
- Renders one table: columns Date, Revenue, COGS, Net; one row per date
  key, ascending; currency formatted (e.g. `$1,234.56`).
- Loading state while the fetch is in flight; error state if the fetch
  fails or returns 503.
- No totals row, no charts, no filters, no date picker — scope is
  exactly the 14-row table.

## Hosting summary

| Component | Azure resource |
|---|---|
| CSV source | Blob Storage account + container |
| Preprocessing trigger | Function App — Blob Trigger |
| API | Function App — HTTP Trigger (same Function App) |
| Shared store | Azure Cache for Redis (Basic) |
| Client | Azure Static Web Apps |

The implementation plan will include the concrete provisioning steps
(resource group, storage account/container, Function App, Redis instance,
Static Web App + GitHub Actions deploy workflow) since this is the user's
first time setting up this kind of hosting.

## Testing

- Unit tests for the join/aggregation logic (Section "Data model &
  preprocessing") against small fixture CSVs — this is the only real
  business logic in the system and should be covered directly, independent
  of Azure Functions or Redis.
- A test covering the "order with no matching fulfillment row" case
  (COGS = 0) and the "day with zero orders" case (all zeros), since both
  are easy to get wrong silently.
- Client: a basic render test with a mocked fetch response (loading →
  table; error state).
- No integration tests against live Azure resources planned for this
  scope; local testing uses the Azurite emulator for Blob Storage where
  needed.
