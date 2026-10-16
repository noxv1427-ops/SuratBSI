/*
# Batasi fungsi bantuan profil

1. Perubahan
- Memperbarui hak pemanggilan `is_super_admin()`.
- Memperbarui hak pemanggilan `clear_must_change_password()`.

2. Keamanan
- Pengguna anonim tidak dapat memanggil kedua fungsi yang berjalan dengan hak database.
- Pengguna yang sudah login tetap dapat memakai fungsi sesuai policy dan tujuan aplikasi.

3. Catatan
- Tidak ada tabel, kolom, atau data yang dihapus maupun diubah.
*/

REVOKE EXECUTE ON FUNCTION public.is_super_admin() FROM anon;
REVOKE EXECUTE ON FUNCTION public.clear_must_change_password() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_must_change_password() TO authenticated;
