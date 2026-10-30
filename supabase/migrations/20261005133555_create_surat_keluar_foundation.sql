/*
# Pondasi pencatatan surat keluar BSI

1. Tabel baru
- `profiles`: profil pengguna yang terhubung ke `auth.users`, berisi email, nama lengkap, peran, dan penanda perubahan kata sandi.
- `invite_codes`: kode undangan yang hanya dapat dikelola oleh super admin untuk kebutuhan tahap berikutnya.
- `surat`: data surat keluar dengan nomor unik, tanggal, perihal, status, pembuat, dan waktu perubahan.

2. Integritas data
- Semua tabel memakai UUID sebagai identitas.
- Nomor surat dibuat unik setelah spasi awal/akhir dihapus dan huruf diubah menjadi kecil, termasuk untuk surat yang dibatalkan.
- Profil otomatis dibuat ketika akun baru muncul di `auth.users`.

3. Keamanan
- Row Level Security aktif pada ketiga tabel.
- Profil dapat dibaca oleh pengguna login, tetapi tidak dapat diubah langsung dari klien.
- Kode undangan hanya dapat dilihat, dibuat, dan dihapus oleh super admin.
- Surat dapat dibaca dan dikelola oleh pengguna login sesuai operasi yang ditentukan.
- Fungsi pemeriksaan super admin dan pembersihan penanda perubahan kata sandi berjalan dengan hak database terbatas.

4. Catatan
- Tidak ada policy DELETE untuk tabel `surat`; penghapusan dilakukan dengan mengubah status menjadi `dibatalkan` pada tahap fitur berikutnya.
- Fungsi trigger hanya membuat profil baru jika belum tersedia.
*/

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  full_name text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin')),
  must_change_password boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.invite_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  expires_at timestamptz NOT NULL,
  used_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.surat (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nomor_surat text NOT NULL,
  tanggal_surat date NOT NULL,
  perihal text NOT NULL,
  status text NOT NULL DEFAULT 'aktif' CHECK (status IN ('aktif', 'dibatalkan')),
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS surat_nomor_surat_normalized_idx
  ON public.surat (lower(trim(nomor_surat)));

CREATE OR REPLACE FUNCTION public.set_profile_from_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role, must_change_password)
  VALUES (NEW.id, COALESCE(NEW.email, ''), COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''), 'admin', false)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.set_profile_from_auth_user();

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = (SELECT auth.uid())
      AND role = 'super_admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.clear_must_change_password()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.profiles
  SET must_change_password = false
  WHERE id = (SELECT auth.uid());
$$;

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
REVOKE ALL ON FUNCTION public.clear_must_change_password() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_must_change_password() TO authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.surat ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Pengguna login dapat melihat profil" ON public.profiles;
CREATE POLICY "Pengguna login dapat melihat profil"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Super admin dapat melihat kode undangan" ON public.invite_codes;
CREATE POLICY "Super admin dapat melihat kode undangan"
  ON public.invite_codes FOR SELECT
  TO authenticated
  USING ((SELECT public.is_super_admin()));

DROP POLICY IF EXISTS "Super admin dapat membuat kode undangan" ON public.invite_codes;
CREATE POLICY "Super admin dapat membuat kode undangan"
  ON public.invite_codes FOR INSERT
  TO authenticated
  WITH CHECK ((SELECT public.is_super_admin()) AND created_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Super admin dapat menghapus kode undangan" ON public.invite_codes;
CREATE POLICY "Super admin dapat menghapus kode undangan"
  ON public.invite_codes FOR DELETE
  TO authenticated
  USING ((SELECT public.is_super_admin()));

DROP POLICY IF EXISTS "Pengguna login dapat melihat surat" ON public.surat;
CREATE POLICY "Pengguna login dapat melihat surat"
  ON public.surat FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Pengguna login dapat membuat surat" ON public.surat;
CREATE POLICY "Pengguna login dapat membuat surat"
  ON public.surat FOR INSERT
  TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Pengguna login dapat memperbarui surat" ON public.surat;
CREATE POLICY "Pengguna login dapat memperbarui surat"
  ON public.surat FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
