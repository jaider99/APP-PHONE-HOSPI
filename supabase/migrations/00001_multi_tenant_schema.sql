-- ============================================================================
-- HOSPIDASH: Multi-Tenant SaaS Schema for Hospitality
-- Version: 1.0.0
-- ============================================================================
-- This migration creates the complete multi-tenant database schema
-- with strict company-based data isolation.
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text matching
CREATE EXTENSION IF NOT EXISTS "unaccent"; -- For accent-insensitive search

-- Create IMMUTABLE wrapper for unaccent (required for generated columns)
CREATE OR REPLACE FUNCTION immutable_unaccent(text)
RETURNS text AS $$
    SELECT unaccent($1)
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- ============================================================================
-- PART 1: CORE TENANT TABLES
-- ============================================================================

-- Companies (Tenants)
-- Each company is a separate tenant with isolated data
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    legal_name TEXT,
    tax_id TEXT, -- CIF/NIF for Spanish companies
    address TEXT,
    city TEXT,
    postal_code TEXT,
    country TEXT DEFAULT 'ES',
    phone TEXT,
    email TEXT,
    logo_url TEXT,
    subscription_plan TEXT DEFAULT 'free' CHECK (subscription_plan IN ('free', 'starter', 'professional', 'enterprise')),
    subscription_status TEXT DEFAULT 'active' CHECK (subscription_status IN ('active', 'trial', 'suspended', 'cancelled')),
    trial_ends_at TIMESTAMPTZ,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- User Profiles (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    phone TEXT,
    current_company_id UUID REFERENCES companies(id) ON DELETE SET NULL,
    preferences JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Company Users (Many-to-Many: Users <-> Companies)
-- A user can belong to multiple companies with different roles
CREATE TABLE IF NOT EXISTS company_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'manager', 'member', 'viewer')),
    permissions JSONB DEFAULT '[]', -- Granular permissions array
    invited_by UUID REFERENCES profiles(id),
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    joined_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    UNIQUE (company_id, user_id)
);

-- ============================================================================
-- PART 2: BUSINESS ENTITIES (ALL COMPANY-SCOPED)
-- ============================================================================

-- Providers (Suppliers)
CREATE TABLE IF NOT EXISTS providers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    
    -- Core info
    name TEXT NOT NULL,
    name_normalized TEXT GENERATED ALWAYS AS (
        lower(trim(regexp_replace(immutable_unaccent(name), '[^a-zA-Z0-9]', '', 'g')))
    ) STORED, -- For deduplication matching
    legal_name TEXT,
    tax_id TEXT, -- CIF/NIF
    
    -- Contact
    email TEXT,
    phone TEXT,
    website TEXT,
    
    -- Address
    address TEXT,
    city TEXT,
    postal_code TEXT,
    country TEXT DEFAULT 'ES',
    
    -- Business details
    category TEXT, -- e.g., 'beverages', 'food', 'cleaning', 'equipment'
    payment_terms INTEGER DEFAULT 30, -- Days
    notes TEXT,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    created_by UUID REFERENCES profiles(id),
    
    -- Prevent duplicate providers within same company
    UNIQUE (company_id, name_normalized)
);

-- Products (items purchased from providers)
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    provider_id UUID REFERENCES providers(id) ON DELETE SET NULL,
    
    -- Core info
    name TEXT NOT NULL,
    name_normalized TEXT GENERATED ALWAYS AS (
        lower(trim(regexp_replace(immutable_unaccent(name), '[^a-zA-Z0-9]', '', 'g')))
    ) STORED,
    sku TEXT,
    barcode TEXT,
    description TEXT,
    
    -- Categorization
    category TEXT,
    subcategory TEXT,
    
    -- Pricing
    unit_price NUMERIC(12,4),
    currency TEXT DEFAULT 'EUR',
    unit_type TEXT DEFAULT 'unit', -- unit, kg, liter, box, pack
    tax_rate NUMERIC(5,2) DEFAULT 21.00, -- IVA in Spain
    
    -- Inventory
    track_inventory BOOLEAN DEFAULT FALSE,
    min_stock_level NUMERIC(12,2),
    current_stock NUMERIC(12,2) DEFAULT 0,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    created_by UUID REFERENCES profiles(id),
    
    UNIQUE (company_id, name_normalized, provider_id)
);

-- Documents (Invoices, receipts, delivery notes)
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    provider_id UUID REFERENCES providers(id) ON DELETE SET NULL,
    
    -- Document info
    document_type TEXT NOT NULL CHECK (document_type IN ('invoice', 'receipt', 'delivery_note', 'credit_note', 'quote', 'other')),
    document_number TEXT, -- Invoice number from provider
    
    -- Dates
    document_date DATE,
    due_date DATE,
    received_date TIMESTAMPTZ DEFAULT NOW(),
    
    -- Amounts
    subtotal NUMERIC(12,2),
    tax_amount NUMERIC(12,2),
    total_amount NUMERIC(12,2),
    currency TEXT DEFAULT 'EUR',
    
    -- Payment
    payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'partial', 'paid', 'overdue', 'cancelled')),
    paid_amount NUMERIC(12,2) DEFAULT 0,
    paid_at TIMESTAMPTZ,
    payment_method TEXT,
    
    -- OCR Processing
    ocr_status TEXT DEFAULT 'pending' CHECK (ocr_status IN ('pending', 'processing', 'completed', 'failed', 'manual')),
    ocr_confidence NUMERIC(5,2), -- 0-100
    ocr_raw_data JSONB,
    ocr_processed_at TIMESTAMPTZ,
    
    -- File storage
    file_url TEXT,
    file_path TEXT, -- Path in storage bucket
    file_size INTEGER,
    file_type TEXT,
    thumbnail_url TEXT,
    
    -- Notes and tags
    notes TEXT,
    tags TEXT[],
    
    -- Status
    is_archived BOOLEAN DEFAULT FALSE,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    created_by UUID REFERENCES profiles(id)
);

