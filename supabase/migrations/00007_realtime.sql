-- ============================================================================
-- HOSPIDASH: Realtime Configuration
-- Version: 1.0.0
-- ============================================================================
-- Enables realtime subscriptions for live updates in the app
-- ============================================================================

-- ============================================================================
-- PART 1: ENABLE REALTIME ON TABLES
-- ============================================================================
-- Note: Realtime respects RLS policies - users only receive updates for
-- rows they have SELECT access to.

-- Enable realtime for documents (new invoices, OCR updates)
ALTER PUBLICATION supabase_realtime ADD TABLE documents;

-- Enable realtime for sales (live dashboard updates)
ALTER PUBLICATION supabase_realtime ADD TABLE sales;

-- Enable realtime for orders (order status changes)
ALTER PUBLICATION supabase_realtime ADD TABLE orders;

-- Enable realtime for notifications (if we add later)
-- ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- ============================================================================
-- PART 2: REALTIME REPLICA IDENTITY
-- ============================================================================
-- Full replica identity is needed for UPDATE and DELETE events to include
-- the full row data (not just primary key)

ALTER TABLE documents REPLICA IDENTITY FULL;
ALTER TABLE sales REPLICA IDENTITY FULL;
ALTER TABLE orders REPLICA IDENTITY FULL;

-- ============================================================================
-- PART 3: DASHBOARD STATS MATERIALIZED VIEW (Optional Optimization)
-- ============================================================================
-- For very frequent dashboard queries, consider a materialized view
-- that's refreshed periodically

CREATE MATERIALIZED VIEW IF NOT EXISTS dashboard_stats AS
SELECT 
    company_id,
    -- Sales summary (last 30 days)
    SUM(CASE WHEN sale_date >= CURRENT_DATE - INTERVAL '30 days' THEN total_amount ELSE 0 END) AS sales_30d,
    SUM(CASE WHEN sale_date >= CURRENT_DATE - INTERVAL '7 days' THEN total_amount ELSE 0 END) AS sales_7d,
    SUM(CASE WHEN sale_date = CURRENT_DATE THEN total_amount ELSE 0 END) AS sales_today,
    COUNT(CASE WHEN sale_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS sales_count_30d
FROM sales
GROUP BY company_id;

-- Index for fast lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_dashboard_stats_company ON dashboard_stats(company_id);

-- Function to refresh stats
CREATE OR REPLACE FUNCTION refresh_dashboard_stats()
RETURNS VOID
LANGUAGE SQL
SECURITY DEFINER
AS $$
    REFRESH MATERIALIZED VIEW CONCURRENTLY dashboard_stats;
$$;

-- ============================================================================
-- PART 4: NOTIFICATION HELPERS (For Push/In-App Notifications)
-- ============================================================================

-- Trigger function to notify on important events
CREATE OR REPLACE FUNCTION notify_document_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Notify via Postgres NOTIFY for realtime listeners
    PERFORM pg_notify(
        'document_changes',
        json_build_object(
            'operation', TG_OP,
            'company_id', NEW.company_id,
            'document_id', NEW.id,
            'document_type', NEW.document_type,
            'ocr_status', NEW.ocr_status
        )::TEXT
    );
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER notify_on_document_change
    AFTER INSERT OR UPDATE ON documents
    FOR EACH ROW
    EXECUTE FUNCTION notify_document_change();

-- ============================================================================
-- PART 5: OCR STATUS CHANGE NOTIFIER
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_ocr_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only notify when OCR completes
    IF OLD.ocr_status = 'processing' AND NEW.ocr_status = 'completed' THEN
        PERFORM pg_notify(
            'ocr_complete',
            json_build_object(
                'company_id', NEW.company_id,
                'document_id', NEW.id,
                'provider_id', NEW.provider_id,
                'total_amount', NEW.total_amount
            )::TEXT
        );
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE TRIGGER notify_on_ocr_complete
    AFTER UPDATE ON documents
    FOR EACH ROW
    WHEN (OLD.ocr_status = 'processing' AND NEW.ocr_status = 'completed')
    EXECUTE FUNCTION notify_ocr_complete();
