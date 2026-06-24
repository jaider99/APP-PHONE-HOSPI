-- ============================================================================
-- HOSPIDASH: Provider Deduplication & Fuzzy Matching
-- Version: 1.0.0
-- ============================================================================
-- Prevents duplicate providers and provides smart matching for OCR
-- ============================================================================

-- ============================================================================
-- PART 1: NORMALIZATION FUNCTIONS
-- ============================================================================

-- Normalize company/provider name for comparison
CREATE OR REPLACE FUNCTION normalize_business_name(p_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_normalized TEXT;
BEGIN
    IF p_name IS NULL THEN
        RETURN NULL;
    END IF;
    
    v_normalized := p_name;
    
    -- Convert to lowercase
    v_normalized := lower(v_normalized);
    
    -- Remove accents (using immutable wrapper defined in 00001)
    v_normalized := immutable_unaccent(v_normalized);
    
    -- Remove common Spanish business suffixes
    v_normalized := regexp_replace(v_normalized, '\s*(s\.?l\.?u?\.?|s\.?a\.?|s\.?c\.?|sociedad limitada|sociedad anonima|comercial)\s*$', '', 'gi');
    
    -- Remove punctuation and extra spaces
    v_normalized := regexp_replace(v_normalized, '[^a-z0-9\s]', '', 'g');
    v_normalized := regexp_replace(v_normalized, '\s+', ' ', 'g');
    v_normalized := trim(v_normalized);
    
    RETURN v_normalized;
END;
$$;

-- Normalize tax ID (CIF/NIF)
CREATE OR REPLACE FUNCTION normalize_tax_id(p_tax_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_tax_id IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Remove all non-alphanumeric characters and convert to uppercase
    RETURN upper(regexp_replace(p_tax_id, '[^A-Za-z0-9]', '', 'g'));
END;
$$;

-- ============================================================================
-- PART 2: FUZZY MATCHING FUNCTIONS
-- ============================================================================

-- Calculate similarity score between two names (0-100)
CREATE OR REPLACE FUNCTION name_similarity_score(p_name1 TEXT, p_name2 TEXT)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT ROUND(
        (similarity(
            normalize_business_name(p_name1),
            normalize_business_name(p_name2)
        ) * 100)::NUMERIC,
        2
    );
$$;

-- Find potential duplicate providers
CREATE OR REPLACE FUNCTION find_similar_providers(
    p_company_id UUID,
    p_name TEXT,
    p_threshold NUMERIC DEFAULT 70  -- Minimum similarity percentage
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    tax_id TEXT,
    similarity_score NUMERIC
)
LANGUAGE SQL
STABLE
AS $$
    SELECT 
        p.id,
        p.name,
        p.tax_id,
        name_similarity_score(p.name, p_name) AS similarity_score
    FROM providers p
    WHERE p.company_id = p_company_id
    AND p.is_active = TRUE
    AND (
        -- Exact normalized match
        p.name_normalized = lower(trim(regexp_replace(immutable_unaccent(p_name), '[^a-zA-Z0-9]', '', 'g')))
        -- Or fuzzy match above threshold
        OR similarity(normalize_business_name(p.name), normalize_business_name(p_name)) > p_threshold / 100.0
    )
    ORDER BY similarity_score DESC
    LIMIT 10;
$$;

-- Find provider by tax ID (exact match after normalization)
CREATE OR REPLACE FUNCTION find_provider_by_tax_id(
    p_company_id UUID,
    p_tax_id TEXT
)
RETURNS UUID
LANGUAGE SQL
STABLE
AS $$
    SELECT id
    FROM providers
    WHERE company_id = p_company_id
    AND normalize_tax_id(tax_id) = normalize_tax_id(p_tax_id)
    AND is_active = TRUE
    LIMIT 1;
$$;

-- ============================================================================
-- PART 3: SMART PROVIDER CREATION/MATCHING
-- ============================================================================

-- Create or match provider (for OCR workflow)
CREATE OR REPLACE FUNCTION create_or_match_provider(
    p_company_id UUID,
    p_name TEXT,
    p_tax_id TEXT DEFAULT NULL,
    p_email TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_address TEXT DEFAULT NULL,
    p_auto_create BOOLEAN DEFAULT FALSE  -- If TRUE, auto-create when no match found
)
RETURNS TABLE (
    provider_id UUID,
    match_type TEXT,  -- 'exact_tax_id', 'exact_name', 'fuzzy_match', 'created', 'no_match'
    confidence NUMERIC,
    suggestions JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_provider_id UUID;
    v_match_type TEXT;
    v_confidence NUMERIC;
    v_suggestions JSONB;
BEGIN
    -- 1. Try exact match by tax ID (highest confidence)
    IF p_tax_id IS NOT NULL THEN
        SELECT id INTO v_provider_id
        FROM providers
        WHERE company_id = p_company_id
        AND normalize_tax_id(tax_id) = normalize_tax_id(p_tax_id)
        AND is_active = TRUE;
        
        IF v_provider_id IS NOT NULL THEN
            RETURN QUERY SELECT v_provider_id, 'exact_tax_id'::TEXT, 100::NUMERIC, NULL::JSONB;
            RETURN;
        END IF;
    END IF;
    
    -- 2. Try exact normalized name match
    SELECT id INTO v_provider_id
    FROM providers
    WHERE company_id = p_company_id
    AND name_normalized = lower(trim(regexp_replace(immutable_unaccent(p_name), '[^a-zA-Z0-9]', '', 'g')))
    AND is_active = TRUE;
    
    IF v_provider_id IS NOT NULL THEN
        RETURN QUERY SELECT v_provider_id, 'exact_name'::TEXT, 95::NUMERIC, NULL::JSONB;
        RETURN;
    END IF;
    
    -- 3. Try fuzzy matching
    SELECT 
        jsonb_agg(
            jsonb_build_object(
                'id', s.id,
                'name', s.name,
                'tax_id', s.tax_id,
                'score', s.similarity_score
            ) ORDER BY s.similarity_score DESC
        )
    INTO v_suggestions
    FROM find_similar_providers(p_company_id, p_name, 70) s;
    
    -- If we have a high-confidence fuzzy match (>85%), use it
    IF v_suggestions IS NOT NULL AND jsonb_array_length(v_suggestions) > 0 THEN
        SELECT 
            (v_suggestions->0->>'id')::UUID,
            (v_suggestions->0->>'score')::NUMERIC
        INTO v_provider_id, v_confidence;
        
        IF v_confidence >= 85 THEN
            RETURN QUERY SELECT v_provider_id, 'fuzzy_match'::TEXT, v_confidence, v_suggestions;
            RETURN;
        END IF;
    END IF;
    
    -- 4. Auto-create or return suggestions
    IF p_auto_create AND (v_suggestions IS NULL OR jsonb_array_length(v_suggestions) = 0) THEN
        INSERT INTO providers (company_id, name, tax_id, email, phone, address)
        VALUES (p_company_id, p_name, p_tax_id, p_email, p_phone, p_address)
        RETURNING id INTO v_provider_id;
        
        RETURN QUERY SELECT v_provider_id, 'created'::TEXT, 100::NUMERIC, NULL::JSONB;
        RETURN;
    END IF;
    
    -- 5. No match - return suggestions for manual selection
    RETURN QUERY SELECT NULL::UUID, 'no_match'::TEXT, 0::NUMERIC, COALESCE(v_suggestions, '[]'::JSONB);
END;
$$;

-- ============================================================================
-- PART 4: DUPLICATE PREVENTION TRIGGER
-- ============================================================================

-- Trigger function to prevent exact duplicates
CREATE OR REPLACE FUNCTION prevent_duplicate_provider()
RETURNS TRIGGER
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
    AND id != COALESCE(NEW.id, uuid_generate_v4())
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
        AND id != COALESCE(NEW.id, uuid_generate_v4())
        AND is_active = TRUE;
        
        IF v_existing_id IS NOT NULL THEN
            RAISE EXCEPTION 'A provider with this tax ID already exists (ID: %)', v_existing_id
                USING ERRCODE = 'unique_violation';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER check_duplicate_provider
    BEFORE INSERT OR UPDATE ON providers
    FOR EACH ROW
    EXECUTE FUNCTION prevent_duplicate_provider();

-- ============================================================================
-- PART 5: MERGE DUPLICATE PROVIDERS
-- ============================================================================

-- Merge two providers (keep target, transfer references from source)
CREATE OR REPLACE FUNCTION merge_providers(
    p_target_id UUID,
    p_source_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
BEGIN
    -- Verify both providers exist and belong to same company
    SELECT company_id INTO v_company_id
    FROM providers
    WHERE id = p_target_id;
    
    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'Target provider not found';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM providers WHERE id = p_source_id AND company_id = v_company_id) THEN
        RAISE EXCEPTION 'Source provider not found or belongs to different company';
    END IF;
    
    -- Check user has admin access
    IF NOT user_is_company_admin(v_company_id) THEN
        RAISE EXCEPTION 'Only admins can merge providers';
    END IF;
    
    -- Transfer all references from source to target
    UPDATE documents SET provider_id = p_target_id WHERE provider_id = p_source_id;
    UPDATE products SET provider_id = p_target_id WHERE provider_id = p_source_id;
    UPDATE orders SET provider_id = p_target_id WHERE provider_id = p_source_id;
    
    -- Soft delete the source provider
    UPDATE providers SET is_active = FALSE WHERE id = p_source_id;
    
    -- Log the merge
    INSERT INTO activity_logs (company_id, user_id, action, entity_type, entity_id, new_data)
    VALUES (
        v_company_id,
        (SELECT auth.uid()),
        'merge',
        'provider',
        p_target_id,
        jsonb_build_object('merged_from', p_source_id)
    );
    
    RETURN TRUE;
END;
$$;

-- ============================================================================
-- PART 6: GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION normalize_business_name TO authenticated;
GRANT EXECUTE ON FUNCTION normalize_tax_id TO authenticated;
GRANT EXECUTE ON FUNCTION name_similarity_score TO authenticated;
GRANT EXECUTE ON FUNCTION find_similar_providers TO authenticated;
GRANT EXECUTE ON FUNCTION find_provider_by_tax_id TO authenticated;
GRANT EXECUTE ON FUNCTION create_or_match_provider TO authenticated;
GRANT EXECUTE ON FUNCTION merge_providers TO authenticated;
