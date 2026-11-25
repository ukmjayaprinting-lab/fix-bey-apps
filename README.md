# BeyX Stok

Aplikasi Flutter Android untuk mencatat inventaris part Beyblade X dan menyusun
deck tiga combo berdasarkan stok yang tersedia.

## Integrasi Beydle

Sumber online aplikasi ditetapkan hanya ke:

- `https://beydle.com/meta/combos?period=all`

Mode `period=all` dipilih agar konektor meminta ranking sepanjang waktu, bukan
hanya empat minggu terakhir. Beydle menghitung skor podium sebagai
`3 × juara 1 + 2 × juara 2 + 1 × juara 3`. Angka podium bukan win rate
pertandingan.

### Fitur yang ditambahkan

- Menu **Data → Update Sekarang dari Beydle**.
- Sakelar **Update otomatis Beydle**.
- Pemeriksaan otomatis ketika aplikasi dibuka jika pembaruan terakhir sudah
  berumur 24 jam.
- Pemeriksaan berkala 24 jam selama aplikasi tetap aktif.
- Parser HTML tabel ranking Beydle untuk baris format combo + podium.
- Penyimpanan lokal baru dilakukan setelah parsing dan validasi berhasil.
- Jika fetch atau parsing gagal, data combo sebelumnya tetap digunakan.
- Nilai `rankingScore` dari Beydle dipakai untuk mengurutkan rekomendasi deck.

### Batasan yang belum terverifikasi

Halaman Beydle menggunakan pemuatan konten dinamis. Dalam audit saat ini,
tampilan web yang dapat dibaca menampilkan shell pemuatan, sedangkan endpoint
API/data JSON yang dipakai situs belum dapat diverifikasi. Karena itu, konektor
ini bersifat fail-safe: ia mencoba membaca baris tabel HTML yang tersedia dan
akan menolak update jika tidak menemukan data yang cukup. Aplikasi tidak akan
menganggap halaman kosong sebagai update sukses.

Jika Beydle mengirimkan shell JavaScript tanpa baris tabel, diperlukan audit
endpoint data resmi/diizinkan atau konfirmasi dari pengelola Beydle. Jangan
mengandalkan scraping yang melanggar ketentuan situs atau melewati proteksi
akses.

### Catatan fallback

`assets/data/combos_snapshot.json` dipertahankan sebagai data offline warisan
dari versi aplikasi sebelumnya. Itu bukan snapshot live Beydle. Setelah update
Beydle berhasil, data lokal akan diganti dengan data yang berhasil diparse dari
Beydle.

## Data lokal

- Inventaris pengguna tersimpan di SharedPreferences.
- Combo tersimpan secara lokal agar aplikasi tetap bisa dipakai offline.
- Update combo tidak mengubah inventaris fisik.
- Backup/pemulihan inventaris tetap tersedia.
- Parser sinkronisasi live saat ini memetakan format tiga bagian
  `Blade · Ratchet · Bit`. Saran/picker tetap dapat menampilkan combo dua bagian
  yang sudah ada di database lokal (misalnya data snapshot/manual); combo tanpa
  ratchet tidak dimasukkan ke auto-build deck siap tanding.

## Menambah alias nama part

Edit `lib/normalize.dart`, tambahkan baris di `kNameAliases`:

```dart
const Map<String, String> kNameAliases = {
  'sharkgill': 'gillshark',
  'hellsschyte': 'hellsscythe',
  'tyrannoroar': 'roartyranno',
  'croco': 'croc',
  // tambahkan di sini:
  'namabaru': 'namastandar',
};