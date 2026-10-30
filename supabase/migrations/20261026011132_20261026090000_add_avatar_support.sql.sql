/*
# Add avatar support — avatar_path column, set_my_avatar function, avatars bucket

1. Changes
- Add `avatar_path` (text, nullable) column to `profiles`. The frontend already queries this column; without it, profile loading fails.
- Add `set_my_avatar(p_path text)` SECURITY DEFINER function so a user can update only their own avatar_path (calls with null to clear).
- Create `avatars` storage bucket (private) for profile photos.

2. Security
- `set_my_avatar` only updates the row where id = auth.uid(), so a user can only change their own avatar.
- REVOKE EXECUTE from PUBLIC/anon; GRANT to authenticated only.
- Storage policies: authenticated users can INSERT/SELECT/DELETE only objects whose first path segment matches their own user id.
*/

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_path text;

CREATE OR REPLACE FUNCTION public.set_my_avatar(p_path text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.profiles
  SET avatar_path = p_path
  WHERE id = (SELECT auth.uid());
$$;

REVOKE ALL ON FUNCTION public.set_my_avatar(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_my_avatar(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_my_avatar(text) TO authenticated;

INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "avatar_upload_own" ON storage.objects;
CREATE POLICY "avatar_upload_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "avatar_read_own" ON storage.objects;
CREATE POLICY "avatar_read_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "avatar_delete_own" ON storage.objects;
CREATE POLICY "avatar_delete_own" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
