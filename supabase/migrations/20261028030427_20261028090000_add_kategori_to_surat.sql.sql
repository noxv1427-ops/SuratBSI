/*
# Tambah kolom kategori pada tabel surat

1. Perubahan skema
- Menambahkan kolom `kategori` (text, NOT NULL, default 'Lainnya') pada tabel `public.surat`.
- Menambahkan CHECK constraint untuk membatasi kategori pada daftar tetap: 'Internal', 'Eksternal', 'Permohonan', 'Pemberitahuan', 'Lainnya'.
- Menambahkan index pada `kategori` untuk mempercepat filter.
- Data surat yang sudah ada akan otomatis bernilai 'Lainnya'.

2. Keamanan
- Tidak ada perubahan RLS atau policy. Kolom baru mengikuti policy yang sudah ada (SELECT untuk semua yang login, INSERT oleh pembuat, UPDATE bebas).
- Grant tidak berubah karena `surat` sudah punya grant SELECT/INSERT/UPDATE untuk `authenticated`.

3. Catatan
- Tidak ada data yang dihapus atau diubah.
- Kolom baru diberi default sehingga surat lama tetap valid.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'surat' AND column_name = 'kategori'
  ) THEN
    ALTER TABLE public.surat ADD COLUMN kategori text NOT NULL DEFAULT 'Lainnya';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public' AND table_name = 'surat' AND constraint_name = 'surat_kategori_valid'
  ) THEN
    ALTER TABLE public.surat ADD CONSTRAINT surat_kategori_valid
    CHECK (kategori IN ('Internal', 'Eksternal', 'Permohonan', 'Pemberitahuan', 'Lainnya'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS surat_kategori_idx ON public.surat (kategori);
