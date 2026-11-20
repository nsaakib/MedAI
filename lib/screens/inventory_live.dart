import '../localization.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import 'medicine_setup.dart';

class InventoryCard extends StatefulWidget {
  const InventoryCard({super.key, required this.medicineId});
  final String medicineId;
  @override
  State<InventoryCard> createState() => _InventoryCardState();
}

class _InventoryCardState extends State<InventoryCard> {
  bool busy = false;
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    final m = s.medicines.where((m) => m.id == widget.medicineId).firstOrNull;
    if (m == null) return const SizedBox.shrink();
    return Tile(
      outlined: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Course and supply'),
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          gap(7),
          small(
            tr('Course total: ${m.quantity} · Units logged: ${m.unitsTaken}'),
          ),
          small(tr('Still needed for course: ${m.remainingCourse}')),
          small(
            tr(
              'On hand: ${m.stockUnits ?? 'not tracked'} · To buy: ${m.neededToBuy}',
            ),
          ),
          if (m.lowStock) Pill(tr('Low supply'), color: Colors.orange),
          Wrap(
            spacing: 6,
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => record(c, s, 'purchase'),
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(tr('Record purchase')),
              ),
              TextButton(
                onPressed: busy || !m.verified
                    ? null
                    : () => record(c, s, 'dose'),
                child: Text(tr('Log dose taken')),
              ),
              TextButton(
                onPressed: busy ? null : () => record(c, s, 'stock'),
                child: Text(tr('Set on hand')),
              ),
              TextButton(
                onPressed: busy ? null : () => record(c, s, 'threshold'),
                child: Text(tr('Refill level')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> record(BuildContext c, AppState s, String change) async {
    final current = s.medicines
        .where((m) => m.id == widget.medicineId)
        .firstOrNull;
    if (current == null || busy) return;
    setState(() => busy = true);
    try {
      final isDose = change == 'dose';
      final units = await askUnits(
        c,
        switch (change) {
          'purchase' => 'Record units purchased',
          'dose' => 'Log the dose you actually took',
          'threshold' => 'Low supply threshold',
          _ => 'Set units on hand',
        },
        isDose
            ? 'Individual units actually taken'
            : 'Individual units, not packs',
        min: change == 'stock' || change == 'threshold' ? 0 : 1,
        initial: isDose
            ? current.confirmedDoseUnits
            : change == 'threshold'
            ? current.lowStockLevel
            : change == 'stock'
            ? current.stockUnits
            : null,
      );
      if (units == null || !mounted || !s.signedIn) return;
      final m = s.medicines.where((m) => m.id == widget.medicineId).firstOrNull;
      if (m == null || (isDose && !m.verified)) return;
      if (isDose && (s.doses.length >= 5000 || units + m.unitsTaken > 100000)) {
        throw StateError('This record has reached its logging limit.');
      }
      final previousLow = m.lowStock;
      final previousStock = m.stockUnits;
      final previousTaken = m.unitsTaken;
      final previousThreshold = m.refillThreshold;
      final dose = <String, dynamic>{
        'id': identifier(),
        'medicine_id': m.id,
        'logged_at': DateTime.now().toUtc().toIso8601String(),
        'units': units,
      };
      switch (change) {
        case 'purchase':
          if (units + (m.stockUnits ?? 0) > 100000)
            throw StateError('Stock limit is 100,000 units.');
          m.stockUnits = units + (m.stockUnits ?? 0);
          break;
        case 'stock':
          m.stockUnits = units;
          break;
        case 'threshold':
          m.refillThreshold = units;
          break;
        case 'dose':
          if (m.stockUnits != null)
            m.stockUnits = max(0, m.stockUnits! - units);
          m.unitsTaken += units;
          s.doses.add(dose);
          break;
      }
      try {
        await s.commit();
      } catch (_) {
        m.stockUnits = previousStock;
        m.unitsTaken = previousTaken;
        m.refillThreshold = previousThreshold;
        if (isDose) s.doses.remove(dose);
        rethrow;
      }
      if (!previousLow && m.lowStock) {
        try {
          final sent = await s.notification.refillAlert(m.id);
          if (!sent && c.mounted) {
            ScaffoldMessenger.of(c).showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    'Supply is low. Enable notifications for refill reminders.',
                  ),
                ),
              ),
            );
          }
        } catch (_) {
          if (c.mounted)
            ScaffoldMessenger.of(c).showSnackBar(
              SnackBar(
                content: Text(
                  tr('Supply is low. Notification could not be displayed.'),
                ),
              ),
            );
        }
      }
    } catch (e) {
      if (c.mounted) message(c, tr('Could not update supply'), tr('$e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
