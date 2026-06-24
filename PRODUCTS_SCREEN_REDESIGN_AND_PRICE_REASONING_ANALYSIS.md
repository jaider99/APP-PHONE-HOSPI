# Products Screen Redesign and Price Reasoning Analysis

## 1. Current Products Screen Widget Tree

Current file: `lib/features/products/presentation/screens/product_list_screen.dart`.

Current tree, simplified:

- `ProductListScreen extends ConsumerStatefulWidget`
  - `_ProductListScreenState`
    - watches `productsProvider`
    - watches `productCategoriesProvider`
    - watches `productCategoryFilterProvider`
    - debounces search into `productSearchQueryProvider`
  - `AppScaffold`
    - `AppTopBar(eyebrow: 'catalogue', title: 'Products')`
    - `Column`
      - `_SearchBar`
        - `TextField`
        - clear icon
      - `_CategoryChips`
        - horizontal `ListView`
        - shared `CategoryChip`
      - `Expanded`
        - `productsAsync.when(...)`
          - loading: `_LoadingGrid`
          - error: `ErrorState`
          - empty: `AppEmptyState`
          - data:
            - `_CatalogueStats`
            - `_ProductGrid`
              - `GridView.builder`
              - two columns
              - `_ProductCard`
                - `Material`
                - `InkWell` to `/products/${product.id}`
                - `Container` with hard hairline border
                - image area using `product.imageUrl`
                - `CachedNetworkImage` or `_ImagePlaceholder`
                - product category/name/unit price

Current visual issue: the screen behaves like an ecommerce/product-photo catalogue. The two-column generated-image grid adds visual noise, makes product identity inconsistent, and does not emphasize procurement intelligence.

## 2. Current Product Provider/Repository Structure

Current provider file: `lib/features/products/providers/product_providers.dart`.

Providers:

- `productRepositoryProvider`: creates `ProductRepository(SupabaseService.client)`.
- `productSearchQueryProvider`: local search text state.
- `productCategoryFilterProvider`: local category filter string.
- `_productsRealtimeProvider`: subscribes by `company_id` to:
  - `products`
  - `product_prices`
  - `document_items`
  - `price_anomalies`
  - `product_price_stats`
- `productsProvider`: fetches active products for current company using `companyIdProvider`, search, and category.
- `productDetailProvider`: fetches one product by id and company.
- `productPriceHistoryProvider`: reads `product_prices` for product detail/history.
- `productAliasesProvider`: reads `product_aliases`.
- `productSupplierBreakdownProvider`: builds supplier breakdown from price history.
- `productInsightsProvider`: computes simple price insight client-side from price history.
- `productPriceStatsProvider`: reads `product_price_stats`.
- `productPriceAnomaliesProvider` / `openProductPriceAnomaliesProvider`: reads `price_anomalies`.
- `priceAnomalyActionsProvider`: resolves anomalies through step-up auth and RPC.
- `productCategoriesProvider`: reads distinct categories currently used by products.

Repository file: `lib/features/products/data/repositories/product_repository.dart`.

Current list query:

- table: `products`
- filters:
  - `.eq('company_id', companyId)`
  - `.eq('is_active', true)`
  - optional `ilike('name', search)`
- selected fields include `image_url`.
- category filtering happens after fetch in Dart via `product.displayCategory == category`.

Important gap: current search only uses product `name`, not normalized name, category, or supplier/provider. Current category filtering is client-side on already tenant-scoped rows, but can be improved while preserving tenant scope.

## 3. Current Supabase Tables Used by Products Screen

Current Flutter product area uses or is prepared to use:

- `products`
- `categories`
- `product_prices`
- `product_aliases`
- `providers` through joins from `product_prices`
- `product_price_stats`
- `price_anomalies`
- `document_items` only for realtime invalidation; detail price data comes from `product_prices`

Live tenant evidence for `company_id=e70aabbf-679d-4270-aaf6-bb8a8c25babe`:

- `products`: 52 rows
- `product_prices`: 45 rows
- `product_price_stats`: 9 rows
- `price_anomalies`: 0 rows

The price observation bridge is now populated and usable for real price variation signals.

## 4. Current Generated Image Logic

Flutter UI image usage:

- `product_list_screen.dart`
  - imports `cached_network_image`
  - `_ProductCard` renders `CachedNetworkImage(imageUrl: product.imageUrl!)`
  - `_ImagePlaceholder` appears when no image URL exists
- `product_detail_screen.dart`
  - imports `cached_network_image`
  - `SliverAppBar` renders `_ProductHeroImage(imageUrl: product.imageUrl)`
  - `_ProductHeroImage` renders `CachedNetworkImage` when `imageUrl` exists
- `lib/features/dashboard/presentation/widgets/intelligence_section.dart`
  - also renders `product.imageUrl` for dashboard top products, but dashboard is explicitly out of scope for this task.

