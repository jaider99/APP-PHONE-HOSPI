-- Fix remaining extraction finalization UUID failures in supplier resolution.
-- Document completion can call resolve_supplier(), which inserts providers and
-- supplier_aliases under restricted search_path contexts.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE IF EXISTS public.providers
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE IF EXISTS public.supplier_aliases
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

CREATE OR REPLACE FUNCTION public.prevent_duplicate_provider()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing_id UUID;
BEGIN
    -- Check for exact normalized name match
    SELECT id INTO v_existing_id
    FROM providers
    WHERE company_id = NEW.company_id
    AND name_normalized = NEW.name_normalized
    AND id != COALESCE(NEW.id, gen_random_uuid())
    AND is_active = TRUE;

    IF v_existing_id IS NOT NULL THEN
        RAISE EXCEPTION 'A provider with a similar name already exists (ID: %)', v_existing_id
            USING ERRCODE = 'unique_violation';
    END IF;

    -- Check for exact tax ID match (if provided)
    IF NEW.tax_id IS NOT NULL THEN
        SELECT id INTO v_existing_id
        FROM providers
        WHERE company_id = NEW.company_id
        AND normalize_tax_id(tax_id) = normalize_tax_id(NEW.tax_id)
        AND id != COALESCE(NEW.id, gen_random_uuid())
        AND is_active = TRUE;

        IF v_existing_id IS NOT NULL THEN
            RAISE EXCEPTION 'A provider with this tax ID already exists (ID: %)', v_existing_id
                USING ERRCODE = 'unique_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
