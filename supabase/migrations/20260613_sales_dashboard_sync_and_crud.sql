-- ============================================================================
-- HOSPIDASH: Sales Dashboard Sync And CRUD
-- Date: 2026-06-13
-- ============================================================================
-- Fixes imported report date normalization fallout, counts aggregate sales rows
-- correctly, and adds tenant-checked RPCs for sales/import/POS management.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.parse_sales_report_day_first_date(p_value text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  parts text[];
  parsed_day int;
  parsed_month int;
  parsed_year int;
  parsed_date date;
BEGIN
  IF p_value IS NULL OR btrim(p_value) = '' THEN
    RETURN NULL;
  END IF;

  p_value := btrim(p_value);

  IF p_value ~ '^\d{4}-\d{2}-\d{2}$' THEN
    RETURN p_value::date;
  END IF;

  IF p_value !~ '^\d{1,2}[\/.-]\d{1,2}[\/.-](\d{2}|\d{4})$' THEN
    RETURN NULL;
  END IF;

  parts := regexp_split_to_array(p_value, '[\/.-]');
  parsed_day := parts[1]::int;
  parsed_month := parts[2]::int;
  parsed_year := parts[3]::int;

  IF parsed_year < 100 THEN
    parsed_year := 2000 + parsed_year;
  END IF;

  IF parsed_year < 2000 OR parsed_year > 2100 THEN
    RETURN NULL;
  END IF;

  BEGIN
    parsed_date := make_date(parsed_year, parsed_month, parsed_day);
  EXCEPTION
    WHEN datetime_field_overflow THEN
      RETURN NULL;
  END;

  RETURN parsed_date;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_sales_import_totals(
  p_company_id uuid,
  p_sales_import_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  totals record;
BEGIN
  SELECT
    MIN(s.sale_date) AS period_start,
    MAX(s.sale_date) AS period_end,
    COALESCE(SUM(s.gross_amount), 0)::numeric(14,2) AS total_gross,
    COALESCE(SUM(COALESCE(s.net_amount, s.gross_amount - COALESCE(s.tax_amount, 0))), 0)::numeric(14,2) AS total_net,
    COALESCE(SUM(COALESCE(s.tax_amount, 0)), 0)::numeric(14,2) AS total_tax
  INTO totals
  FROM public.sales s
  WHERE s.company_id = p_company_id
    AND s.sales_import_id = p_sales_import_id;

  UPDATE public.sales_imports si
  SET
    period_start = totals.period_start,
    period_end = totals.period_end,
    total_gross = totals.total_gross,
    total_net = totals.total_net,
    total_tax = totals.total_tax,
    updated_at = now()
  WHERE si.company_id = p_company_id
    AND si.id = p_sales_import_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_sales_summary(
  p_company_id uuid,
  p_period_start date,
  p_period_end date
)
RETURNS TABLE (
  gross_revenue numeric,
  net_revenue numeric,
  tax_amount numeric,
  transaction_count bigint,
  average_ticket numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.user_belongs_to_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH totals AS (
    SELECT
      COALESCE(SUM(s.gross_amount), 0)::numeric AS gross_revenue,
      COALESCE(SUM(COALESCE(s.net_amount, s.gross_amount - COALESCE(s.tax_amount, 0))), 0)::numeric AS net_revenue,
      COALESCE(SUM(COALESCE(s.tax_amount, 0)), 0)::numeric AS tax_amount,
      COALESCE(SUM(GREATEST(COALESCE(s.transaction_count, 1), 1)), 0)::bigint AS transaction_count
    FROM public.sales s
    WHERE s.company_id = p_company_id
      AND s.sale_date >= p_period_start
      AND s.sale_date <= p_period_end
  )
  SELECT
    totals.gross_revenue,
    totals.net_revenue,
    totals.tax_amount,
    totals.transaction_count,
    CASE
      WHEN totals.transaction_count > 0
        THEN (totals.gross_revenue / totals.transaction_count)::numeric
      ELSE 0::numeric
    END AS average_ticket
  FROM totals;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_sales_record(
  p_company_id uuid,
  p_sale_id uuid,
  p_sale_date date,
  p_gross_amount numeric,
  p_net_amount numeric DEFAULT NULL,
  p_tax_amount numeric DEFAULT NULL,
  p_discount_amount numeric DEFAULT NULL,
  p_tip_amount numeric DEFAULT NULL,
  p_transaction_count int DEFAULT 1,
  p_channel text DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  company_id uuid,
  sales_import_id uuid,
  sale_date date,
  sale_datetime timestamptz,
  gross_amount numeric,
  net_amount numeric,
  tax_amount numeric,
  discount_amount numeric,
  tip_amount numeric,
  currency text,
  payment_method text,
  channel text,
  transaction_count int,
  source_type text,
  metadata jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  linked_import_id uuid;
  normalized_channel text;
BEGIN
  IF NOT public.user_has_role_in_company(p_company_id, ARRAY['owner', 'admin', 'manager', 'member']) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  IF p_sale_date IS NULL THEN
    RAISE EXCEPTION 'Sale date is required' USING ERRCODE = '22004';
  END IF;

  IF p_gross_amount IS NULL OR p_gross_amount < 0 THEN
    RAISE EXCEPTION 'Gross amount must be zero or greater' USING ERRCODE = '22003';
  END IF;

  IF COALESCE(p_transaction_count, 0) < 1 THEN
    RAISE EXCEPTION 'Transaction count must be at least 1' USING ERRCODE = '22003';
  END IF;

  normalized_channel := NULLIF(lower(btrim(COALESCE(p_channel, ''))), '');
  IF normalized_channel IS NOT NULL
     AND normalized_channel NOT IN ('dine_in', 'takeaway', 'delivery', 'unknown') THEN
    RAISE EXCEPTION 'Unsupported sales channel %', normalized_channel USING ERRCODE = '22023';
  END IF;

  SELECT s.sales_import_id
  INTO linked_import_id
  FROM public.sales s
  WHERE s.company_id = p_company_id
    AND s.id = p_sale_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.sales s
  SET
    sale_date = p_sale_date,
    sale_datetime = CASE
      WHEN s.sale_datetime IS NULL OR s.sale_datetime::date IS DISTINCT FROM p_sale_date
        THEN p_sale_date::timestamptz
      ELSE s.sale_datetime
    END,
    gross_amount = round(p_gross_amount, 2),
    total_amount = round(p_gross_amount, 2),
    net_amount = CASE WHEN p_net_amount IS NULL THEN NULL ELSE round(p_net_amount, 2) END,
    tax_amount = CASE WHEN p_tax_amount IS NULL THEN NULL ELSE round(p_tax_amount, 2) END,
    tax_collected = CASE WHEN p_tax_amount IS NULL THEN NULL ELSE round(p_tax_amount, 2) END,
    discount_amount = CASE WHEN p_discount_amount IS NULL THEN NULL ELSE round(p_discount_amount, 2) END,
    discounts_amount = CASE WHEN p_discount_amount IS NULL THEN NULL ELSE round(p_discount_amount, 2) END,
    tip_amount = CASE WHEN p_tip_amount IS NULL THEN NULL ELSE round(p_tip_amount, 2) END,
    tips_amount = CASE WHEN p_tip_amount IS NULL THEN NULL ELSE round(p_tip_amount, 2) END,
    transaction_count = p_transaction_count,
    channel = COALESCE(normalized_channel, 'unknown'),
    payment_method = NULLIF(btrim(COALESCE(p_payment_method, '')), ''),
    metadata = jsonb_strip_nulls(
      COALESCE(s.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'notes', NULLIF(btrim(COALESCE(p_notes, '')), ''),
        'manual_correction', jsonb_build_object(
          'corrected_at', now(),
          'corrected_by', auth.uid(),
          'reason', 'sales_dashboard_edit'
        )
      )
    ),
    updated_at = now()
  WHERE s.company_id = p_company_id
    AND s.id = p_sale_id;

  IF linked_import_id IS NOT NULL THEN
    PERFORM public.recalculate_sales_import_totals(p_company_id, linked_import_id);
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.company_id,
    s.sales_import_id,
    s.sale_date,
    s.sale_datetime,
    s.gross_amount,
    s.net_amount,
    s.tax_amount,
    s.discount_amount,
    s.tip_amount,
    s.currency,
    s.payment_method,
    s.channel,
    s.transaction_count,
    s.source_type,
    s.metadata
  FROM public.sales s
  WHERE s.company_id = p_company_id
    AND s.id = p_sale_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_sales_record(
  p_company_id uuid,
  p_sale_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  linked_import_id uuid;
BEGIN
  IF NOT public.user_is_company_admin(p_company_id) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  SELECT s.sales_import_id
  INTO linked_import_id
  FROM public.sales s
  WHERE s.company_id = p_company_id
    AND s.id = p_sale_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale not found' USING ERRCODE = 'P0002';
  END IF;

  DELETE FROM public.sales_items si
  WHERE si.company_id = p_company_id
    AND si.sale_id = p_sale_id;

  DELETE FROM public.sales s
  WHERE s.company_id = p_company_id
    AND s.id = p_sale_id;

  IF linked_import_id IS NOT NULL THEN
    PERFORM public.recalculate_sales_import_totals(p_company_id, linked_import_id);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_sales_import(
  p_company_id uuid,
  p_sales_import_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.user_is_company_admin(p_company_id) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.sales_imports si
    WHERE si.company_id = p_company_id
      AND si.id = p_sales_import_id
  ) THEN
    RAISE EXCEPTION 'Sales import not found' USING ERRCODE = 'P0002';
  END IF;

  DELETE FROM public.sales_items si
  WHERE si.company_id = p_company_id
    AND si.sales_import_id = p_sales_import_id;

  DELETE FROM public.sales s
  WHERE s.company_id = p_company_id
    AND s.sales_import_id = p_sales_import_id;

  DELETE FROM public.sales_imports si
  WHERE si.company_id = p_company_id
    AND si.id = p_sales_import_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_pos_connection(
  p_company_id uuid,
  p_connection_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.user_is_company_admin(p_company_id) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.pos_connections pc
  WHERE pc.company_id = p_company_id
    AND pc.id = p_connection_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS connection not found' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sales_summary(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_sales_record(uuid, uuid, date, numeric, numeric, numeric, numeric, numeric, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_sales_record(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_sales_import(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_pos_connection(uuid, uuid) TO authenticated;

WITH parsed_imports AS (
  SELECT
    si.id,
    si.company_id,
    public.parse_sales_report_day_first_date(si.extraction_raw->>'period_start') AS parsed_start,
    public.parse_sales_report_day_first_date(si.extraction_raw->>'period_end') AS parsed_end
  FROM public.sales_imports si
  WHERE si.extraction_raw IS NOT NULL
    AND si.source_type IN ('vlm_import', 'csv_import')
), valid_imports AS (
  SELECT
    id,
    company_id,
    parsed_start,
    COALESCE(parsed_end, parsed_start) AS parsed_end
  FROM parsed_imports
  WHERE parsed_start IS NOT NULL
     OR parsed_end IS NOT NULL
)
UPDATE public.sales_imports si
SET
  period_start = COALESCE(vi.parsed_start, vi.parsed_end),
  period_end = vi.parsed_end,
  extraction_clean = CASE
    WHEN si.extraction_clean IS NULL THEN NULL
    ELSE jsonb_set(
      jsonb_set(
        si.extraction_clean,
        '{period_start}',
        to_jsonb(COALESCE(vi.parsed_start, vi.parsed_end)::text),
        true
      ),
      '{period_end}',
      to_jsonb(vi.parsed_end::text),
      true
    )
  END,
  updated_at = now()
FROM valid_imports vi
WHERE si.id = vi.id
  AND si.company_id = vi.company_id
  AND (
    si.period_start IS DISTINCT FROM COALESCE(vi.parsed_start, vi.parsed_end)
    OR si.period_end IS DISTINCT FROM vi.parsed_end
  );

WITH import_dates AS (
  SELECT
    si.id,
    si.company_id,
    si.period_end AS corrected_sale_date
  FROM public.sales_imports si
  WHERE si.period_end IS NOT NULL
), single_sale_imports AS (
  SELECT
    s.company_id,
    s.sales_import_id,
    COUNT(*) AS sale_count
  FROM public.sales s
  WHERE s.sales_import_id IS NOT NULL
  GROUP BY s.company_id, s.sales_import_id
)
UPDATE public.sales s
SET
  sale_date = idt.corrected_sale_date,
  sale_datetime = idt.corrected_sale_date::timestamptz,
  updated_at = now()
FROM import_dates idt
JOIN single_sale_imports ssi
  ON ssi.company_id = idt.company_id
  AND ssi.sales_import_id = idt.id
  AND ssi.sale_count = 1
WHERE s.company_id = idt.company_id
  AND s.sales_import_id = idt.id
  AND s.sale_date IS DISTINCT FROM idt.corrected_sale_date;