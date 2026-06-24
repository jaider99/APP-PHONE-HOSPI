-- ============================================================================
-- HOTFIX: Prevent auth signup failures from profile trigger errors
-- Error fixed: AuthApiError unexpected_failure / Database error saving new user
-- ============================================================================

-- Safer trigger function for auth.users -> public.profiles
-- Never blocks user creation if profile insert fails.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    -- Primary path: schema includes avatar_url
    insert into public.profiles (id, email, full_name, avatar_url, created_at, updated_at)
    values (
      new.id,
      new.email,
      coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
      new.raw_user_meta_data->>'avatar_url',
      now(),
      now()
    )
    on conflict (id) do update
      set email = excluded.email,
          full_name = excluded.full_name,
          avatar_url = excluded.avatar_url,
          updated_at = now();

  exception
    when undefined_column then
      -- Fallback path for older profile schemas (no avatar_url column)
      insert into public.profiles (id, email, full_name, created_at, updated_at)
      values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
        now(),
        now()
      )
      on conflict (id) do update
        set email = excluded.email,
            full_name = excluded.full_name,
            updated_at = now();

    when others then
      -- Do not block auth signup if profile bootstrap fails.
      raise warning 'handle_new_user failed for auth user %: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;

-- Ensure trigger exists and points to the hotfixed function
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
