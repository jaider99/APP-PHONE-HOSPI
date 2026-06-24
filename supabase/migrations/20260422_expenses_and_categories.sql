-- ============================================================================
-- Migration 20260422: Expenses + Categories foundation for form/tracker
--
-- Adds:
--   1) categories table (company-scoped, with color/icon/sort metadata)
--   2) expenses table (company-scoped, linked to documents/categories)
--   3) documents.expense_id FK for document->expense linking
--   4) RLS policies using user_company_ids()
--   5) Default category seeding for all companies + new company trigger
-- ============================================================================

BEGIN;

-- Ensure helper exists for RLS policies (idempotent).
CREATE OR REPLACE FUNCTION public.user_company_ids()
RETURNS uuid[] AS $$
  SELECT COALESCE(array_agg(company_id), '{}')
  FROM company_users
  WHERE user_id = auth.uid() AND is_active = true;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================================================
-- 1) CATEGORIES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  parent_id uuid REFERENCES categories(id) ON DELETE SET NULL,
  name text NOT NULL,
  name_normalized text GENERATED ALWAYS AS (lower(trim(name))) STORED,
  icon text,
  color_hex text,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT categories_color_hex_check
    CHECK (color_hex IS NULL OR color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_company_name_unique
  ON categories (company_id, name_normalized);

CREATE INDEX IF NOT EXISTS idx_categories_company_parent
  ON categories (company_id, parent_id);

CREATE INDEX IF NOT EXISTS idx_categories_company_active_sort
  ON categories (company_id, is_active, sort_order, name);

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS categories_isolation ON categories;
CREATE POLICY categories_isolation ON categories
  FOR ALL
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ============================================================================
-- 2) EXPENSES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS expenses (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  document_id uuid REFERENCES documents(id) ON DELETE SET NULL,
  category_id uuid REFERENCES categories(id) ON DELETE SET NULL,

  supplier_name text,
  document_date date,
  total_amount numeric(12,2),
  currency text NOT NULL DEFAULT 'EUR',

  document_type text,
  payment_method text,
  purchase_order_id text,
  incident text,
  is_paid boolean NOT NULL DEFAULT false,

  status text NOT NULL DEFAULT 'processing'
    CHECK (status IN ('draft', 'processing', 'completed', 'flagged')),

  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_expenses_company
  ON expenses (company_id);

CREATE INDEX IF NOT EXISTS idx_expenses_company_status
  ON expenses (company_id, status);

CREATE INDEX IF NOT EXISTS idx_expenses_company_date
  ON expenses (company_id, document_date DESC);

CREATE INDEX IF NOT EXISTS idx_expenses_company_category
  ON expenses (company_id, category_id);

CREATE INDEX IF NOT EXISTS idx_expenses_company_created
  ON expenses (company_id, created_at DESC);

ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS expenses_isolation ON expenses;
CREATE POLICY expenses_isolation ON expenses
  FOR ALL
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ============================================================================
-- 3) DOCUMENTS LINK COLUMN
-- ============================================================================

ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS expense_id uuid REFERENCES expenses(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_documents_company_expense
  ON documents (company_id, expense_id);

-- ============================================================================
-- 4) UPDATED_AT TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_categories_updated_at ON categories;
CREATE TRIGGER update_categories_updated_at
  BEFORE UPDATE ON categories
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_expenses_updated_at ON expenses;
CREATE TRIGGER update_expenses_updated_at
  BEFORE UPDATE ON expenses
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 5) DEFAULT CATEGORY SEEDS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.seed_default_expense_categories(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO categories (company_id, name, icon, color_hex, sort_order)
  VALUES
    (p_company_id, 'Raw Materials', 'inventory_2', '#E8D47A', 10),
    (p_company_id, 'Drinks', 'local_bar', '#F2C230', 20),
    (p_company_id, 'Cleaning', 'cleaning_services', '#E9C89A', 30),
    (p_company_id, 'Consumables', 'shopping_basket', '#F28C38', 40),
    (p_company_id, 'Administrative services', 'business_center', '#BEC8F8', 50),
    (p_company_id, 'Marketing and communication', 'campaign', '#7886F0', 60),
    (p_company_id, 'Rent', 'home_work', '#95E0C1', 70),
    (p_company_id, 'Finance', 'account_balance', '#D9DBE1', 80),
    (p_company_id, 'Maintenance', 'handyman', '#A8AAB7', 90),
    (p_company_id, 'Logistics', 'local_shipping', '#8FD3FF', 100),
    (p_company_id, 'Utilities', 'bolt', '#FFD166', 110),
    (p_company_id, 'Other', 'category', '#C4C4C4', 999)
  ON CONFLICT (company_id, name_normalized) DO NOTHING;
END;
$$;

-- Seed defaults for existing companies.
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT id FROM companies LOOP
    PERFORM public.seed_default_expense_categories(c.id);
  END LOOP;
END $$;

-- Auto-seed when a new company is created.
CREATE OR REPLACE FUNCTION public.seed_categories_for_new_company()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.seed_default_expense_categories(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seed_categories_on_company_insert ON companies;
CREATE TRIGGER trg_seed_categories_on_company_insert
  AFTER INSERT ON companies
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_categories_for_new_company();

COMMIT;
