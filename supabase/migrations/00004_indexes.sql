-- ============================================================================
-- HOSPIDASH: Indexes for Performance Optimization
-- Version: 1.0.0
-- ============================================================================
-- CRITICAL: All company_id columns must be indexed for RLS performance
-- Following Supabase best practices for multi-tenant apps
-- ============================================================================

-- ============================================================================
-- PART 1: PRIMARY FOREIGN KEY INDEXES
-- ============================================================================
-- PostgreSQL does NOT auto-index foreign keys - we must do it manually!

-- Company Users
CREATE INDEX IF NOT EXISTS idx_company_users_company_id ON company_users(company_id);
CREATE INDEX IF NOT EXISTS idx_company_users_user_id ON company_users(user_id);
CREATE INDEX IF NOT EXISTS idx_company_users_company_user ON company_users(company_id, user_id);

-- Profiles
CREATE INDEX IF NOT EXISTS idx_profiles_current_company ON profiles(current_company_id);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);

-- Providers
CREATE INDEX IF NOT EXISTS idx_providers_company_id ON providers(company_id);
CREATE INDEX IF NOT EXISTS idx_providers_company_name ON providers(company_id, name);
CREATE INDEX IF NOT EXISTS idx_providers_company_normalized ON providers(company_id, name_normalized);
CREATE INDEX IF NOT EXISTS idx_providers_tax_id ON providers(company_id, tax_id) WHERE tax_id IS NOT NULL;

-- Products
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_provider ON products(provider_id);
CREATE INDEX IF NOT EXISTS idx_products_company_provider ON products(company_id, provider_id);
CREATE INDEX IF NOT EXISTS idx_products_company_category ON products(company_id, category);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(company_id, sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(company_id, barcode) WHERE barcode IS NOT NULL;

-- Documents
CREATE INDEX IF NOT EXISTS idx_documents_company_id ON documents(company_id);
CREATE INDEX IF NOT EXISTS idx_documents_provider ON documents(provider_id);
CREATE INDEX IF NOT EXISTS idx_documents_company_provider ON documents(company_id, provider_id);
CREATE INDEX IF NOT EXISTS idx_documents_company_date ON documents(company_id, document_date DESC);
CREATE INDEX IF NOT EXISTS idx_documents_company_type ON documents(company_id, document_type);
CREATE INDEX IF NOT EXISTS idx_documents_payment_status ON documents(company_id, payment_status);
CREATE INDEX IF NOT EXISTS idx_documents_ocr_status ON documents(company_id, ocr_status);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(company_id, created_at DESC);

-- Document Items
CREATE INDEX IF NOT EXISTS idx_document_items_document ON document_items(document_id);
CREATE INDEX IF NOT EXISTS idx_document_items_company ON document_items(company_id);
CREATE INDEX IF NOT EXISTS idx_document_items_product ON document_items(product_id);

-- Orders
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_provider ON orders(provider_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_provider ON orders(company_id, provider_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_status ON orders(company_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_company_date ON orders(company_id, order_date DESC);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(company_id, created_at DESC);

-- Order Items
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_company ON order_items(company_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

-- Sales
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_date ON sales(company_id, sale_date DESC);
-- Note: For monthly aggregation, use the idx_sales_company_date index with date filtering in queries

-- Activity Logs
CREATE INDEX IF NOT EXISTS idx_activity_logs_company ON activity_logs(company_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_user ON activity_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_entity ON activity_logs(company_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_created ON activity_logs(company_id, created_at DESC);

-- ============================================================================
-- PART 2: PARTIAL INDEXES (For Filtered Queries)
-- ============================================================================

-- Active providers only
CREATE INDEX IF NOT EXISTS idx_providers_active 
    ON providers(company_id, name)
    WHERE is_active = TRUE;

-- Active products only
CREATE INDEX IF NOT EXISTS idx_products_active 
    ON products(company_id, name)
    WHERE is_active = TRUE;

-- Pending documents
CREATE INDEX IF NOT EXISTS idx_documents_pending 
    ON documents(company_id, created_at DESC)
    WHERE payment_status = 'pending';

-- Documents pending payment (filter by due_date at query time for overdue check)
CREATE INDEX IF NOT EXISTS idx_documents_pending_due 
    ON documents(company_id, due_date)
    WHERE payment_status = 'pending';

-- Pending OCR processing
CREATE INDEX IF NOT EXISTS idx_documents_ocr_pending 
    ON documents(created_at)
    WHERE ocr_status IN ('pending', 'processing');

-- Active orders (not delivered/cancelled)
CREATE INDEX IF NOT EXISTS idx_orders_active 
    ON orders(company_id, order_date DESC)
    WHERE status NOT IN ('delivered', 'cancelled');

-- ============================================================================
-- PART 3: TEXT SEARCH INDEXES (For Fuzzy Matching)
-- ============================================================================

-- GIN index for provider name search
CREATE INDEX IF NOT EXISTS idx_providers_name_trgm 
    ON providers USING gin (name gin_trgm_ops);

-- GIN index for product name search
CREATE INDEX IF NOT EXISTS idx_products_name_trgm 
    ON products USING gin (name gin_trgm_ops);

-- GIN index for document text search (OCR extracted text)
CREATE INDEX IF NOT EXISTS idx_documents_ocr_data 
    ON documents USING gin (ocr_raw_data);

-- ============================================================================
-- PART 4: COMPOSITE INDEXES FOR COMMON QUERIES
-- ============================================================================

-- Dashboard: Recent documents by company
CREATE INDEX IF NOT EXISTS idx_dashboard_documents 
    ON documents(company_id, created_at DESC, document_type)
    WHERE is_archived = FALSE;

-- Dashboard: Sales summary by company and period
CREATE INDEX IF NOT EXISTS idx_dashboard_sales 
    ON sales(company_id, sale_date DESC)
    INCLUDE (total_amount, cash_amount, card_amount);

-- Provider spending analysis
CREATE INDEX IF NOT EXISTS idx_documents_provider_spending 
    ON documents(company_id, provider_id, document_date)
    INCLUDE (total_amount);

-- ============================================================================
-- PART 5: ANALYZE TABLES (Update Statistics)
-- ============================================================================

ANALYZE companies;
ANALYZE profiles;
ANALYZE company_users;
ANALYZE providers;
ANALYZE products;
ANALYZE documents;
ANALYZE document_items;
ANALYZE orders;
ANALYZE order_items;
ANALYZE sales;
ANALYZE activity_logs;

-- ============================================================================
-- INFO: Missing Index Detection Query
-- ============================================================================
-- Run this periodically to find missing indexes on foreign keys:
/*
SELECT
    conrelid::regclass AS table_name,
    a.attname AS fk_column,
    pg_size_pretty(pg_relation_size(conrelid)) AS table_size
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
)
ORDER BY pg_relation_size(conrelid) DESC;
*/
