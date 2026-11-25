import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'normalize.dart';

enum PartKind { blade, lockChip, overBlade, mainBlade, assist, ratchet, bit, launcher }

extension PartKindX on PartKind {
  String get label => switch (this) {
        PartKind.blade => 'Blade',
        PartKind.lockChip => 'Lock Chip',
        PartKind.overBlade => 'Over Blade',
        PartKind.mainBlade => 'Main Blade',
        PartKind.assist => 'Assist Blade',
        PartKind.ratchet => 'Ratchet',
        PartKind.bit => 'Bit',
        PartKind.launcher => 'Launcher',
      };
}

PartKind kindFromKey(String s) {
  for (final k in PartKind.values) {
    if (k.name == s) return k;
  }
  throw FormatException('Jenis part tidak dikenal: $s');
}

String partKey(PartKind kind, String name) => '${kind.name}|${normalizeName(name)}';

class PartRef {
  const PartRef(this.kind, this.name);
  final PartKind kind;
  final String name;

  String get key => partKey(kind, name);

  factory PartRef.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] as String).trim();
    if (name.isEmpty || name.length > 80) {
      throw const FormatException('Nama part kosong atau terlalu panjang.');
    }
    return PartRef(kindFromKey(j['kind'] as String), name);
  }

  Map<String, dynamic> toJson() => {'kind': kind.name, 'name': name};
}

class InventoryUnit {
  InventoryUnit({
    required this.id,
    required this.kind,
    required this.name,
    this.detail = '',
  });

  final String id;
  final PartKind kind;
  String name;
  String detail;

  factory InventoryUnit.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] as String).trim();
    if (name.isEmpty || name.length > 80) {
      throw const FormatException('Nama unit kosong atau terlalu panjang.');
    }
    final id = (j['id'] as String).trim();
    if (id.isEmpty || id.length > 64) {
      throw const FormatException('ID unit tidak valid.');
    }
    return InventoryUnit(
      id: id,
      kind: kindFromKey(j['kind'] as String),
      name: name,
      detail: ((j['detail'] ?? '') as String).trim(),
    );
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'kind': kind.name, 'name': name, 'detail': detail};
}

class Combo {
  const Combo({
    required this.id,
    required this.label,
    required this.tier,
    required this.topCuts,
    required this.firstRate,
    required this.parts,
    this.note = '',
    this.rankingScore = 0,
  });

  final String id;
  final String label;
  final String tier;
  final int topCuts;
  final double firstRate;
  final List<PartRef> parts;
  final String note;
  final int rankingScore;

  factory Combo.fromJson(Map<String, dynamic> j) {
    final raw = j['parts'];
    if (raw is! List || raw.isEmpty || raw.length > 8) {
      throw const FormatException('Daftar part kombo tidak valid.');
    }
    final id = (j['id'] as String).trim();
    if (id.isEmpty || id.length > 128) {
      throw const FormatException('ID kombo tidak valid.');
    }
    final label = (j['label'] as String).trim();
    if (label.isEmpty || label.length > 200) {
      throw const FormatException('Label kombo terlalu panjang atau kosong.');
    }
    final tcRaw = (j['topCuts'] as num?)?.toInt() ?? 0;
    final frRaw = (j['firstRate'] as num?)?.toDouble() ?? 0.0;
    final rsRaw = (j['rankingScore'] as num?)?.toInt() ?? 0;
    return Combo(
      id: id,
      label: label,
      tier: ((j['tier'] ?? '') as String),
      topCuts: tcRaw < 0 ? 0 : tcRaw,
      firstRate: (frRaw.isFinite && frRaw >= 0 && frRaw <= 100) ? frRaw : 0.0,
      parts: raw
          .map((e) => PartRef.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      note: ((j['note'] ?? '') as String),
      rankingScore: rsRaw < 0 ? 0 : rsRaw,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'tier': tier,
        'topCuts': topCuts,
        'firstRate': firstRate,
        'note': note,
        'rankingScore': rankingScore,
        'parts': parts.map((p) => p.toJson()).toList(),
      };
}

class ComboData {
  const ComboData({
    required this.source,
    required this.asOf,
    required this.scope,
    required this.combos,
  });

  final String source;
  final String asOf;
  final String scope;
  final List<Combo> combos;

  factory ComboData.fromJson(Map<String, dynamic> j) {
    final list = j['combos'];
    if (list is! List) {
      throw const FormatException('Data kombo tidak memuat daftar "combos".');
    }
    if (list.isEmpty) throw const FormatException('Daftar kombo kosong.');
    if (list.length > 5000) throw const FormatException('Terlalu banyak kombo.');
    return ComboData(
      source: ((j['source'] ?? 'tidak disebutkan') as String),
      asOf: ((j['asOf'] ?? '') as String),
      scope: ((j['scope'] ?? '') as String),
      combos: list
          .map((e) => Combo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class BeydleUpdateCancelled implements Exception {
  const BeydleUpdateCancelled([
    this.message = 'Pembaruan dibatalkan karena database combo telah di-reset.',
  ]);
  final String message;

  @override
  String toString() => message;
}

String errText(Object e) {
  if (e is BeydleUpdateCancelled) return e.message;
  if (e is FormatException) return e.message;
  if (e is TimeoutException) {
    return 'Koneksi ke server melewati batas waktu. Coba lagi.';
  }
  if (e is SocketException) {
    return 'Tidak dapat terhubung ke internet. Periksa koneksi Anda.';
  }
  if (e is http.ClientException) {
    return 'Koneksi HTTP gagal: ${e.message}';
  }
  if (e is HttpException) {
    return 'Terjadi masalah komunikasi HTTP: ${e.message}';
  }
  return 'Terjadi kesalahan yang tidak terduga. Coba lagi.';
}