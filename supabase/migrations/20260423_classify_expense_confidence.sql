-- Migration 20260423: Add category_confidence to expenses
-- Stores the AI classification confidence level returned by classify-expense.

ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS category_confidence text
  CHECK (
    category_confidence IS NULL OR
    category_confidence IN ('high', 'medium', 'low')
  );
