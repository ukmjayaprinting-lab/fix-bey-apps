# Perubahan integrasi Beydle

- Sumber online diubah menjadi Beydle `/meta/combos?period=all` saja.
- Ditambahkan service fetch + parser HTML tabel ranking.
- Ditambahkan tombol Update Sekarang dan sakelar update otomatis.
- Auto-check saat startup bila data berumur >= 24 jam; timer 24 jam selama aplikasi aktif.
- Ditambahkan `rankingScore` agar urutan rekomendasi menggunakan skor podium Beydle.
- Penyimpanan dilakukan setelah validasi; kegagalan tidak menimpa data lokal.
- Snapshot lama dipertahankan sebagai fallback offline dan diberi label legacy.

## Status validasi

- Pemeriksaan struktur YAML, JSON seed, dan keseimbangan delimiter source: lulus.
- Flutter/Dart SDK tidak tersedia di lingkungan penyusunan awal. Build pertama
  dijalankan melalui GitHub Actions (lihat `.github/workflows/build-apk.yml`).
  `flutter pub get`, `flutter analyze`, `flutter test`, dan `flutter build apk`
  belum dijalankan di lingkungan penyusunan.
- Endpoint data dinamis Beydle belum terverifikasi. Parser hanya menerima data
  yang benar-benar tersedia sebagai baris tabel HTML; bila situs mengirim shell
  JavaScript saja, update akan gagal dengan pesan yang jelas dan data lama tetap
  aman.
- Update otomatis bekerja saat aplikasi dibuka dan selama aplikasi aktif; belum
  dijadwalkan sebagai proses Android background ketika aplikasi ditutup.

## Perbaikan audit — 25 November 2026

### Bug prioritas tinggi
- Timer 24 jam sekarang memanggil `autoUpdateBeydleIfDue()` sehingga update
  terjadwal tidak memunculkan exception ketika proses update lain sedang
  berlangsung.
- Pemulihan slot deck dilakukan per-slot; satu data slot yang rusak tidak
  mengosongkan slot lain yang masih valid.
- `InventoryUnit.fromJson` menolak ID kosong dan ID lebih dari 64 karakter.
- Metadata combo Beydle menampilkan `Beydle score` dan jumlah podium, bukan
  `1st rate 0.0%`.

### Perbaikan tambahan
- Pesan error membedakan format data, timeout, jaringan, dan HTTP.
- Parser menerima prefix ranking `1`, `#1`, `1.` dan `1)`.
- Baris HTML tanpa elemen `<td>` diabaikan.
- Parser menolak skor yang tidak konsisten dengan rumus podium (toleransi satu
  poin): `3 × juara 1 + 2 × juara 2 + juara 3`.
- Konektor memeriksa Content-Type, melakukan satu kali retry untuk
  timeout/gangguan jaringan dan respons server 5xx, serta mengelola HTTP Client
  agar dapat ditutup.
- Auto-build hanya memilih combo yang memiliki ratchet; combo tanpa ratchet
  tidak dianggap deck siap tanding.
- Timer dibatalkan dan HTTP Client ditutup saat `AppState` di-dispose.
- Reset database combo juga menghapus waktu sinkronisasi terakhir.
- Operasi tambah, ubah, hapus, dan impor inventaris menunggu penyimpanan
  SharedPreferences selesai.

### Catatan yang sengaja tidak diubah
- `combos_snapshot.json` memiliki `asOf: 2026-11-17`, yang bukan tanggal masa
  depan terhadap tanggal audit 2026-11-25. Nilai dipertahankan karena tidak ada
  bukti bahwa tanggal tersebut salah.
- Parser tetap eksperimental karena struktur HTML/endpoint Beydle belum diuji
  dengan respons live yang dapat diverifikasi.
- Auto-update 24 jam masih berjalan saat aplikasi aktif dan saat startup; bukan
  Android background worker ketika aplikasi ditutup.
- APK release workflow masih menggunakan konfigurasi signing default
  Flutter/debug. APK dapat diuji/sideload, tetapi belum disiapkan untuk
  publikasi Play Store.

### Validasi pada lingkungan penyusunan
- Flutter/Dart SDK tidak tersedia di lingkungan ini; `flutter pub get`,
  `flutter analyze`, `flutter test`, dan `flutter build apk` belum dapat
  dijalankan di sini.
