import 'package:flutter/material.dart';

import 'models.dart';

String comboMeta(Combo c) {
  if (c.rankingScore > 0) {
    return 'Beydle score ${c.rankingScore} · ${c.topCuts} podium';
  }
  if (c.topCuts == 0 && c.tier.isEmpty) return 'Susunan manual';
  final tier = c.tier.isEmpty ? 'belum bertier (<60 top cut)' : 'Tier ${c.tier}';
  final rate = c.firstRate > 0
      ? ' · 1st rate ${c.firstRate.toStringAsFixed(1)}%'
      : '';
  return '$tier · ${c.topCuts} top cut$rate';
}

/// Kartu kombo. Part yang tidak tersedia di [remaining] diberi tanda.
class ComboCard extends StatelessWidget {
  const ComboCard({
    super.key,
    required this.combo,
    required this.remaining,
    this.onTap,
    this.actions = const <Widget>[],
  });

  final Combo combo;
  final Map<String, int> remaining;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final rows = combo.parts.map((p) {
      final ok = (remaining[p.key] ?? 0) >= 1;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 16,
              color: ok ? scheme.primary : scheme.error,
              semanticLabel: ok ? 'Tersedia' : 'Tidak tersedia',
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${p.kind.label}: ${p.name}${ok ? '' : ' (tidak tersedia)'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                combo.label,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(comboMeta(combo), style: text.bodySmall),
              const SizedBox(height: 6),
              ...rows,
              if (combo.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    combo.note,
                    style: text.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (actions.isNotEmpty)
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}