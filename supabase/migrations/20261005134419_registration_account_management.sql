/*
# Pendaftaran token dan fungsi pengelolaan akun

1. Perubahan database
- Memperbarui trigger profil agar nama lengkap diambil dari metadata akun baru.
- Menambahkan `create_invite_code()` untuk membuat token pendaftaran 8 karakter yang hanya dapat dibuat super admin.
- Menambahkan fungsi internal `claim_registration_token()` untuk mengklaim token secara atomik dari Edge Function.

2. Keamanan
- Token hanya dapat dibuat melalui fungsi dengan pemeriksaan peran super admin.
- Fungsi internal token tidak dapat dipanggil anon maupun authenticated; hanya service role Edge Function yang dapat menggunakannya.
- Akun baru selalu dibuat dengan peran `admin` melalui trigger.

3. Catatan
- Tidak ada tabel atau kolom lama yang dihapus maupun diubah tipenya.
- `used_by` dihubungkan setelah user berhasil dibuat; kegagalan pembuatan user mengembalikan token ke keadaan belum terpakai.
*/

CREATE OR REPLACE FUNCTION public.set_profile_from_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role, must_change_password)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    'admin',
    false
  )
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      full_name = EXCLUDED.full_name;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_invite_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  raw_code text;
  formatted_code text;
  result_code text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = (SELECT auth.uid()) AND role = 'super_admin'
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  LOOP
    raw_code := '';
    FOR i IN 1..8 LOOP
      raw_code := raw_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    END LOOP;
    formatted_code := substr(raw_code, 1, 4) || '-' || substr(raw_code, 5, 4);
    BEGIN
      INSERT INTO public.invite_codes (code, created_by, expires_at)
      VALUES (formatted_code, (SELECT auth.uid()), now() + interval '7 days')
      RETURNING code INTO result_code;
      RETURN result_code;
    EXCEPTION WHEN unique_violation THEN
      CONTINUE;
    END;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_registration_token(p_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claimed_id uuid;
BEGIN
  UPDATE public.invite_codes
  SET used_at = now()
  WHERE lower(trim(code)) = lower(trim(p_code))
    AND used_at IS NULL
    AND expires_at > now()
  RETURNING id INTO claimed_id;
  RETURN claimed_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_invite_code() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_invite_code() FROM anon;
GRANT EXECUTE ON FUNCTION public.create_invite_code() TO authenticated;

REVOKE ALL ON FUNCTION public.claim_registration_token(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_registration_token(text) FROM anon;
REVOKE ALL ON FUNCTION public.claim_registration_token(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_registration_token(text) TO service_role;
