import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../normalize.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.state});
  final AppState state;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  PartKind _kind = PartKind.blade;

  String _detailLabel(PartKind k) =>
      (k == PartKind.ratchet || k == PartKind.bit) ? 'Warna' : 'Kondisi (new/used)';

  String _detailSummary(List<InventoryUnit> g) {
    final c = <String, int>{};
    for (final u in g) {
      final d = u.detail.isEmpty ? '-' : u.detail;
      c[d] = (c[d] ?? 0) + 1;
    }
    return c.entries.map((e) => '${e.key} ×${e.value}').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final all = widget.state.units;
        final units = all.where((u) => u.kind == _kind).toList();
        final groups = <String, List<InventoryUnit>>{};
        for (final u in units) {
          groups.putIfAbsent(normalizeName(u.name), () => <InventoryUnit>[]).add(u);
        }
        final keys = groups.keys.toList()
          ..sort((a, b) => groups[a]!
              .first
              .name
              .toLowerCase()
              .compareTo(groups[b]!.first.name.toLowerCase()));

        return Scaffold(
          appBar: AppBar(title: const Text('Stok')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _unitDialog(context, kind: _kind),
            icon: const Icon(Icons.add),
            label: Text('Tambah ${_kind.label}'),
          ),
          body: Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  children: [
                    for (final k in PartKind.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                              '${k.label} (${all.where((u) => u.kind == k).length})'),
                          selected: _kind == k,
                          onSelected: (_) => setState(() => _kind = k),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${units.length} unit · ${groups.length} jenis',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              Expanded(
                child: units.isEmpty
                    ? const Center(child: Text('Belum ada unit untuk jenis ini.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: keys.length,
                        itemBuilder: (context, i) {
                          final g = groups[keys[i]]!;
                          return ListTile(
                            title: Text('${g.first.name} ×${g.length}'),
                            subtitle: Text(_detailSummary(g)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _groupSheet(context, keys[i]),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _groupSheet(BuildContext context, String normKey) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => ListenableBuilder(
        listenable: widget.state,
        builder: (ctx, _) {
          final g = widget.state.units
              .where((u) => u.kind == _kind && normalizeName(u.name) == normKey)
              .toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: g.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Tidak ada unit tersisa.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final u in g)
                          ListTile(
                            title: Text(u.name),
                            subtitle: Text(u.detail.isEmpty ? '-' : u.detail),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Ubah',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _unitDialog(ctx, unit: u),
                                ),
                                IconButton(
                                  tooltip: 'Hapus',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await _confirm(
                                      ctx,
                                      'Hapus unit "${u.name}"?',
                                    );
                                    if (!ok) return;
                                    try {
                                      await widget.state.removeUnit(u.id);
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Gagal menghapus unit: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _unitDialog(
    BuildContext context, {
    PartKind? kind,
    InventoryUnit? unit,
  }) async {
    final k = unit?.kind ?? kind ?? PartKind.blade;
    final nameC = TextEditingController(text: unit?.name ?? '');
    final detailC = TextEditingController(text: unit?.detail ?? '');
    final qtyC = TextEditingController(text: '1');

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(unit == null ? 'Tambah ${k.label}' : 'Ubah ${k.label}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailC,
                  decoration: InputDecoration(labelText: _detailLabel(k)),
                ),
                if (unit == null) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtyC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jumlah unit'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      );

      if (ok != true) return;
      final name = nameC.text.trim();
      final detail = detailC.text;
      final qty = int.tryParse(qtyC.text.trim()) ?? 1;
      if (name.isEmpty || name.length > 80) return;

      try {
        if (unit == null) {
          await widget.state.addUnits(k, name, detail, qty);
        } else {
          await widget.state.updateUnit(unit.id, name, detail);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan unit: $e')),
          );
        }
      }
    } finally {
      nameC.dispose();
      detailC.dispose();
      qtyC.dispose();
    }
  }
}