import '../lib/services/purchase_math.dart';

void main() {
  void check(bool condition) {
    if (!condition) throw StateError('Purchase calculation check failed');
  }

  check(packsFor(15, 10) == 2);
  check(packTotal(15, 10, 1140) == 2280);
  check(packsFor(20, 10) == 2);
  check(packTotal(1, 1, 345) == 345);
  check(quantityFormKey('Tab.') == quantityFormKey('Tablet'));
  check(strengthKey('500 mg') == strengthKey('500mg'));
  var rejected = false;
  try {
    packsFor(1, 0);
  } catch (_) {
    rejected = true;
  }
  check(rejected);
  print(
    'Purchase math checks passed: pack rounding, paisa totals, unit aliases and invalid pack rejection.',
  );
}