Product model/repository image fields:

- `ProductModel.imageUrl` maps `products.image_url`.
- `ProductRepository.fetchProducts` and `fetchProductById` select `image_url`.

## 5. Where Generative AI Image Calls Happen

Backend image generation is in `supabase/functions/recognize-products/index.ts`:

- function: `generateAndStoreProductImage(...)`
- provider: Pollinations image endpoint, not OpenRouter image generation
- prompt: `studio product photo of ${productName}, clean white background, professional lighting, sharp detail, no text`
- uploads to Supabase Storage bucket `products`
- storage path: `${companyId}/${productId}.jpg`
- writes public URL into `products.image_url`
- called in the image generation section after new product creation, around the `newProductIds` flow.

This is backend-connected and automatic for newly created products. It is not only a UI concern.

## 6. Whether Image Generation Is UI-Only or Backend-Connected

It is backend-connected.

The Products list currently only consumes `products.image_url`; it does not call image generation. However, `recognize-products` automatically generates and stores product images for new products. Therefore:

- Removing the image grid from Products UI is safe and does not affect extraction or product matching.
- Existing historical `products.image_url` values should not be deleted unless explicitly requested.
- Disabling future generation would require touching `recognize-products`, which the user listed under files to leave untouched unless directly proven necessary. The safe first implementation is to stop using generated images in Products UI and document the backend generator as deprecated/unused by this screen.

## 7. Files Can Safely Be Removed/Disabled

Safe to modify for this task:

- `lib/features/products/presentation/screens/product_list_screen.dart`
  - replace grid with vertical Digital Atelier product intelligence list
  - remove `CachedNetworkImage` use from this screen
  - replace image area with initials avatar
  - add search/filter UI and deterministic price variation display
- `lib/features/products/data/repositories/product_repository.dart`
  - add list query for product intelligence summaries
  - keep `company_id` filters
  - join real `product_prices`, `providers`, `categories`, `product_price_stats`, `price_anomalies` if needed
- `lib/features/products/providers/product_providers.dart`
  - add filter state for price changes / needs review
  - add provider for product intelligence summaries if preferable
- `lib/features/products/data/models/*`
  - add a dedicated immutable summary model for list cards if needed
- `lib/features/products/presentation/screens/product_detail_screen.dart`
  - optional, only to remove generated hero image usage from product detail when entered from Products

Do not delete yet:

- `products.image_url` column
- existing storage files
- `generateAndStoreProductImage` inside `recognize-products`

The backend image generator can be documented as deprecated for Products UI. Fully disabling it would touch product matching Edge Function and is not necessary for a screen redesign.

## 8. Current Product Price Data Flow

Current backend flow:

1. `process-document` extracts document and line items.
2. `recognize-products` matches/creates products and links `document_items.product_id`.
3. `recognize-products` upserts `product_prices` with:
   - `company_id`
   - `product_id`
   - `document_id`
   - `document_item_id`
   - `supplier_id`
   - `price`
   - `quantity`
   - `unit`
   - `date`
   - `observed_at`
4. `refresh_product_price_stats(company_id, product_id)` maintains `product_price_stats`.
5. `price_anomalies` can store deterministic anomaly events and AI explanation metadata.

Current Flutter flow:

- Product list reads `products.unit_price`, not rich price history.
- Product detail reads `product_prices`, `product_price_stats`, and `price_anomalies`.
- `ProductRepository.buildInsights` deterministically computes latest/previous/min/max/average from `product_prices` for one product.

## 9. Whether `product_prices` Exists and Is Populated

Yes.

Live DB evidence for the active tenant:

- `product_prices`: 45 rows
- covers 6 documents and 35 products from previous validation
- latest date: 2026-05-29

This means the redesigned Products list can use real price history and should not invent trends.

## 10. Whether Price Anomalies or Product Price Stats Exist

Yes, schema and models exist.

- `product_price_stats` exists and currently has 9 rows for the active tenant.
- `price_anomalies` exists and currently has 0 rows for the active tenant.
- `PriceAnomalyModel` includes both deterministic explanation fields and AI fields:
  - `explanation`
  - `heuristic_details`
  - `ai_confidence`
  - `ai_explanation`
- `ProductPriceStatsModel` includes:
  - `last_price`
  - `avg_price`
  - `thirty_day_avg`
  - `prior_thirty_day_avg`
  - `trend_percent`
  - min/max/stddev/median/baseline data

Best immediate approach: use deterministic list-level calculation from `product_prices` and/or `product_price_stats`, and surface existing anomaly/AI explanation fields when present. Do not add a new table unless the UI needs cached server-side prose that existing `price_anomalies.ai_explanation` cannot cover.

## 11. Best Way to Implement AI Reasoning for Price Variations

Recommended staged approach:

