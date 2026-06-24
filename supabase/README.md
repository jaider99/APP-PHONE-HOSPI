# Supabase Setup Guide for HospiDash

This guide explains how to set up the Supabase backend for the multi-tenant hospitality SaaS application.

## Prerequisites

- A Supabase project (https://supabase.com)
- Access to the SQL Editor in Supabase Dashboard

## Project Configuration

Your Supabase project URL and anon key are configured in:
- `lib/core/config/env_config.dart`

```dart
SUPABASE_URL: https://qbvfeizmcuctmhrxkvbx.supabase.co
SUPABASE_ANON_KEY: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## Database Setup

Run the migrations in order in the Supabase SQL Editor:

### 1. Create Schema (`00001_multi_tenant_schema.sql`)
Creates all tables with proper relationships:
- `companies` - Tenant organizations
- `profiles` - User profiles (extends auth.users)
- `company_users` - User-company membership with roles
- `providers` - Suppliers/vendors
- `products` - Items from providers
- `documents` - Invoices, receipts (with OCR fields)
- `document_items` - Line items from documents
- `orders` - Purchase orders
- `order_items` - Order line items
- `sales` - Daily sales records
- `activity_logs` - Audit trail

### 2. Enable RLS (`00002_row_level_security.sql`)
Implements strict data isolation:
- Every query is filtered by `company_id`
- Uses optimized helper functions (`(SELECT auth.uid())` pattern)
- Role-based access control (owner, admin, manager, member, viewer)

### 3. Auth Triggers (`00003_auth_triggers.sql`)
Automates user management:
- Auto-creates profile on signup
- `create_company_with_owner()` - Create company and become owner
- `switch_company()` - Switch active company
- `invite_user_to_company()` - Invite team members
- `get_user_context()` - Get current user's full context

### 4. Indexes (`00004_indexes.sql`)
Performance optimization:
- All `company_id` columns indexed
- All foreign keys indexed
- Partial indexes for filtered queries
- Trigram indexes for fuzzy search

### 5. Storage (`00005_storage.sql`)
Document storage configuration:
- `documents` bucket (private, company-scoped)
- `company-assets` bucket (public logos)
- `avatars` bucket (public user avatars)
- RLS policies for storage access

### 6. Provider Deduplication (`00006_provider_deduplication.sql`)
Prevents duplicate providers:
- Name normalization (accents, suffixes, case)
- Fuzzy matching for OCR suggestions
- `create_or_match_provider()` for smart matching

### 7. Realtime (`00007_realtime.sql`)
Live updates:
- Documents, sales, orders enabled
- Notification triggers for OCR completion

## Running Migrations

1. Go to **Supabase Dashboard** → **SQL Editor**
2. Create a new query
3. Copy-paste each migration file content
4. Run in order (00001 → 00007)

Or use Supabase CLI:
```bash
supabase db push
```

## Architecture Overview

### Multi-Tenant Isolation

```
┌─────────────────────────────────────────────────────────┐
│                    User Request                          │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Auth (JWT)                        │
│         Contains: user_id from auth.users              │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│              profiles table                              │
│    Maps user_id → current_company_id                    │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│              RLS Policy                                  │
│    WHERE company_id = get_current_company_id()         │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│              Filtered Data                               │
│         Only current company's data returned            │
└─────────────────────────────────────────────────────────┘
```

### User Roles

| Role | Permissions |
|------|------------|
| `owner` | Full access, can delete company |
| `admin` | Manage members, settings, delete data |
| `manager` | Create/update data, limited settings |
| `member` | Create/update data |
| `viewer` | Read-only access |

### Key Functions

```sql
-- Get user's current company
SELECT get_current_company_id();

-- Get user's full context (company, role, etc.)
SELECT get_user_context();

-- Get all companies user belongs to
SELECT * FROM get_user_companies();

-- Create company (auto-becomes owner)
SELECT create_company_with_owner('My Restaurant', 'My Restaurant S.L.', 'B12345678');

-- Switch active company
SELECT switch_company('company-uuid-here');

-- Find similar providers (for OCR)
SELECT * FROM find_similar_providers(
    'company-id',
    'Comercial Bastida S.L.',
    70  -- threshold
);
```

## Flutter Integration

### Auth Flow

```dart
// Sign up (profile auto-created)
await authService.signUp(
  email: 'user@example.com',
  password: 'password',
  fullName: 'John Doe',
);

// Create company after signup
final companyId = await companyService.createCompany(
  name: 'My Restaurant',
  legalName: 'My Restaurant S.L.',
  taxId: 'B12345678',
);

// Get user context
final context = await authService.getUserContext();
// { user_id, email, current_company_id, role, ... }
```

### Querying Data

```dart
// All queries automatically filtered by company_id via RLS
final providers = await supabase
    .from('providers')
    .select()
    .order('name');
// Returns only current company's providers!

// No need to manually add company_id filter
```

### Switching Companies

```dart
// User belongs to multiple companies
final companies = await companyService.getUserCompanies();

// Switch to another company
await companyService.switchCompany(companies[1].companyId);

// All subsequent queries return new company's data
```

## Testing

Use the queries in `supabase/testing/test_queries.sql` to:
1. Verify RLS is enabled on all tables
2. Test data isolation between companies
3. Check index usage
4. Find missing indexes

## Security Checklist

- [x] RLS enabled on all tables
- [x] RLS forced (prevents table owner bypass)
- [x] All company_id columns indexed
- [x] Foreign keys indexed
- [x] Storage policies enforce company scope
- [x] service_role key never exposed to client
- [x] Anon key is safe for client (limited by RLS)

## Common Issues

### "permission denied for table X"
- User not authenticated
- Profile missing `current_company_id`
- User not member of company (`company_users.is_active = false`)

### Query returns empty when data exists
- RLS filtering by wrong company
- Call `switch_company()` to correct company
- Check `profiles.current_company_id`

### Slow queries
- Run `EXPLAIN ANALYZE` to check for Seq Scan
- Ensure index exists on filtered columns
- Use `(SELECT get_current_company_id())` not direct function call in RLS

## Next Steps

1. Run migrations in Supabase SQL Editor
2. Enable required extensions: `uuid-ossp`, `pg_trgm`, `unaccent`
3. Configure auth providers (email, Google, etc.)
4. Run `flutter pub get` and `dart run build_runner build`
5. Start the app!
