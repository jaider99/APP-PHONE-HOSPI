# Product Detail Redesign and AI Reasoning Analysis

## 1. Current Product Detail Widget Tree

Current owner: `lib/features/products/presentation/screens/product_detail_screen.dart`.

The current screen is a `ConsumerWidget` that watches product detail, price history, aliases, supplier breakdown, product insights, price stats, all anomalies, and open anomalies. It renders a bare `Scaffold` with `CustomScrollView` slivers:

1. `SliverAppBar` with `_BackButton` and `_ProductHeroImage`.
2. `_ProductInfoSection` with category tag, product name, description, and `_MetaChip` metadata.
3. `_InsightsSection` with another `Wrap` of `_MetaChip` metrics.
4. `_PriceHealthSection` for cached stats or open anomaly summary.
5. `_SupplierBreakdownSection` using bordered container, `ListView.separated`, `Divider`, and `ListTile` trailing columns.
6. `_AliasesSection` with bordered pills.
7. `_PriceHistorySection` using `fl_chart` over `product_prices`.
8. `_AnomalyTimelineSection` with anomaly actions.
9. `_RecentPurchasesSection` using recent price observations.

Root UI problems:

- `_ProductHeroImage` depends on `product.imageUrl` / generated image URLs.
- `_MetaChip` hardcodes `width: 160` and internal `SizedBox` width math, which can overflow on narrow screens.
- Supplier and purchase lists rely on row/trailing layouts that are fragile with long supplier names or large amounts.
- The visual language uses borders/dividers and debug-style labels instead of Digital Atelier tonal surfaces.
- Loading is a full-screen spinner, not skeleton content.

## 2. Current Product Detail Route

Route owner: `lib/core/router/app_router.dart`.

- `AppRoutes.productDetail = '/products/:id'`.
- Product detail is outside the shell and uses `parentNavigatorKey: rootNavigatorKey`.
- The route extracts `state.pathParameters['id']` and returns `ProductDetailScreen(productId: id)`.
- Product list cards navigate with `context.push('/products/${summary.id}')`.

The route should be preserved. Back navigation should continue to use GoRouter/Navigator pop behavior and return to the Products catalogue.

## 3. Current Product Provider/Repository

Provider owner: `lib/features/products/providers/product_providers.dart`.

Repository owner: `lib/features/products/data/repositories/product_repository.dart`.

Current product detail providers:

- `productDetailProvider(productId)` -> `repo.fetchProductById(productId, companyId)`.
- `productPriceHistoryProvider(productId)` -> `repo.fetchPriceHistory(productId, companyId)`.
- `productAliasesProvider(productId)` -> `repo.fetchAliases(productId, companyId)`.
- `productSupplierBreakdownProvider(productId)` -> `repo.buildSupplierBreakdown(productId, companyId)`.
- `productInsightsProvider(productId)` -> `repo.buildInsights(productId, companyId)`.
- `productPriceStatsProvider(productId)` -> `repo.fetchPriceStats(productId, companyId)`.
- `productPriceAnomaliesProvider(productId)` -> `repo.fetchPriceAnomalies(productId, companyId)`.
- `openProductPriceAnomaliesProvider(productId)` -> unresolved anomalies only.
- `_productsRealtimeProvider` watches tenant-filtered `products`, `product_prices`, `document_items`, `price_anomalies`, and `product_price_stats` changes.

Tenant safety is already present through `companyIdProvider` plus explicit `.eq('company_id', companyId)` repository filters. This must not be weakened.

## 4. Current Supabase Tables Used by Product Detail

Current direct product detail reads use:

- `products`
- `categories` through `products.category_id -> categories(name)`
- `product_prices`
- `providers` joined from `product_prices.supplier_id -> providers(name)`
- `product_aliases`
- `product_price_stats`
- `price_anomalies`

Existing schema confirms:

- Canonical supplier table is `providers`, not `suppliers`.
- Canonical line-item table is `document_items`, not `document_line_items`.
- `documents` holds document number/date/total/provider metadata.
- `product_prices` links price observations back to `document_id`, `document_item_id`, `supplier_id`, `date`, and `observed_at`.

## 5. Current Metrics Available

Available from existing real data:

