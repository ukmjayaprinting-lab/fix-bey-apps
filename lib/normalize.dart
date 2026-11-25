/// Alias nama yang berbeda antara penulisan pengguna / Takara Tomy / Hasbro / situs.
/// Kunci dan nilai memakai bentuk ringkas (huruf kecil, tanpa spasi dan tanda baca).
///
/// Cara menambah alias:
/// 1. Cari nama part yang tidak cocok saat aplikasi dijalankan.
/// 2. Lihat bentuk ringkasnya: huruf kecil, tanpa spasi/tanda baca.
///    Contoh: "Shark Gill" -> "sharkgill", "Hells Scythe" -> "hellsscythe".
/// 3. Tambahkan baris: 'bentukyangtidakcocok': 'bentukstandar',
/// 4. Jalankan ulang aplikasi.
///
/// Contoh yang sudah ada:
/// - Shark Gill = Gill Shark
/// - Hells Schyte = Hells Scythe
/// - Tyranno Roar = Roar Tyranno
/// - Croco = Croc
const Map<String, String> kNameAliases = {
  'sharkgill': 'gillshark',
  'hellsschyte': 'hellsscythe',
  'tyrannoroar': 'roartyranno',
  'croco': 'croc',
};

/// Bentuk ringkas nama part untuk pencocokan:
/// "Low Rush" -> "lowrush", "M-85" -> "m85", "9-60" -> "960".
String normalizeName(String raw) {
  final compact = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return kNameAliases[compact] ?? compact;
}