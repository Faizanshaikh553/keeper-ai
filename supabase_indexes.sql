-- Safe performance indexes for Keeper AI's documents table.
-- Run once in Supabase Dashboard > SQL Editor.

create index if not exists documents_user_space_created_idx
  on public.documents (user_id, space, created_at desc);

create index if not exists documents_org_space_created_idx
  on public.documents (organization_id, space, created_at desc);

create index if not exists documents_file_name_lower_idx
  on public.documents (lower(file_name));

-- IMPORTANT:
-- These indexes improve speed but do not secure the public storage bucket.
-- Keeper currently authenticates users with Firebase rather than Supabase Auth,
-- so production-grade Supabase RLS/private-file access needs a verified backend
-- before public release.
