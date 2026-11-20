import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/services/purchase_math.dart';
import 'package:med_ai/services/reminders.dart';

void main() {
  test('whole-pack purchase cost differs from prescribed unit count', () {
    final m = Medicine(
      name: 'Synthetic example',
      quantity: 15,
      unitPrice: 114,
      verified: true,
      productMatchConfirmed: true,
      quoteId: 'q1',
      priceQuote: {
        'units_per_pack': 10,
        'pack_price_minor': 1140,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      },
      quantityUnit: 'Tablet',
    );
    expect(m.total, 1710);
    expect(m.purchaseTotal, 2280);
    final copy = Medicine.fromJson(m.toJson());
    expect(copy.quantity, 15);
    expect(copy.purchaseTotal, 2280);
    expect(copy.quantityUnit, 'Tablet');
    copy.purchased = true;
    expect(copy.purchaseTotal, 0);
    copy.purchased = false;
    copy.priceQuote!['expires_at'] = 0;
    expect(copy.hasPrice, isFalse);
    expect(copy.purchaseTotal, 0);
  });
  test('legacy records with no new purchase fields remain readable', () {
    final legacy = Medicine(
      name: 'Legacy',
      quantity: 10,
      unitPrice: 250,
    ).toJson();
    for (final key in [
      'purchased',
      'quantity_unit',
      'price_quote',
      'quote_id',
      'product_match_confirmed',
      'price_confirmed',
    ]) {
      legacy.remove(key);
    }
    final copy = Medicine.fromJson(legacy);
    expect(copy.purchased, isFalse);
    expect(copy.priceConfirmed, isTrue);
    expect(copy.total, 2500);
  });
  test('stable alarm IDs do not depend on reminder ordering', () {
    final first = ReminderService.notificationId('first-reminder');
    final second = ReminderService.notificationId('second-reminder');
    expect(first, isNot(second));
    expect(first, ReminderService.notificationId('first-reminder'));
    expect(first, greaterThanOrEqualTo(0));
  });
  test('no pack calculator accepts an unknown pack size', () {
    expect(() => packsFor(10, 0), throwsArgumentError);
  });
}
