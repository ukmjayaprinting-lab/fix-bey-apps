import 'models.dart';

/// Jumlah unit per kunci part (jenis|nama ternormalisasi).
Map<String, int> ownedCounts(Iterable<InventoryUnit> units) {
  final m = <String, int>{};
  for (final u in units) {
    final k = partKey(u.kind, u.name);
    m[k] = (m[k] ?? 0) + 1;
  }
  return m;
}

/// Sisa stok setelah sebuah kombo dipakai.
/// Mode biasa: tiap part mengurangi 1 unit.
/// Mode ketat (strictByName): nama part yang sudah dipakai tidak tersedia lagi,
/// walaupun masih ada unit lain.
Map<String, int> applyUse(Map<String, int> remaining, Combo c, bool strictByName) {
  final res = Map<String, int>.from(remaining);
  for (final p in c.parts) {
    final k = p.key;
    res[k] = strictByName ? 0 : (res[k] ?? 0) - 1;
  }
  return res;
}

List<PartRef> missingParts(Combo c, Map<String, int> remaining) =>
    c.parts.where((p) => (remaining[p.key] ?? 0) < 1).toList();

int tierWeight(String t) {
  switch (t) {
    case 'X':
      return 5;
    case 'S':
      return 4;
    case 'A':
      return 3;
    case 'B':
      return 2;
    case 'C':
      return 1;
    default:
      return 0;
  }
}

/// Skor urutan: rankingScore Beydle dulu, lalu tier, 1st rate, top cut.
///
/// Catatan desain: jika `rankingScore > 0`, skor Beydle dipakai apa adanya
/// tanpa offset. Kombo Beydle dengan skor kecil bisa kalah dari kombo legacy
/// tier X (skor ~5000). Jika ingin kombo Beydle selalu di atas, tambahkan
/// offset tetap, misalnya `10000 + rankingScore`.
double comboScore(Combo c) {
  if (c.rankingScore > 0) return c.rankingScore.toDouble();
  return tierWeight(c.tier) * 1000 +
      c.firstRate * 10 +
      (c.topCuts > 1000 ? 1000 : c.topCuts) / 1000.0;
}

class Suggestion {
  const Suggestion(this.combo, this.missing);
  final Combo combo;
  final List<PartRef> missing;
}

/// Saran kombo yang bisa dirakit dari sisa stok.
///
/// [maxMissing] = 0 hanya kombo yang seluruh part-nya tersedia;
/// [maxMissing] = 1 termasuk kombo yang kurang tepat satu part.
///
/// Tidak ada batas jumlah hasil. Pemanggil (mis. picker_screen) yang perlu
/// membatasi jumlah tampilan.
List<Suggestion> suggest({
  required List<Combo> combos,
  required Map<String, int> remaining,
  String? anchorKey,
  int maxMissing = 0,
}) {
  final out = <Suggestion>[];
  for (final c in combos) {
    if (anchorKey != null && !c.parts.any((p) => p.key == anchorKey)) continue;
    final miss = missingParts(c, remaining);
    if (miss.length <= maxMissing) out.add(Suggestion(c, miss));
  }
  out.sort((a, b) {
    final byMissing = a.missing.length.compareTo(b.missing.length);
    if (byMissing != 0) return byMissing;
    return comboScore(b.combo).compareTo(comboScore(a.combo));
  });
  return out;
}

/// Mencari sampai 3 kombo tanpa rebutan part dengan total skor tertinggi.
///
/// Combo tanpa ratchet dikecualikan agar tidak dianggap deck siap tanding.
///
/// Catatan performa: DFS ini O(n^3) untuk n kandidat. Untuk stok realistis
/// (< 100 kombo cocok), masih cepat. Jika kandidat sangat banyak, pertimbangkan
/// membatasi `cand` ke 50 teratas sebelum DFS.
List<Combo> autoBuild(List<Combo> combos, Map<String, int> owned, bool strictByName) {
  final cand = combos
      .where((c) =>
          c.parts.any((p) => p.kind == PartKind.ratchet) &&
          missingParts(c, owned).isEmpty)
      .toList()
    ..sort((a, b) => comboScore(b).compareTo(comboScore(a)));

  var best = <Combo>[];
  var bestScore = -1.0;

  void dfs(int start, List<Combo> chosen, Map<String, int> rem, double sc) {
    if (chosen.length > best.length ||
        (chosen.length == best.length && sc > bestScore)) {
      best = List<Combo>.from(chosen);
      bestScore = sc;
    }
    if (chosen.length == 3) return;
    for (var i = start; i < cand.length; i++) {
      final c = cand[i];
      if (missingParts(c, rem).isNotEmpty) continue;
      chosen.add(c);
      dfs(i + 1, chosen, applyUse(rem, c, strictByName), sc + comboScore(c));
      chosen.removeLast();
    }
  }

  dfs(0, <Combo>[], owned, 0);
  return best;
}