- Current stock: `products.current_stock`.
- Latest price: `ProductInsightsModel.latestPrice`, `product_price_stats.last_price`, or latest `product_prices.price`.
- Average price: `ProductInsightsModel.averagePrice`, `product_price_stats.avg_price`, or computed from `product_prices`.
- Purchase count: `ProductInsightsModel.purchaseCount`, `product_price_stats.sample_count`, or `product_prices.length`.
- Suppliers count: `ProductInsightsModel.supplierCount`, `product_price_stats.supplier_count`, or grouped `product_prices.supplier_id`.
- Last change: `ProductInsightsModel.changePercentFromPrevious` or deterministic comparison of latest and previous `product_prices` rows.
- Category: `ProductModel.displayCategory` from `categories(name)` or legacy `products.category`.
- Unit: `products.unit_type` and `product_prices.unit`.
- Aliases: `product_aliases.raw_name`.
- Linked documents: currently not exposed by the UI, but real links exist through `product_prices.document_id` and `document_items.document_id`.

## 6. Which Values Are Real and Which Are Missing

Real now:

- Product name, category, description, unit, current stock, min stock, unit price.
- Price history observations from `product_prices`.
- Supplier names via `providers` joins.
- Alias names from `product_aliases`.
- Cached stats from `product_price_stats` when present.
- Deterministic anomaly and AI explanation fields from `price_anomalies` when present.

Missing or partial in current UI:

- Linked Documents section is not implemented even though `document_id` exists in `product_prices`.
- Previous price and 30d/90d averages are partly computed for list summaries but not cleanly surfaced on detail.
- Best/worst supplier price are derived visually in supplier breakdown but not modeled as a dedicated detail metric.
- AI reasoning is present only indirectly through anomaly `ai_explanation`; there is no separate product-level reasoning Edge Function/cache.
- Stock is real only if inventory is tracked/populated. It must not be treated as a forecast.

## 7. Current Source of Price History

`ProductRepository.fetchPriceHistory(productId, companyId)` reads `product_prices` with:

- `id`
- `company_id`
- `product_id`
- `document_id`
- `document_item_id`
- `supplier_id`
- `providers(name)`
- `price`
- `quantity`
- `unit`
- `date`
- `observed_at`

Rows are scoped by `product_id` and `company_id`, ordered by `observed_at` descending, and capped by limit.

## 8. Current Source of Supplier Breakdown

`ProductRepository.buildSupplierBreakdown(productId, companyId)` calls `fetchPriceHistory(limit: 200)`, groups rows by `supplierId ?? 'unknown'`, and computes:

- supplier name
- purchase count
- average price
- latest price
- last purchased date

This is real data derived from `product_prices` and `providers` joins. It is not mock data.

## 9. Whether Price Anomalies Exist

Yes, schema and Flutter models exist.

- Table: `price_anomalies`.
- It stores deterministic anomaly events, current/expected price, deviation percent, severity, confidence, heuristic details, and AI explanation/confidence.
- Product providers already expose all anomalies and open anomalies.
- The current UI can show a price health card and anomaly timeline.

Whether a specific product has anomaly rows depends on real tenant data; the screen must handle zero rows cleanly.

## 10. Whether AI Reasoning Already Exists

Partially.

- `recognize-products` uses OpenRouter server-side for product normalization and anomaly explanation refinement.
- `price_anomalies.ai_explanation` and `price_anomalies.ai_confidence` already exist.
- `ProductRepository._buildProductSummary` currently prefers `anomaly.aiExplanation`, then deterministic anomaly explanation, then local deterministic reasoning.
- There is no dedicated product detail Edge Function named `analyze-product-price-reasoning` today.

The immediate safe implementation should surface existing AI/anomaly explanation when available and deterministic reasoning otherwise. A new Edge Function is optional and should be added only if product-level non-anomaly prose must be generated and cached server-side.

## 11. Best Way to Integrate AI Reasoning Safely

Safe staged approach:

