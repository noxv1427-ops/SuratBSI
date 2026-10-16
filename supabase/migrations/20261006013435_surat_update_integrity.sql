/*
# Integritas pembaruan surat

1. Perubahan
- Menambahkan trigger pada tabel `surat` untuk mengisi `updated_at` otomatis setiap kali surat diperbarui.
- Menolak perubahan pada `created_by` dan `created_at` agar identitas penginput serta waktu input tetap asli.

2. Keamanan
- Memastikan tidak ada policy DELETE pada tabel `surat`.
- Surat tetap hanya dapat dibatalkan atau dipulihkan melalui perubahan status.

3. Catatan
- Tidak ada tabel, kolom, atau data yang dihapus.
- Nomor surat tetap divalidasi oleh unique index yang sudah ada, termasuk surat berstatus dibatalkan.
*/

CREATE OR REPLACE FUNCTION public.protect_surat_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'created_by tidak dapat diubah';
  END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'created_at tidak dapat diubah';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_surat_update_trigger ON public.surat;
CREATE TRIGGER protect_surat_update_trigger
  BEFORE UPDATE ON public.surat
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_surat_update();

DROP POLICY IF EXISTS "Pengguna login dapat menghapus surat" ON public.surat;
DROP POLICY IF EXISTS "Users can delete surat" ON public.surat;