-- Document Line Items (for detailed OCR extraction)
CREATE TABLE IF NOT EXISTS document_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    
    -- Item details
    description TEXT NOT NULL,
    quantity NUMERIC(12,3),
    unit_type TEXT,
    unit_price NUMERIC(12,4),
    discount_percent NUMERIC(5,2) DEFAULT 0,
    tax_rate NUMERIC(5,2),
    line_total NUMERIC(12,2),
    
    -- OCR matching
    matched_automatically BOOLEAN DEFAULT FALSE,
    confidence_score NUMERIC(5,2),
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Orders (to providers)
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    provider_id UUID NOT NULL REFERENCES providers(id) ON DELETE RESTRICT,
    
    -- Order info
    order_number TEXT,
    order_date TIMESTAMPTZ DEFAULT NOW(),
    expected_delivery_date DATE,
    actual_delivery_date DATE,
    
    -- Status
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'returned')),
    
    -- Amounts
    subtotal NUMERIC(12,2),
    tax_amount NUMERIC(12,2),
    total_amount NUMERIC(12,2),
    currency TEXT DEFAULT 'EUR',
    
    -- Delivery
    delivery_address TEXT,
    delivery_notes TEXT,
    
    -- Notes
    notes TEXT,
    internal_notes TEXT,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    created_by UUID REFERENCES profiles(id),
    confirmed_by UUID REFERENCES profiles(id),
    confirmed_at TIMESTAMPTZ
);

-- Order Items
CREATE TABLE IF NOT EXISTS order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    
    -- Item details
    description TEXT NOT NULL,
    quantity NUMERIC(12,3) NOT NULL,
    unit_type TEXT,
    unit_price NUMERIC(12,4),
    discount_percent NUMERIC(5,2) DEFAULT 0,
    tax_rate NUMERIC(5,2),
    line_total NUMERIC(12,2),
    
    -- Fulfillment
    quantity_received NUMERIC(12,3) DEFAULT 0,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Sales (POS transactions / daily sales)
CREATE TABLE IF NOT EXISTS sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    
    -- Sale info
    sale_date DATE NOT NULL DEFAULT CURRENT_DATE,
    sale_time TIME,
    
    -- Amounts
    cash_amount NUMERIC(12,2) DEFAULT 0,
    card_amount NUMERIC(12,2) DEFAULT 0,
    other_amount NUMERIC(12,2) DEFAULT 0,
    total_amount NUMERIC(12,2),
    
    -- Breakdown
    tax_collected NUMERIC(12,2),
    tips_amount NUMERIC(12,2) DEFAULT 0,
    discounts_amount NUMERIC(12,2) DEFAULT 0,
    
    -- Counts
    transaction_count INTEGER DEFAULT 0,
    covers_count INTEGER DEFAULT 0, -- Number of customers served
    
    -- Source
    source TEXT DEFAULT 'manual' CHECK (source IN ('manual', 'pos_import', 'api')),
    pos_reference TEXT,
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    created_by UUID REFERENCES profiles(id),
    
    -- One sale record per day per company
    UNIQUE (company_id, sale_date)
);

-- ============================================================================
-- PART 3: AUDIT & ACTIVITY LOGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    
    -- Action details
    action TEXT NOT NULL, -- 'create', 'update', 'delete', 'view', 'export'
    entity_type TEXT NOT NULL, -- 'document', 'order', 'provider', etc.
    entity_id UUID,
    
    -- Change details
    old_data JSONB,
    new_data JSONB,
    
    -- Context
    ip_address INET,
    user_agent TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- PART 4: UPDATED_AT TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables with updated_at
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename IN (
        'companies', 'profiles', 'company_users', 'providers', 'products', 
        'documents', 'orders', 'sales'
    )
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS update_%I_updated_at ON %I;
            CREATE TRIGGER update_%I_updated_at
                BEFORE UPDATE ON %I
                FOR EACH ROW
                EXECUTE FUNCTION update_updated_at_column();
        ', tbl, tbl, tbl, tbl);
    END LOOP;
END;
$$;

-- ============================================================================
-- PART 5: COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE companies IS 'Multi-tenant company/organization records';
COMMENT ON TABLE profiles IS 'User profiles extending Supabase auth.users';
COMMENT ON TABLE company_users IS 'Many-to-many relationship between users and companies with roles';
COMMENT ON TABLE providers IS 'Suppliers/vendors providing products and services';
COMMENT ON TABLE products IS 'Products/items purchased from providers';
COMMENT ON TABLE documents IS 'Invoices, receipts, and other documents with OCR support';
COMMENT ON TABLE orders IS 'Purchase orders to providers';
COMMENT ON TABLE sales IS 'Daily sales records from POS or manual entry';
COMMENT ON COLUMN providers.name_normalized IS 'Auto-generated normalized name for deduplication';
COMMENT ON COLUMN documents.ocr_status IS 'Processing status: pending, processing, completed, failed, manual';