1. Deterministic first in repository/model code using tenant-scoped `product_prices` and `product_price_stats`.
2. If an open or recent anomaly exists, display `ai_explanation` when present.
3. If no AI explanation exists, display deterministic reasoning from price variation, supplier changes, and history size.
4. Keep Flutter free of OpenRouter URLs and API keys.
5. If product-level AI prose is later required, add a Supabase Edge Function such as `analyze-product-price-reasoning`:
   - Authenticate the user.
   - Fetch product through RLS/user client.
   - Derive `company_id` from the product row.
   - Fetch only tenant-scoped `product_prices`, `providers`, `documents`, and anomalies.
   - Send a compact summary to OpenRouter server-side.
   - Return `{ summary, severity, possible_causes, recommended_action }`.
   - Cache in existing `price_anomalies` only when tied to an anomaly, or add a minimal cache table only if analysis proves existing tables cannot represent product-level insight.

Do not send signed URLs, document binaries, raw OCR, full invoices, or cross-tenant data to OpenRouter.

## 12. UI Redesign Plan

Redesign only Product Detail into a Digital Atelier intelligence page:

1. Replace generated/network hero image with a tonal identity card using initials/iconography.
2. Use `SafeArea`, `LayoutBuilder`, and `SingleChildScrollView` or slivers with responsive width constraints.
3. Top area: pill back button, category label, health pill, product name max two lines.
4. Hero identity card: product symbol/initials, category, unit, latest price, status.
5. Core metrics: responsive bento cards for stock, latest price, average price, purchases, suppliers, last change.
6. Price Intelligence card: latest, previous, average 30d/90d, variation vs previous/average, benchmark pill, and a simple chart only when real price history exists.
7. AI Reasoning card: `What Changed?` with AI anomaly explanation if available, deterministic fallback otherwise, and graceful loading/error/insufficient-data states.
8. Supplier Breakdown: clean stacked supplier cards with name, purchase count, last purchase, average/latest price, best price label.
9. Linked Documents: real linked documents from `product_prices.document_id` / `documents`; tap opens existing document detail route/sheet.
10. Known Aliases: tonal pills.
11. Operational actions: preserve existing anomaly resolve/ignore/approve actions if anomalies are present; do not invent manual stock actions.

Responsive rules:

- 320px: single-column metrics.
- 360/390/430px: two-column bento only when computed item width remains safe.
- Tablet: centered content max-width, wider two-column/section cards.
- No fixed card widths that exceed available constraints.
- Long names use `maxLines` and ellipsis; amounts use `FittedBox` or constrained text.

## 13. Files to Modify

Likely implementation files:

- `lib/features/products/presentation/screens/product_detail_screen.dart`
- `lib/features/products/data/repositories/product_repository.dart`
- `lib/features/products/providers/product_providers.dart`

Potential model file if linked documents need a typed model:

- `lib/features/products/data/models/product_linked_document_model.dart`

Potential future server-side AI function only if required after deterministic/anomaly-backed UI:

- `supabase/functions/analyze-product-price-reasoning/index.ts`

For this pass, prefer existing `price_anomalies.ai_explanation` plus deterministic fallback before adding a new Edge Function or migration.

## 14. Files to Leave Untouched

Do not touch unless a direct compile dependency proves otherwise:

- `supabase/functions/process-document/index.ts`
- `supabase/functions/recognize-products/index.ts`
- `supabase/functions/classify-expense/index.ts`
- `supabase/functions/classify-document-type/index.ts`
- PDF extraction/rendering/upload code
- document upload providers/services
- VLM extraction logic
- product matching semantics
- RLS policies broadly
- storage policies
- auth code
- dashboard, FAB, and bottom navigation
- document detail screen internals
- supplier detail screen unless adding an existing-route navigation affordance requires it

## 15. Validation Checklist

After implementation:

1. Product Detail opens from Products list.
2. No RenderFlex overflow at 320, 360, 390, 430, and tablet widths.
3. Product name and category display from real product data.
4. Latest price displays from real `product_prices`/stats data.
5. Average price displays from real history/stats data.
6. Supplier count is real.
7. Purchase count is real.
8. Last change is calculated from real price history.
9. Supplier Breakdown uses real `providers` data.
10. Linked Documents use real `documents` rows and open existing document detail.
11. AI reasoning does not block the screen.
12. If AI/anomaly explanation is absent, deterministic fallback works.
13. No generated product image is displayed.
14. No fake chart data is shown.
15. No fake stock or forecast data is shown.
16. Product queries remain scoped by active `company_id`.
17. Company switch invalidates/refetches via existing company-aware providers/realtime.
18. VLM extraction remains untouched.
19. Product matching remains untouched.
20. Products screen still works.
