import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets.dart';
import 'picker_screen.dart';

class DeckScreen extends StatelessWidget {
  const DeckScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Deck 3 kombo'),
            actions: [
              IconButton(
                tooltip: 'Kosongkan semua slot',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  try {
                    await state.clearAllSlots();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal mengosongkan slot: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                state.strictByName
                    ? 'Aturan: satu nama part hanya sekali per deck.'
                    : 'Aturan: part dibatasi jumlah unit di stok.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < 3; i++) _SlotCard(state: state, index: i),
              const SizedBox(height: 4),
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Susun deck terbaik otomatis'),
                onPressed: () async {
                  try {
                    final n = await state.autoFill();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(n == 0
                          ? 'Tidak ada kombo bertier yang bisa dirakit dari stok.'
                          : 'Deck tersusun: $n kombo.'),
                    ));
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal menyusun deck: $e')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Saran didasarkan pada hasil top 3 turnamen (data per '
                '${state.comboData.asOf.isEmpty ? "-" : state.comboData.asOf}), '
                'bukan win rate. Sumber: ${state.comboData.source}.',
                style: text.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.state, required this.index});
  final AppState state;
  final int index;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PickerScreen(state: state, slotIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final combo = state.slots[index];
    final text = Theme.of(context).textTheme;

    if (combo == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Slot ${index + 1}', style: text.titleMedium),
              const SizedBox(height: 4),
              const Text('Kosong'),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => _open(context),
                child: const Text('Pilih / mulai dari part'),
              ),
            ],
          ),
        ),
      );
    }

    final remaining = state.remainingExcluding(index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text('Slot ${index + 1}', style: text.titleMedium),
        ),
        ComboCard(
          combo: combo,
          remaining: remaining,
          actions: [
            Tooltip(
              message: 'Ganti kombo di slot ini',
              child: TextButton(
                onPressed: () => _open(context),
                child: const Text('Ganti'),
              ),
            ),
            Tooltip(
              message: 'Kosongkan slot ini',
              child: TextButton(
                onPressed: () async {
                  try {
                    await state.setSlot(index, null);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal mengosongkan slot: $e')),
                      );
                    }
                  }
                },
                child: const Text('Kosongkan'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}