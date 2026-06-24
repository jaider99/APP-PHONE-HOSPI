# Supabase Setup Guide

This document contains all the SQL scripts needed to set up the authentication 
and user profile tables in Supabase for the HospiDash application.

## Prerequisites

1. Create a Supabase project at https://supabase.com
2. Get your project URL and anon key from Settings > API
3. Update `lib/core/config/env_config.dart` with your credentials

---

## Quick Setup (Copy & Paste All)

Copy this entire block and run it in Supabase SQL Editor:

```sql
-- ============================================
-- HospiDash Complete Database Setup
-- Run this entire script in Supabase SQL Editor
-- Safe to run multiple times (idempotent)
-- ============================================

-- 1. Create Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.profiles IS 'User profiles for HospiDash app';

-- 2. Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first (idempotent)
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

CREATE POLICY "Users can view own profile" 
ON public.profiles FOR SELECT 
USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" 
ON public.profiles FOR INSERT 
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" 
ON public.profiles FOR UPDATE 
USING (auth.uid() = id);

-- 3. Auto-Create Profile Trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (
    new.id, 
    COALESCE(new.raw_user_meta_data->>'full_name', '')
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_new_user();

-- 4. Updated At Trigger
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
```

---

## SQL Scripts (Individual)

If you prefer to run scripts individually, use the sections below.
**Important:** Only copy the code inside the \`\`\`sql blocks, not the markdown headers.

### 1. Create Profiles Table

```sql
-- Table: profiles
-- Stores user profile information linked to auth.users
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add comment for documentation
COMMENT ON TABLE public.profiles IS 'User profiles for HospiDash app';
```

### 2. Enable Row Level Security (RLS)

```sql
-- Enable RLS on profiles table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own profile
CREATE POLICY "Users can view own profile" 
ON public.profiles 
FOR SELECT 
USING (auth.uid() = id);

-- Policy: Users can insert their own profile
CREATE POLICY "Users can insert own profile" 
ON public.profiles 
FOR INSERT 
WITH CHECK (auth.uid() = id);

-- Policy: Users can update their own profile
CREATE POLICY "Users can update own profile" 
ON public.profiles 
FOR UPDATE 
USING (auth.uid() = id);
```

### 3. Auto-Create Profile Trigger

This trigger automatically creates a profile row when a new user signs up:

```sql
-- Function: Create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (
    new.id, 
    COALESCE(new.raw_user_meta_data->>'full_name', '')
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Execute function after user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_new_user();
```

### 4. Updated At Trigger

Automatically update the `updated_at` timestamp:

```sql
-- Function: Update timestamp on modification
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Auto-update updated_at
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
```

---

## Authentication Settings

Configure these settings in the Supabase Dashboard:

### Auth > Settings

1. **Site URL**: Set to your app's deep link URL
   - Development: `http://localhost:3000`
   - Production: `https://yourapp.com`

2. **Redirect URLs**: Add these URLs
   - `io.hospidash.app://login-callback`
   - `io.hospidash.app://reset-password`
   - `http://localhost:3000/auth/callback` (for web development)

### Auth > Providers

1. **Email**: Enable email/password sign-in
   - Enable "Confirm email" for production
   - Optionally enable "Secure email change"

2. **Google**: 
   - Enable and configure with Google Cloud OAuth credentials
   - Add authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback`

3. **Apple**:
   - Enable and configure with Apple Developer credentials
   - Add Services ID and key

### Auth > Email Templates

Customize these templates for your branding:
- Confirmation email
- Password reset email
- Magic link email

---

## Deep Link Configuration

### iOS (ios/Runner/Info.plist)

Add URL scheme for OAuth callbacks:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>io.hospidash.app</string>
    </array>
  </dict>
</array>
```

### Android (android/app/src/main/AndroidManifest.xml)

Add intent filter for OAuth callbacks:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="io.hospidash.app" android:host="login-callback" />
</intent-filter>
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="io.hospidash.app" android:host="reset-password" />
</intent-filter>
```

---

## Biometric Authentication Setup

### iOS (ios/Runner/Info.plist)

Add Face ID usage description:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Use Face ID to sign in faster to HospiDash</string>
```

### Android (android/app/src/main/AndroidManifest.xml)

Add biometric permissions:

```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.USE_FINGERPRINT"/>
```

---

## Testing

### Test User Creation

```sql
-- View all profiles
SELECT * FROM public.profiles;

-- View auth users (admin only)
SELECT id, email, created_at FROM auth.users;
```

### Verify RLS Policies

```sql
-- Test RLS (will return empty if not authenticated)
SELECT * FROM public.profiles;
```

---

## Troubleshooting

### Profile Not Created on Signup

1. Check trigger exists:
```sql
SELECT * FROM pg_trigger WHERE tgname = 'on_auth_user_created';
```

2. Check function exists:
```sql
SELECT * FROM pg_proc WHERE proname = 'handle_new_user';
```

### RLS Blocking Access

1. Verify policies:
```sql
SELECT * FROM pg_policies WHERE tablename = 'profiles';
```

2. Temporarily disable for debugging (NOT for production):
```sql
ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;
```

### OAuth Redirect Issues

1. Verify redirect URLs in Supabase dashboard match exactly
2. Check deep link configuration in app
3. Test deep links: `adb shell am start -a android.intent.action.VIEW -d "io.hospidash.app://login-callback"`
