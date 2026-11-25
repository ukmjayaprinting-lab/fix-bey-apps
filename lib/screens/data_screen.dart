import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key, required this.state});
  final AppState state;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String message) async {
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

  Future<String?> _pasteDialog(String title) async {
    final c = TextEditingController();
    try {
      final r = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Tempel JSON di sini'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Proses'),
            ),
          ],
        ),
      );
      return r;
    } finally {
      c.dispose();
    }
  }

  Future<void> _fetchBeydleUpdate() async {
    setState(() => _busy = true);
    try {
      _toast(await widget.state.updateBeydle());
    } on BeydleUpdateCancelled catch (e) {
      _toast(errText(e));
    } on FormatException catch (e) {
      if (e.message.contains('sedang berlangsung')) {
        _toast('Update sedang berlangsung. Tunggu sebentar.');
      } else {
        _toast('Update gagal; data lama tetap digunakan. ${e.message}');
      }
    } catch (e) {
      _toast(
        'Update Beydle gagal; data yang sedang tersimpan tetap digunakan. ${errText(e)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importCombos() async {
    final raw = await _pasteDialog('Impor data kombo');
    if (raw == null || raw.trim().isEmpty) return;
    try {
      _toast(await widget.state.importComboJson(raw));
    } catch (e) {
      _toast('Impor gagal, data lama tetap dipakai. ${errText(e)}');
    }
  }

  Future<void> _importInventory() async {
    final raw = await _pasteDialog('Pulihkan stok dari cadangan');
    if (raw == null || raw.trim().isEmpty) return;
    if (!await _confirm('Stok saat ini akan diganti seluruhnya. Lanjutkan?')) {
      return;
    }
    try {
      final n = await widget.state.importInventoryJson(raw);
      _toast('$n unit dimuat.');
    } catch (e) {
      _toast('Impor gagal, stok lama tetap utuh. ${errText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        final d = s.comboData;
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Data & pengaturan')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: SwitchListTile(
                  title: const Text('Satu nama part hanya sekali per deck'),
                  subtitle: const Text(
                    'Mati: part dibatasi jumlah unit stok. Aktif: walau punya 2 unit, '
                    'nama part yang sama tidak dipakai di dua kombo. Aturan resmi '
                    'turnamen berbeda antar-ruleset; periksa sebelum bertanding.',
                  ),
                  value: s.strictByName,
                  onChanged: s.setStrict,
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Data kombo turnamen', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text('Sumber: ${d.source}'),
                      Text('Per tanggal: ${d.asOf.isEmpty ? "-" : d.asOf}'),
                      Text('Cakupan: ${d.scope.isEmpty ? "-" : d.scope}'),
                      Text('Jumlah combo: ${d.combos.length}'),
                      Text(
                        'Update terakhir: ${s.beydleLastUpdate?.toLocal().toString() ?? "Belum pernah"}',
                      ),
                      if (d.source.startsWith('Legacy offline'))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Perhatian: data yang sedang dipakai adalah snapshot offline versi lama, '
                            'belum merupakan hasil sinkronisasi Beydle.',
                            style: text.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Sumber tunggal: Beydle all-time. Statistik berdasarkan podium WBO '
                        '(juara 1/2/3), bukan win rate pertandingan. Update otomatis diperiksa '
                        'saat aplikasi dibuka dan setiap 24 jam selama aplikasi aktif.',
                        style: text.bodySmall,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Update otomatis Beydle'),
                        subtitle: const Text(
                          'Periksa data terbaru maksimal setiap 24 jam.',
                        ),
                        value: s.beydleAutoUpdate,
                        onChanged: s.setBeydleAutoUpdate,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (_busy || s.isBeydleUpdating)
                              ? null
                              : _fetchBeydleUpdate,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(
                            (_busy || s.isBeydleUpdating)
                                ? 'Mengambil data Beydle…'
                                : 'Update Sekarang dari Beydle',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _importCombos,
                            child: const Text('Impor JSON cadangan'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              if (!await _confirm(
                                'Kembali ke data combo bawaan? Data combo tersimpan akan diganti dengan snapshot bawaan dan waktu sinkronisasi terakhir akan dihapus. Reset tidak akan memulai update otomatis.',
                              )) {
                                return;
                              }
                              await s.resetCombos();
                              _toast('Data combo dikembalikan ke bawaan.');
                            },
                            child: const Text('Data bawaan'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cadangan stok', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${s.units.length} unit tersimpan di perangkat ini.',
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: s.exportInventoryJson()),
                              );
                              _toast('Cadangan disalin ke clipboard.');
                            },
                            child: const Text('Salin cadangan'),
                          ),
                          OutlinedButton(
                            onPressed: _importInventory,
                            child: const Text('Pulihkan dari cadangan'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              if (!await _confirm(
                                'Kembalikan stok ke data awal? Perubahan Anda akan hilang.',
                              )) {
                                return;
                              }
                              await s.resetInventory();
                              _toast('Stok dikembalikan ke data awal.');
                            },
                            child: const Text('Reset ke data awal'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nama part yang tidak dikenali tidak akan cocok dengan data turnamen. '
                'Tambahkan alias di lib/normalize.dart bila perlu.',
                style: text.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}