- Unit test tambahan ditambahkan untuk validasi ID inventaris dan pengecualian
  combo tanpa ratchet.
- Pemeriksaan sintaks/struktur statis dilakukan; build GitHub Actions tetap harus
  dijalankan setelah ZIP ini diunggah.

## Patch — Reset combo tidak memicu sinkronisasi (25 November 2026)

Patch ini hanya menyentuh `AppState` dan tidak menyentuh `picker_screen.dart`
maupun `deck_screen.dart`. Perubahan pada kedua file screen tersebut dilakukan di
"Review lanjutan" di bawah, bukan di patch reset combo ini.

- `resetCombos()` kini hanya memulihkan snapshot bawaan dan menghapus metadata
  waktu update terakhir.
- Pemanggilan auto-update langsung setelah reset dihapus.
- Permintaan update Beydle yang dimulai sebelum reset dibatalkan secara logis
  melalui generation token.
- Commit perubahan database combo diserialisasi agar reset terbaru menjadi hasil
  akhir dan hasil fetch lama tidak menimpa snapshot.
- Jika reset terjadi saat fetch sedang berlangsung, hasil fetch tersebut ditolak
  dengan pesan pembatalan yang jelas.

## Review lanjutan berdasarkan catatan akhir (25 November 2026)

- Menambahkan `BeydleUpdateCancelled` agar pembatalan karena reset tidak
  ditampilkan sebagai kesalahan format.
- UI membedakan pembatalan reset dari kegagalan fetch; pesan tidak lagi
  menyatakan data lama tetap dipakai ketika reset telah menggantinya dengan
  snapshot.
- `BeydleService` kini menjadi instance per `AppState`, sehingga `dispose()`
  tidak menutup client milik instance lain.
- `setSlot`, `clearAllSlots`, dan `autoFill` menjadi operasi async dan menunggu
  penyimpanan slot selesai; pemanggil pada picker/deck ikut menunggu.
- Tombol update manual nonaktif selama update sedang berlangsung, memakai getter
  `isBeydleUpdating`.
- Konfirmasi pemulihan data combo menjelaskan bahwa waktu sinkronisasi terakhir
  dihapus dan reset tidak memulai update otomatis.
- README diperjelas: parser live memetakan format tiga bagian, sedangkan
  picker/suggest tetap dapat menampilkan combo dua bagian yang sudah ada di
  database; auto-build tetap mengecualikan combo tanpa ratchet.
- Ditambahkan unit test agar `suggest` tetap menampilkan combo dua bagian yang
  cocok dengan stok, sekaligus memastikan tidak ada part yang hilang.
- Ditambahkan komentar larangan pemanggilan nested pada `_withComboMutationLock`,
  dan guard runtime `StateError` agar nested call gagal cepat, bukan deadlock.
  Guard `_inComboMutation` hanya bernilai true di dalam lock, sehingga tidak ada
  false-positive untuk pemanggilan concurrent.
- `RangeError.index` diganti `RangeError.range` pada `setSlot` agar pesan error
  lebih jelas.
- `picker_screen.dart`: `_choose` sekarang menangani error `setSlot` dan
  mengecek `mounted` sebelum `Navigator.pop`; `_manual` menunggu `_choose`;
  `onTap` memakai block body async.
- `deck_screen.dart`: semua `onPressed` async memakai block body dan `try/catch`
  dengan pesan SnackBar.
- `data_screen.dart`: `FormatException` "sedang berlangsung" ditangani terpisah
  dari kegagalan fetch biasa.

## Koreksi workflow GitHub Actions (25 November 2026)

- Workflow dikembalikan ke `actions/checkout@v4`, `actions/setup-java@v4`, dan
  `actions/upload-artifact@v4`.
- Klaim sebelumnya bahwa `actions/setup-java@v6` tersedia **tidak akurat**.
  Rilis resmi `actions/setup-java` saat audit ini adalah `v4`; menulis `@v6`
  akan menggagalkan workflow dengan "Unable to resolve action".
- `actions/checkout@v5` dan `actions/upload-artifact@v5` sebenarnya sudah
  tersedia, tetapi dipilih `@v4` untuk konsistensi dan menghindari risiko.