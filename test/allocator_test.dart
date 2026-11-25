import 'package:flutter_test/flutter_test.dart';
import 'package:beyx_stok/allocator.dart';
import 'package:beyx_stok/models.dart';
import 'package:beyx_stok/normalize.dart';

Combo combo(String id, String blade, String ratchet, String bit, {String tier = 'A'}) {
  return Combo(
    id: id,
    label: '$blade $ratchet $bit',
    tier: tier,
    topCuts: 100,
    firstRate: 30,
    parts: [
      PartRef(PartKind.blade, blade),
      PartRef(PartKind.ratchet, ratchet),
      PartRef(PartKind.bit, bit),
    ],
  );
}

List<InventoryUnit> units(Map<String, int> spec) {
  // spec: 'kind|nama' -> jumlah
  final out = <InventoryUnit>[];
  var n = 0;
  spec.forEach((k, qty) {
    final parts = k.split('|');
    for (var i = 0; i < qty; i++) {
      out.add(InventoryUnit(
        id: 'u${n++}',
        kind: kindFromKey(parts[0]),
        name: parts[1],
      ));
    }
  });
  return out;
}

void main() {
  test('normalisasi dan alias', () {
    expect(normalizeName('Low Rush'), 'lowrush');
    expect(normalizeName('m-85'), normalizeName('M85'));
    expect(normalizeName('Shark Gill'), normalizeName('Gill Shark'));
    expect(normalizeName('Hells Schyte'), normalizeName('Hells Scythe'));
    expect(normalizeName('Tyranno Roar'), normalizeName('Roar Tyranno'));
    expect(normalizeName('Croco'), normalizeName('Croc'));
  });

  test('partKey menggabungkan jenis dan nama ternormalisasi', () {
    expect(partKey(PartKind.blade, 'Silver Wolf'), 'blade|silverwolf');
    expect(partKey(PartKind.ratchet, '9-60'), 'ratchet|960');
    expect(partKey(PartKind.blade, 'Shark Gill'), 'blade|gillshark');
  });

  test('part yang habis tidak disarankan lagi (per unit)', () {
    final owned = ownedCounts(units({
      'blade|Silver Wolf': 1,
      'blade|Hover Wyvern': 1,
      'ratchet|9-60': 1,
      'bit|Kick': 1,
      'bit|Free Ball': 1,
    }));
    final a = combo('a', 'Silver Wolf', '9-60', 'Free Ball');
    final b = combo('b', 'Hover Wyvern', '9-60', 'Kick');

    // Sebelum ada slot terisi, keduanya bisa dirakit.
    expect(suggest(combos: [a, b], remaining: owned).length, 2);

    // Setelah a dipakai, ratchet 9-60 habis sehingga b tidak disarankan.
    final rem = applyUse(owned, a, false);
    expect(suggest(combos: [a, b], remaining: rem).length, 0);
    final near = suggest(combos: [b], remaining: rem, maxMissing: 1);
    expect(near.single.missing.single.name, '9-60');
  });

  test('dua unit boleh dipakai dua kali, mode ketat tidak', () {
    final owned = ownedCounts(units({
      'blade|Silver Wolf': 1,
      'blade|Hover Wyvern': 1,
      'ratchet|9-60': 2,
      'bit|Kick': 1,
      'bit|Free Ball': 1,
    }));
    final a = combo('a', 'Silver Wolf', '9-60', 'Free Ball');
    final b = combo('b', 'Hover Wyvern', '9-60', 'Kick');

    final loose = applyUse(owned, a, false);
    expect(missingParts(b, loose), isEmpty);

    final strict = applyUse(owned, a, true);
    expect(missingParts(b, strict).single.name, '9-60');
  });

  test('comboScore memprioritaskan rankingScore Beydle', () {
    final beydleCombo = Combo(
      id: 'beydle-1',
      label: 'A B C',
      tier: '',
      topCuts: 100,
      firstRate: 0,
      rankingScore: 500,
      parts: [
        PartRef(PartKind.blade, 'A'),
        PartRef(PartKind.ratchet, '1-60'),
        PartRef(PartKind.bit, 'Rush'),
      ],
    );
    final legacyCombo = combo('legacy', 'A', '1-60', 'Rush', tier: 'X');

    // Beydle score 500 > legacy tier X (5000+)
    expect(comboScore(beydleCombo), 500);
    expect(comboScore(legacyCombo), greaterThan(5000));
  });

  test('suggest memfilter berdasarkan anchorKey', () {
    final owned = ownedCounts(units({
      'blade|A': 1,
      'blade|B': 1,
      'ratchet|1-60': 1,
      'ratchet|3-60': 1,
      'bit|Rush': 2,
      'bit|Hexa': 1,
    }));
    final c1 = combo('c1', 'A', '1-60', 'Rush');
    final c2 = combo('c2', 'B', '3-60', 'Hexa');

    final result = suggest(
      combos: [c1, c2],
      remaining: owned,
      anchorKey: partKey(PartKind.ratchet, '1-60'),
    );
    expect(result.map((s) => s.combo.id), ['c1']);
  });

  test('autoBuild tidak membagi part yang sama', () {
    final owned = ownedCounts(units({
      'blade|A': 1,
      'blade|B': 1,
      'blade|C': 1,
      'ratchet|1-60': 1,
      'ratchet|3-60': 1,
      'bit|Rush': 2,
      'bit|Hexa': 1,
    }));
    final c1 = combo('1', 'A', '1-60', 'Rush', tier: 'X');
    final c2 = combo('2', 'B', '1-60', 'Hexa', tier: 'S');
    final c3 = combo('3', 'C', '3-60', 'Rush', tier: 'A');
    final best = autoBuild([c1, c2, c3], owned, false);
    expect(best.map((c) => c.id).toList(), ['1', '3']);
  });

  test('autoBuild dengan mode ketat tidak memakai part yang sama dua kali', () {
    final owned = ownedCounts(units({
      'blade|A': 1,
      'blade|B': 1,
      'ratchet|1-60': 2,
      'bit|Rush': 2,
    }));
    final c1 = combo('c1', 'A', '1-60', 'Rush', tier: 'X');
    final c2 = combo('c2', 'B', '1-60', 'Rush', tier: 'S');

    // Mode longgar: 2 unit 1-60, jadi c1 dan c2 bisa dipakai.
    final loose = autoBuild([c1, c2], owned, false);
    expect(loose.length, 2);

    // Mode ketat: nama 1-60 hanya sekali, jadi hanya satu yang dipilih.
    final strict = autoBuild([c1, c2], owned, true);
    expect(strict.length, 1);
  });

  test('autoBuild mengecualikan combo tanpa ratchet', () {
    final owned = ownedCounts(units({
      'blade|A': 1,
      'ratchet|1-60': 1,
      'bit|Rush': 1,
    }));
    final incomplete = Combo(
      id: 'incomplete',
      label: 'A Rush',
      tier: 'X',
      topCuts: 100,
      firstRate: 30,
      parts: [
        PartRef(PartKind.blade, 'A'),
        PartRef(PartKind.bit, 'Rush'),
      ],
    );
    final complete = combo('complete', 'A', '1-60', 'Rush', tier: 'A');
    expect(
      autoBuild([incomplete, complete], owned, false).map((c) => c.id),
      ['complete'],
    );
  });

  test('InventoryUnit menolak ID kosong atau terlalu panjang', () {
    expect(
      () => InventoryUnit.fromJson({
        'id': '',
        'kind': 'blade',
        'name': 'Wizard Rod',
      }),
      throwsFormatException,
    );
    expect(
      () => InventoryUnit.fromJson({
        'id': List<String>.filled(65, 'x').join(),
        'kind': 'blade',
        'name': 'Wizard Rod',
      }),
      throwsFormatException,
    );
  });

  test('InventoryUnit menolak ID yang hanya berisi spasi', () {
    expect(
      () => InventoryUnit.fromJson({
        'id': '   ',
        'kind': 'blade',
        'name': 'Wizard Rod',
      }),
      throwsFormatException,
    );
  });

  test('Combo.fromJson menolak ID kosong', () {
    expect(
      () => Combo.fromJson({
        'id': '',
        'label': 'A B C',
        'parts': [
          {'kind': 'blade', 'name': 'A'},
          {'kind': 'ratchet', 'name': '1-60'},
          {'kind': 'bit', 'name': 'Rush'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('Combo.fromJson menormalkan nilai negatif', () {
    final c = Combo.fromJson({
      'id': 'c1',
      'label': 'A B C',
      'topCuts': -5,
      'firstRate': -10,
      'rankingScore': -100,
      'parts': [
        {'kind': 'blade', 'name': 'A'},
        {'kind': 'ratchet', 'name': '1-60'},
        {'kind': 'bit', 'name': 'Rush'},
      ],
    });
    expect(c.topCuts, 0);
    expect(c.firstRate, 0.0);
    expect(c.rankingScore, 0);
  });

  test('suggest tetap menampilkan combo dua bagian yang cocok dengan stok', () {
    final owned = ownedCounts(units({
      'blade|A': 1,
      'bit|Rush': 1,
    }));
    final twoPart = Combo(
      id: 'two-part',
      label: 'A Rush',
      tier: 'A',
      topCuts: 10,
      firstRate: 20,
      parts: [
        PartRef(PartKind.blade, 'A'),
        PartRef(PartKind.bit, 'Rush'),
      ],
    );

    final result = suggest(combos: [twoPart], remaining: owned);
    expect(result.map((item) => item.combo.id), ['two-part']);
    // Perkuat: pastikan tidak ada part yang hilang.
    expect(result.single.missing, isEmpty);
  });
}