1. Deterministic first in Flutter/data repository:
   - latest price
   - previous price
   - average 30d
   - average 90d
   - variation vs previous
   - variation vs average
   - direction: up/down/stable
   - severity: stable/watch/high/critical
   - supplier/provider context
2. Use existing `price_anomalies` fields when available:
   - show `ai_explanation` if present
   - otherwise show deterministic `explanation` / heuristic summary
3. Do not call OpenRouter from Flutter.
4. If later needed, add a server-side Edge Function such as `analyze-product-price-variation`:
   - authenticated user request
   - verify access through RLS/user context first
   - derive `company_id` from DB, not user input
   - fetch only that product's tenant-scoped price history
   - call OpenRouter text model server-side
   - cache in existing `price_anomalies` if tied to an anomaly, or in a minimal new `product_price_insights` table if product-level non-anomaly prose is needed

For this implementation, avoid a new Edge Function unless there is a proven existing UI requirement for generated prose. The screen can show real deterministic reasoning without blocking and without introducing key-handling risk.

## 12. UI Redesign Plan

Digital Atelier direction:

- Replace product grid with a vertical stock/intelligence list.
- Header copy:
  - eyebrow: `stock`
  - title: `Products`
  - subtitle: `Price intelligence & stock signals`
- Search:
  - pill-shaped, white tonal surface, no hard border
  - placeholder: `Search products...`
  - connected to real search state/provider
- Filters:
  - `All`
  - real category filters from current categories, with priority display for `Drinks`, `Raw Materials`, `Cleaning`, `Consumables`
  - `Price changes`
  - `Needs review`
  - optionally `Uncategorized`
- Product card:
  - large 96-120px white rounded card, radius 32px
  - no product photo
  - left circular initials avatar on soft gray surface
  - center name, category, supplier/last purchase context
  - right latest price and trend
  - badge for `Stable`, `Watch`, `High`, `Critical`, `Needs review`, `No price yet`
- Loading:
  - skeleton list cards, no full-screen spinner
- Empty:
  - `No products yet`
  - `Upload an invoice and HospiDash will build your product catalogue.`
- Error:
  - `Products unavailable`
  - retry action

Motion:

- subtle fade-up for header/search/filters/list
- 180-280ms easeOutCubic
- card press scale 0.97 unless `MediaQuery.disableAnimations` is true

## 13. Files to Modify

Expected minimal files:

- `lib/features/products/presentation/screens/product_list_screen.dart`
  - primary redesign
  - remove `cached_network_image` import
  - remove image grid/card UI
  - add list cards, initials avatar, trend badges, skeleton list
- `lib/features/products/providers/product_providers.dart`
  - add stock/intelligence filter state if needed
  - add product intelligence list provider if repository returns richer model
- `lib/features/products/data/repositories/product_repository.dart`
  - add tenant-scoped product intelligence summary query/calculation
  - improve search to include normalized name/category/supplier if practical without broad tenant fetch
- `lib/features/products/data/models/product_intelligence_summary_model.dart` or similar
  - immutable list summary model containing product, latest/previous price, averages, supplier, direction, severity, and anomaly state
- `lib/features/products/presentation/screens/product_detail_screen.dart`
  - optional image removal from detail hero if needed to fully prevent generated product images in Products flow

## 14. Files to Leave Untouched

Do not modify in this task:

- `supabase/functions/process-document/index.ts`
- `supabase/functions/recognize-products/index.ts` unless the user explicitly asks to disable backend generation globally
- `supabase/functions/classify-expense/index.ts`
- document upload/extraction/PDF rendering files
- document detail/document insertion pipeline
- product matching services/logic
- supplier/provider matching logic
- Supabase RLS policies
- Storage policies
- Auth
- Dashboard
- FAB
- Bottom navigation logic
- Orders
- Sales

## 15. Validation Checklist

After implementation:

1. Products screen loads real products from Supabase.
2. No generated product images are shown on the Products list.
3. Product cards show initials avatars.
4. Search still uses real product data and tenant scope.
5. Category filters work with existing categories.
6. `Price changes` filter uses real price variation.
7. `Needs review` filter uses real anomalies/review state when available.
8. Product detail navigation still works.
9. Latest price displays from `product_prices`/`product_price_stats`, not mock data.
10. Previous price and variation are calculated only from real price history.
11. No OpenRouter call is made from Flutter.
12. OpenRouter keys remain server-side only.
13. VLM extraction is untouched.
14. Product matching is untouched.
15. Existing extracted products still appear.
16. No duplicate products are created.
17. All product queries include/derive `company_id`.
18. Realtime invalidates on product/price/anomaly changes.
19. Reduced motion disables scale/stagger behavior.
20. UI follows Digital Atelier: soft monochrome, generous spacing, large radii, tonal layering, no ecommerce grid.
21. `flutter analyze` passes for touched Dart files.
