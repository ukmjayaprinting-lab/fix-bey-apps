import 'package:flutter/material.dart';

import '../allocator.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';

class PickerScreen extends StatefulWidget {
  const PickerScreen({super.key, required this.state, required this.slotIndex});
  final AppState state;
  final int slotIndex;

  @override
  State<PickerScreen> createState() => _PickerScreenState();
}

class _AnchorOption {
  const _AnchorOption(this.key, this.name, this.count);
  final String key;
  final String name;
  final int count;
}

class _PickerScreenState extends State<PickerScreen> {
  PartKind? _kind;
  String? _anchorKey;

  static const _startKinds = <PartKind>[
    PartKind.blade,
    PartKind.lockChip,
    PartKind.overBlade,
    PartKind.mainBlade,
    PartKind.assist,
    PartKind.ratchet,
    PartKind.bit,
  ];

  /// Part yang masih tersedia untuk jenis [k], satu entri per nama.
  List<_AnchorOption> _options(PartKind k, Map<String, int> remaining) {
    final seen = <String>{};
    final out = <_AnchorOption>[];
    for (final u in widget.state.units) {
      if (u.kind != k) continue;
      final key = partKey(k, u.name);
      final count = remaining[key] ?? 0;
      if (count < 1 || !seen.add(key)) continue;
      out.add(_AnchorOption(key, u.name, count));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<void> _choose(Combo c) async {
    try {
      await widget.state.setSlot(widget.slotIndex, c);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan slot: $e')),
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _manual(Map<String, int> remaining) async {
    var custom = false;
    String? error;
    final chosen = <PartKind, String?>{};

    final result = await showDialog<Combo>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final kinds = custom
              ? <PartKind>[
                  PartKind.lockChip,
                  PartKind.mainBlade,
                  PartKind.overBlade,
                  PartKind.assist,
                  PartKind.ratchet,
                  PartKind.bit,
                ]
              : <PartKind>[PartKind.blade, PartKind.ratchet, PartKind.bit];

          return AlertDialog(
            title: const Text('Susun manual'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('Blade standar')),
                      ButtonSegment<bool>(value: true, label: Text('Custom Line')),
                    ],
                    selected: {custom},
                    onSelectionChanged: (s) => setD(() {
                      custom = s.first;
                      chosen.clear();
                      error = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  for (final k in kinds)
                    DropdownButton<String>(
                      isExpanded: true,
                      hint: Text(k == PartKind.overBlade
                          ? '${k.label} (opsional)'
                          : k.label),
                      value: chosen[k],
                      items: _options(k, remaining)
                          .map((o) => DropdownMenuItem<String>(
                                value: o.name,
                                child: Text(o.name),
                              ))
                          .toList(),
                      onChanged: (v) => setD(() => chosen[k] = v),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  final missingRequired = kinds.any(
                      (k) => k != PartKind.overBlade && chosen[k] == null);
                  if (missingRequired) {
                    setD(() => error = 'Lengkapi semua part (Over Blade boleh kosong).');
                    return;
                  }
                  final parts = <PartRef>[
                    for (final k in kinds)
                      if (chosen[k] != null) PartRef(k, chosen[k]!),
                  ];
                  Navigator.pop(
                    ctx,
                    Combo(
                      id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                      label: parts.map((p) => p.name).join(' '),
                      tier: '',
                      topCuts: 0,
                      firstRate: 0,
                      parts: parts,
                      note: 'Susunan manual (tanpa data turnamen).',
                    ),
                  );
                },
                child: const Text('Pakai'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && mounted) {
      await _choose(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final remaining = state.remainingExcluding(widget.slotIndex);
    final text = Theme.of(context).textTheme;

    // Panggil suggest sekali dengan maxMissing: 1, lalu pisahkan hasilnya.
    final allSuggestions = suggest(
      combos: state.comboData.combos,
      remaining: remaining,
      anchorKey: _anchorKey,
      maxMissing: 1,
    );
    final fits = allSuggestions.where((s) => s.missing.isEmpty).toList();
    final near = allSuggestions
        .where((s) => s.missing.length == 1)
        .take(15)
        .toList();

    final options = _kind == null ? <_AnchorOption>[] : _options(_kind!, remaining);

    return Scaffold(
      appBar: AppBar(title: Text('Slot ${widget.slotIndex + 1}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Mulai dari part (opsional)', style: text.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final k in _startKinds)
                ChoiceChip(
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: (sel) => setState(() {
                    _kind = sel ? k : null;
                    _anchorKey = null;
                  }),
                ),
            ],
          ),
          if (_kind != null) ...[
            const SizedBox(height: 8),
            if (options.isEmpty)
              Text('Tidak ada ${_kind!.label} yang tersedia.', style: text.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final o in options)
                    ChoiceChip(
                      label: Text('${o.name} ×${o.count}'),
                      selected: _anchorKey == o.key,
                      onSelected: (sel) => setState(() => _anchorKey = sel ? o.key : null),
                    ),
                ],
              ),
          ],
          const SizedBox(height: 12),
          Text('Bisa dirakit dari stok (${fits.length})', style: text.titleSmall),
          const SizedBox(height: 4),
          if (fits.isEmpty)
            Text(
              _anchorKey == null
                  ? 'Tidak ada kombo bertier yang bisa dirakit dari sisa stok.'
                  : 'Part ini tidak muncul di kombo bertier yang bisa dirakit. '
                      'Gunakan "Susun manual".',
              style: text.bodySmall,
            ),
          for (final s in fits)
            ComboCard(
              combo: s.combo,
              remaining: remaining,
              onTap: () async {
                await _choose(s.combo);
              },
            ),
          if (near.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Kurang 1 part (${near.length})', style: text.titleSmall),
            const SizedBox(height: 4),
            for (final s in near) ComboCard(combo: s.combo, remaining: remaining),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.tune),
            label: const Text('Susun manual'),
            onPressed: () => _manual(remaining),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}