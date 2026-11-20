class UnitNeed {
  const UnitNeed(this.id, this.requested, this.unitMinor, {this.label = ''});
  final String id, label;
  final int requested, unitMinor;
}

/// Give every priced medicine one unit when possible, then allocate by
/// share of remaining need. Prices are conservative integer-paisa estimates.
Map<String, int> allocateUnits(List<UnitNeed> needs, int budget) {
  final eligible = needs
      .where((n) => n.requested > 0 && n.unitMinor > 0)
      .toList();
  final result = <String, int>{for (final n in needs) n.id: 0};
  var remaining = budget < 0 ? 0 : budget;
  final cheapest = [...eligible]
    ..sort((a, b) {
      final cmp = a.unitMinor.compareTo(b.unitMinor);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
  for (final n in cheapest) {
    if (n.unitMinor > remaining) break;
    result[n.id] = 1;
    remaining -= n.unitMinor;
  }

  // A common fraction of each remaining need is allocated in bulk.
  const scale = 100000;
  int extra(UnitNeed n, int fraction) =>
      (n.requested - result[n.id]!) * fraction ~/ scale;
  var lo = 0, hi = scale;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    final cost = eligible.fold<int>(
      0,
      (total, n) => total + n.unitMinor * extra(n, mid),
    );
    if (cost <= remaining) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  for (final n in eligible) {
    final units = extra(n, lo);
    result[n.id] = result[n.id]! + units;
    remaining -= units * n.unitMinor;
  }

  // Spend the rounding remainder on the least-covered lines first.
  final remainder = [...eligible]
    ..sort((a, b) {
      final fraction = (result[a.id]! * b.requested).compareTo(
        result[b.id]! * a.requested,
      );
      return fraction != 0 ? fraction : a.unitMinor.compareTo(b.unitMinor);
    });
  for (final n in remainder) {
    if (result[n.id]! < n.requested && remaining >= n.unitMinor) {
      result[n.id] = result[n.id]! + 1;
      remaining -= n.unitMinor;
    }
  }
  // Put any residual that cannot raise the common coverage toward
  // affordable remaining lines instead of leaving it unallocated.
  for (final n in remainder) {
    final count = result[n.id]!;
    final open = n.requested - count;
    final affordable = remaining ~/ n.unitMinor;
    final units = affordable < open ? affordable : open;
    result[n.id] = count + units;
    remaining -= units * n.unitMinor;
  }
  return result;
}

int? estimatedUnitMinor(int? packMinor, int? unitsPerPack) {
  if (packMinor == null ||
      unitsPerPack == null ||
      packMinor <= 0 ||
      unitsPerPack <= 0)
    return null;
  return (packMinor + unitsPerPack - 1) ~/ unitsPerPack;
}
