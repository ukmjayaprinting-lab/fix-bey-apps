import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'allocator.dart';
import 'beydle_service.dart';
import 'models.dart';

const _kInventory = 'inventory_v1';
const _kCombos = 'combos_v1';
const _kSlots = 'slots_v1';
const _kStrict = 'strict_v1';
const _kBeydleLastUpdate = 'beydle_last_update_v1';
const _maxJsonChars = 2 * 1024 * 1024;

class AppState extends ChangeNotifier {
  List<InventoryUnit> units = [];
  ComboData comboData =
      const ComboData(source: '', asOf: '', scope: '', combos: <Combo>[]);
  final List<Combo?> slots = List<Combo?>.filled(3, null);
  bool strictByName = false;
  DateTime? beydleLastUpdate;
  bool beydleAutoUpdate = true;
  Timer? _beydleTimer;
  bool _beydleUpdating = false;
  bool get isBeydleUpdating => _beydleUpdating;

  int _comboResetGeneration = 0;
  Future<void> _comboMutationTail = Future<void>.value();
  bool _inComboMutation = false;

  late SharedPreferences _prefs;
  int _idCounter = 0;

  final BeydleService _beydle = BeydleService();

  // ------------------------------------------------------------ muat / simpan

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    final seed = await rootBundle.loadString('assets/data/inventory_seed.json');
    final invRaw = _prefs.getString(_kInventory);
    try {
      units = _parseUnits(invRaw ?? seed);
    } catch (_) {
      units = _parseUnits(seed);
    }

    final comboSeed =
        await rootBundle.loadString('assets/data/combos_snapshot.json');
    final comboRaw = _prefs.getString(_kCombos);
    try {
      comboData = ComboData.fromJson(_decodeMap(comboRaw ?? comboSeed));
    } catch (_) {
      comboData = ComboData.fromJson(_decodeMap(comboSeed));
    }

