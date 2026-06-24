-- ============================================================================
-- HOSPIDASH: Storage Buckets & Policies
-- Version: 1.0.0
-- ============================================================================
-- Configures Supabase Storage with company-scoped access control
-- Files are organized by: {bucket}/{company_id}/{type}/{filename}
-- ============================================================================

-- ============================================================================
-- PART 1: CREATE STORAGE BUCKETS
-- ============================================================================

-- Documents bucket (invoices, receipts, delivery notes)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'documents',
    'documents',
    FALSE,  -- Private bucket
    10485760,  -- 10MB limit per file
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Company assets (logos, banners)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'company-assets',
    'company-assets',
    TRUE,  -- Public for logos
    5242880,  -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- User avatars
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'avatars',
    'avatars',
    TRUE,  -- Public avatars
    2097152,  -- 2MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================
-- PART 2: STORAGE POLICIES FOR 'documents' BUCKET
-- ============================================================================
-- Path format: {company_id}/{document_type}/{year}/{month}/{filename}
-- Example: abc123/invoices/2024/03/invoice_001.pdf

-- Helper function to extract company_id from path (in public schema)
CREATE OR REPLACE FUNCTION get_company_id_from_path(file_path TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- Path format: {company_id}/...
    RETURN (string_to_array(file_path, '/'))[1]::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

-- SELECT: Users can view documents from their current company
CREATE POLICY "Company members can view documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'documents'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
);

-- INSERT: Users can upload to their company's folder
CREATE POLICY "Company members can upload documents"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'documents'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
    -- Only members with write access
    AND (SELECT user_has_role_in_company(
        (SELECT get_current_company_id()), 
        ARRAY['owner', 'admin', 'manager', 'member']
    ))
);

-- UPDATE: Users can update documents in their company's folder
CREATE POLICY "Company members can update documents"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'documents'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
)
WITH CHECK (
    bucket_id = 'documents'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
);

-- DELETE: Only admins can delete documents
CREATE POLICY "Admins can delete documents"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'documents'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
    AND (SELECT user_is_company_admin((SELECT get_current_company_id())))
);

-- ============================================================================
-- PART 3: STORAGE POLICIES FOR 'company-assets' BUCKET
-- ============================================================================
-- Path format: {company_id}/{asset_type}/{filename}
-- Example: abc123/logo/company_logo.png

-- SELECT: Public read for company assets
CREATE POLICY "Anyone can view company assets"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'company-assets');

-- INSERT: Only company admins can upload
CREATE POLICY "Admins can upload company assets"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'company-assets'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
    AND (SELECT user_is_company_admin((SELECT get_current_company_id())))
);

-- UPDATE: Only company admins
CREATE POLICY "Admins can update company assets"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'company-assets'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
    AND (SELECT user_is_company_admin((SELECT get_current_company_id())))
);

-- DELETE: Only company admins
CREATE POLICY "Admins can delete company assets"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'company-assets'
    AND get_company_id_from_path(name) = (SELECT get_current_company_id())
    AND (SELECT user_is_company_admin((SELECT get_current_company_id())))
);

-- ============================================================================
-- PART 4: STORAGE POLICIES FOR 'avatars' BUCKET
-- ============================================================================
-- Path format: {user_id}/{filename}

-- SELECT: Public read for avatars
CREATE POLICY "Anyone can view avatars"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');

-- INSERT: Users can upload their own avatar
CREATE POLICY "Users can upload own avatar"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'avatars'
    AND (string_to_array(name, '/'))[1]::UUID = (SELECT auth.uid())
);

-- UPDATE: Users can update their own avatar
CREATE POLICY "Users can update own avatar"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'avatars'
    AND (string_to_array(name, '/'))[1]::UUID = (SELECT auth.uid())
);

-- DELETE: Users can delete their own avatar
CREATE POLICY "Users can delete own avatar"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'avatars'
    AND (string_to_array(name, '/'))[1]::UUID = (SELECT auth.uid())
);

-- ============================================================================
-- PART 5: HELPER FUNCTIONS FOR FILE OPERATIONS
-- ============================================================================

-- Generate storage path for a document
CREATE OR REPLACE FUNCTION generate_document_path(
    p_company_id UUID,
    p_document_type TEXT,
    p_filename TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN format(
        '%s/%s/%s/%s/%s',
        p_company_id,
        p_document_type,  -- 'invoices', 'receipts', etc.
        to_char(NOW(), 'YYYY'),
        to_char(NOW(), 'MM'),
        p_filename
    );
END;
$$;

-- Get public URL for a file
CREATE OR REPLACE FUNCTION get_document_url(p_file_path TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_bucket_url TEXT;
BEGIN
    -- Construct public URL (adjust based on your Supabase project URL)
    v_bucket_url := current_setting('app.supabase_url', TRUE) || '/storage/v1/object/public/documents/';
    RETURN v_bucket_url || p_file_path;
END;
$$;

GRANT EXECUTE ON FUNCTION generate_document_path TO authenticated;
GRANT EXECUTE ON FUNCTION get_document_url TO authenticated;
