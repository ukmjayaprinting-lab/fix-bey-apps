import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'models.dart';

/// Konektor eksperimental untuk halaman ranking Beydle.
/// Menggunakan periode all-time. Tidak menganggap halaman JS shell sebagai data valid.
class BeydleService {
  static final Uri combosUri =
      Uri.parse('https://beydle.com/meta/combos?period=all');

  /// Batas jumlah baris yang diparse, sama dengan batas ComboData.
  static const int _maxCombos = 5000;

  final http.Client _client = http.Client();

  Future<http.Response> _requestWithRetry() async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(
              combosUri,
              headers: const {
                'Accept': 'text/html,application/xhtml+xml',
                'User-Agent': 'BeyXStok/1.1 (Android)',
              },
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode >= 500 && attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        return response;
      } on SocketException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (lastError != null) throw lastError;
    throw HttpException(
      'Permintaan ke Beydle gagal setelah dicoba ulang.',
      uri: combosUri,
    );
  }

  void close() => _client.close();

  Future<ComboData> fetchAllTime() async {
    final response = await _requestWithRetry();

    if (response.statusCode != 200) {
      throw HttpException(
        'Beydle mengembalikan HTTP ${response.statusCode}.',
        uri: combosUri,
      );
    }
    if (response.bodyBytes.length > 8 * 1024 * 1024) {
      throw const FormatException('Halaman Beydle melebihi batas 8 MB.');
    }
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.isNotEmpty &&
        !contentType.contains('text/html') &&
        !contentType.contains('application/xhtml+xml')) {
      throw FormatException(
        'Format respons Beydle tidak didukung ($contentType). '
        'Parser saat ini membutuhkan HTML; data lokal tidak diubah.',
      );
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final combos = _parseHtmlRows(body);
    if (combos.isEmpty) {
      throw const FormatException(
        'Data combo tidak ditemukan pada HTML yang diterima. '
        'Beydle kemungkinan memuat tabel melalui JavaScript/API. '
        'Database lama tetap aman; endpoint data perlu diaudit lebih lanjut.',
      );
    }

    return ComboData(
      source: 'Beydle (all-time WBO podium rankings)',
      // asOf adalah waktu fetch, bukan tanggal pembaruan data Beydle.
      // Beydle tidak menyediakan metadata tanggal pada HTML yang diparse.
      asOf: DateTime.now().toUtc().toIso8601String(),
      scope: 'Seluruh baris combo yang tersedia pada HTML periode all-time; '
          'skor podium 3×juara 1 + 2×juara 2 + 1×juara 3. '
          'Ini bukan win rate. Tanggal asOf adalah waktu fetch, bukan '
          'tanggal pembaruan data Beydle.',
      combos: combos,
    );
  }

  List<Combo> _parseHtmlRows(String source) {
    final doc = html_parser.parse(source);
    final rows = doc.querySelectorAll('tr');
    final out = <Combo>[];
    final seen = <String>{};

    for (final row in rows) {
      if (out.length >= _maxCombos) break;
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;
      final text = cells.map((e) => e.text.trim())
          .where((e) => e.isNotEmpty).join(' ');
      final combo = _parseRow(text);
      if (combo == null || !seen.add(combo.id)) continue;
      out.add(combo);
    }
    return out;
  }

  Combo? _parseRow(String text) {
    if (text.isEmpty || text.length > 500) return null;

    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final match = RegExp(
      r'^(?:#?\d+[.)]?\s+)?(.+?)\s+(\d{1,7})\s+(\d{1,7})\s+(\d{1,7})\s+(\d{1,7})\s+(\d{1,7})\s*$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final label = match.group(1)!.trim();
    final first = int.parse(match.group(2)!);
    final second = int.parse(match.group(3)!);
    final third = int.parse(match.group(4)!);
    final podiumTotal = int.parse(match.group(5)!);
    final score = int.parse(match.group(6)!);
    if (first + second + third <= 0 || podiumTotal <= 0 || score <= 0) {
      return null;
    }
    final expectedScore = 3 * first + 2 * second + third;
    if ((score - expectedScore).abs() > 1) return null;

    // Parser saat ini hanya memetakan tiga bagian: Blade · Ratchet · Bit.
    // Jika Beydle menambahkan bagian ke-4, baris akan tetap diparse dengan
    // tiga bagian pertama. Validasi bentuk ratchet sengaja tidak dilakukan
    // sampai format live terverifikasi.
    final names = label
        .split(RegExp(r'\s*[·•]\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (names.length < 3) return null;

    final parts = <PartRef>[
      PartRef(PartKind.blade, names[0]),
      PartRef(PartKind.ratchet, names[1]),
      PartRef(PartKind.bit, names[2]),
    ];
    final id = 'beydle_${_slug(label)}';
    return Combo(
      id: id,
      label: label,
      tier: '',
      topCuts: first + second + third,
      firstRate: 0,
      rankingScore: score,
      parts: parts,
      note: 'Beydle podium: 🥇$first 🥈$second 🥉$third; '
          'score ${3 * first + 2 * second + third}. '
          'Bukan win rate pertandingan.',
    );
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}