    strictByName = _prefs.getBool(_kStrict) ?? false;
    final last = _prefs.getString(_kBeydleLastUpdate);
    beydleLastUpdate = last == null ? null : DateTime.tryParse(last);
    beydleAutoUpdate = _prefs.getBool('beydle_auto_update_v1') ?? true;
    _startBeydleSchedule();
    _loadSlots();
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final v = jsonDecode(raw);
    if (v is! Map) throw const FormatException('Data bukan objek JSON.');
    return Map<String, dynamic>.from(v);
  }

  List<InventoryUnit> _parseUnits(String raw) {
    if (raw.length > _maxJsonChars) {
      throw const FormatException('Data terlalu besar.');
    }
    final v = jsonDecode(raw);
    final list = v is Map ? v['units'] : v;
    if (list is! List) {
      throw const FormatException('Data stok tidak memuat daftar "units".');
    }
    if (list.length > 5000) throw const FormatException('Terlalu banyak unit.');
    final parsed = list
        .map((e) => InventoryUnit.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final ids = <String>{};
    for (final u in parsed) {
      if (!ids.add(u.id)) throw FormatException('ID unit ganda: ${u.id}');
    }
    return parsed;
  }

  void _loadSlots() {
    final raw = _prefs.getString(_kSlots);
    if (raw == null) return;
    try {
      final v = jsonDecode(raw);
      if (v is! List) return;
      for (var i = 0; i < 3; i++) {
        if (i >= v.length || v[i] == null) {
          slots[i] = null;
          continue;
        }
        try {
          slots[i] = Combo.fromJson(Map<String, dynamic>.from(v[i] as Map));
        } catch (_) {
          slots[i] = null;
        }
      }
    } catch (_) {
      for (var i = 0; i < 3; i++) {
        slots[i] = null;
      }
    }
  }

  Future<void> _saveUnits() => _prefs.setString(
        _kInventory,
        jsonEncode({
          'format': 'beyx-stok',
          'version': 1,
          'units': units.map((u) => u.toJson()).toList(),
        }),
      );

  Future<void> _saveSlots() => _prefs.setString(
        _kSlots,
        jsonEncode(slots.map((c) => c?.toJson()).toList()),
      );

  // ------------------------------------------------------------ turunan stok

  Map<String, int> get owned => ownedCounts(units);

  Map<String, int> remainingExcluding(int? slot) {
    var rem = ownedCounts(units);
    for (var i = 0; i < slots.length; i++) {
      final c = slots[i];
      if (i != slot && c != null) rem = applyUse(rem, c, strictByName);
    }
    return rem;
  }

  // ------------------------------------------------------------ stok

  String _newId() {
    _idCounter++;
    return 'u${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  Future<void> addUnits(PartKind kind, String name, String detail, int qty) async {
    final n = qty.clamp(1, 50);
    for (var i = 0; i < n; i++) {
      units.add(InventoryUnit(
        id: _newId(),
        kind: kind,
        name: name.trim(),
        detail: detail.trim(),
      ));
    }
    await _saveUnits();
    notifyListeners();
  }

  Future<void> updateUnit(String id, String name, String detail) async {
    for (final u in units) {
      if (u.id == id) {
        u.name = name.trim();
        u.detail = detail.trim();
      }
    }
    await _saveUnits();
    notifyListeners();
  }

  Future<void> removeUnit(String id) async {
    units.removeWhere((u) => u.id == id);
    await _saveUnits();
    notifyListeners();
  }

  String exportInventoryJson() => jsonEncode({
        'format': 'beyx-stok',
        'version': 1,
        'units': units.map((u) => u.toJson()).toList(),
      });

  Future<int> importInventoryJson(String raw) async {
    final parsed = _parseUnits(raw);
    units = parsed;
    await _saveUnits();
    notifyListeners();
    return parsed.length;
  }

  Future<void> resetInventory() async {
    final seed = await rootBundle.loadString('assets/data/inventory_seed.json');
    units = _parseUnits(seed);
    await _saveUnits();
    notifyListeners();
  }

  // ------------------------------------------------------------ deck

  Future<void> setSlot(int i, Combo? c) async {
    if (i < 0 || i >= slots.length) {
      throw RangeError.range(i, 0, slots.length - 1, 'slotIndex');
    }
    slots[i] = c;
    await _saveSlots();
    notifyListeners();
  }

  Future<void> clearAllSlots() async {
    for (var i = 0; i < slots.length; i++) {
      slots[i] = null;
    }
    await _saveSlots();
    notifyListeners();
  }

  Future<int> autoFill() async {
    final best = autoBuild(comboData.combos, owned, strictByName);
    for (var i = 0; i < slots.length; i++) {
      slots[i] = i < best.length ? best[i] : null;
    }
    await _saveSlots();
    notifyListeners();
    return best.length;
  }

  void setStrict(bool v) {
    strictByName = v;
    _prefs.setBool(_kStrict, v);
    notifyListeners();
  }

  // ------------------------------------------------------------ combo mutation guard

  Future<T> _withComboMutationLock<T>(Future<T> Function() action) {
    if (_inComboMutation) {
      throw StateError('Nested _withComboMutationLock tidak diizinkan.');
    }
    final completer = Completer<T>();
    _comboMutationTail = _comboMutationTail.then((_) async {
      _inComboMutation = true;
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _inComboMutation = false;
      }
    });
    return completer.future;
  }

  // ------------------------------------------------------------ Beydle sync

  void setBeydleAutoUpdate(bool enabled) {
    beydleAutoUpdate = enabled;
    _prefs.setBool('beydle_auto_update_v1', enabled);
    if (enabled) {
      _startBeydleSchedule();
    } else {
      _beydleTimer?.cancel();
      _beydleTimer = null;
    }
    notifyListeners();
  }

  void _startBeydleSchedule() {
    _beydleTimer?.cancel();
    if (!beydleAutoUpdate) return;
    _beydleTimer = Timer.periodic(const Duration(hours: 24), (_) {
      unawaited(autoUpdateBeydleIfDue());
    });
    unawaited(autoUpdateBeydleIfDue());
  }

  Future<void> autoUpdateBeydleIfDue() async {
    if (!beydleAutoUpdate || _beydleUpdating) return;
    final last = beydleLastUpdate;
    if (last == null || DateTime.now().difference(last) >= const Duration(hours: 24)) {
      try {
        await updateBeydle();
      } catch (_) {
        // Update otomatis gagal tidak mengganggu pemakaian data lokal.
      }
    }
  }

  Future<String> updateBeydle() async {
    if (_beydleUpdating) {
      throw const FormatException('Pembaruan Beydle sedang berlangsung.');
    }

    final requestGeneration = _comboResetGeneration;
    _beydleUpdating = true;
    notifyListeners();
    try {
      final data = await _beydle.fetchAllTime();

      if (data.combos.length < 10) {
        throw const FormatException(
          'Data yang terbaca terlalu sedikit; database lama tidak diubah.',
        );
      }

      return await _withComboMutationLock<String>(() async {
        if (requestGeneration != _comboResetGeneration) {
          throw const BeydleUpdateCancelled();
        }

        final raw = jsonEncode({
          'format': 'beyx-kombo',
          'version': 1,
          'source': data.source,
          'asOf': data.asOf,
          'scope': data.scope,
          'combos': data.combos.map((c) => c.toJson()).toList(),
        });

        await _prefs.setString(_kCombos, raw);
        comboData = data;
        beydleLastUpdate = DateTime.now();
        await _prefs.setString(
          _kBeydleLastUpdate,
          beydleLastUpdate!.toIso8601String(),
        );
        notifyListeners();
        return '${data.combos.length} combo Beydle berhasil diperbarui.';
      });
    } finally {
      _beydleUpdating = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ data kombo

  Future<String> importComboJson(String raw) async {
    if (raw.length > _maxJsonChars) {
      throw const FormatException('Data terlalu besar.');
    }
    final data = ComboData.fromJson(_decodeMap(raw));
    await _prefs.setString(_kCombos, raw);
    comboData = data;
    notifyListeners();
    return '${data.combos.length} kombo dimuat (sumber: ${data.source}, per ${data.asOf}).';
  }

  Future<void> resetCombos() async {
    final resetGeneration = ++_comboResetGeneration;

    final seed =
        await rootBundle.loadString('assets/data/combos_snapshot.json');
    final seedData = ComboData.fromJson(_decodeMap(seed));

    await _withComboMutationLock<void>(() async {
      if (resetGeneration != _comboResetGeneration) return;

      await _prefs.remove(_kCombos);
      await _prefs.remove(_kBeydleLastUpdate);
      comboData = seedData;
      beydleLastUpdate = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _beydleTimer?.cancel();
    _beydleTimer = null;
    _beydle.close();
    super.dispose();
  }
}