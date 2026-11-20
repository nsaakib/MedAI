import '../localization.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import '../services/unit_budget.dart';
import '../motion.dart';
import 'bulk_prices.dart';
import 'arogga_cart.dart';
import 'workspace.dart';

enum PurchaseStep { prices, total, budget, result, quantities, basket }

class PurchaseFlowLive extends StatefulWidget {
  const PurchaseFlowLive({super.key, required this.step});
  final PurchaseStep step;
  @override
  State<PurchaseFlowLive> createState() => _PurchaseFlowLiveState();
}

class _PurchaseFlowLiveState extends State<PurchaseFlowLive> {
  final budgetInput = TextEditingController(),
      deliveryInput = TextEditingController();
  final form = GlobalKey<FormState>();
  Map<String, dynamic>? plan;
  bool busy = true, started = false, acceptIncomplete = false;
  String? error, priceProgress;
  int loadedVersion = -1;
  List<Map<String, dynamic>> get rows => (plan?['rows'] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  bool get full => widget.step.index <= PurchaseStep.budget.index;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Scope.of(context);
    if (!started) {
      started = true;
      budgetInput.text = s.budgetSet ? (s.budget / 100).toStringAsFixed(2) : '';
      deliveryInput.text = (s.delivery / 100).toStringAsFixed(2);
      Future.microtask(load);
    } else if (!busy && error == null && loadedVersion != s.version) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !busy && error == null) load();
      });
    }
  }

  @override
  void dispose() {
    budgetInput.dispose();
    deliveryInput.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final s = Scope.of(context);
      final p = await s.purchasePlan(fullCost: full);
      if (mounted)
        setState(() {
          plan = p;
          loadedVersion = s.version;
          acceptIncomplete = false;
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final titles = [
      'Medicine Prices',
      'Full Prescription Cost',
      'Set Your Budget',
      'Budget Result',
      'Quantities Within Budget',
      'Review Budget Basket',
    ];
    return AppFrame(
      back: true,
      title: tr(titles[widget.step.index]),
      subtitle: tr(
        'Purchase estimate · BDT · prescribed instructions stay unchanged.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Scope.of(c).needsSignIn || Scope.of(c).conflict)
            const SyncStatus(),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: MedLoader(label: 'Updating your estimate…')),
            ),
          if (busy && priceProgress != null) small(tr(priceProgress!)),
          if (error != null) ...[
            note(
              tr(
                Scope.of(c).needsSignIn
                    ? 'Sign in again to fetch medicine prices and prepare your cart. Your saved medicine list is kept on this device.'
                    : error!,
              ),
            ),
            TextButton(onPressed: busy ? null : load, child: Text(tr('Retry'))),
          ],
          if (!busy && widget.step == PurchaseStep.budget) ...budgetForm(c),
          if (!busy && error != null && widget.step != PurchaseStep.budget)
            TextButton(
              onPressed: () => go(c, 'budget'),
              child: Text(tr('Set My Budget')),
            ),
          if (!busy &&
              error == null &&
              plan != null &&
              widget.step != PurchaseStep.budget) ...[
            if (rows.isEmpty) ...[
              note(tr('Create your medicine list first.'), color: blue),
              ActionButton(
                tr('Add Medicine Manually'),
                onTap: () => go(c, 'medicine'),
              ),
              gap(12),
              ActionButton(tr('Scan Prescription'), onTap: () => go(c, 'add')),
            ] else
              ...switch (widget.step) {
                PurchaseStep.prices => priceSummary(c),
                PurchaseStep.total => totalCost(c),
                PurchaseStep.budget => budgetForm(c),
                PurchaseStep.result => result(c),
                PurchaseStep.quantities => quantities(c),
                PurchaseStep.basket => basket(c),
              },
          ],
        ],
      ),
    );
  }

  Future<void> batchPrices(BuildContext c) async {
    if (busy) return;
    final s = Scope.of(c);
    setState(() {
      busy = true;
      priceProgress = 'Checking Arogga…';
    });
    try {
      final summary = await updateAllPrices(c, s, (status) {
        if (mounted) setState(() => priceProgress = status);
      });
      if (mounted && summary != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(summary))));
      }
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          priceProgress = null;
        });
    }
  }

  Future<void> confirmMedicine(String id) async {
    final s = Scope.of(context);
    final m = s.medicines.where((m) => m.id == id).firstOrNull;
    if (m == null || busy) return;
    final original = jsonEncode(m.toJson());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Review medicine for purchase')),
        content: SingleChildScrollView(
          child: Text(
            tr(
              'Compare these details with your prescription or medicine list. Confirm only if they are correct.\n\n'
              'Medicine: ${m.name}\nStrength: ${m.strength}\nForm: ${m.form}\n'
              'Purchase quantity: ${m.quantity} ${m.quantityUnit}\n'
              'Frequency: ${m.frequency}\nMeal: ${m.meal}\nDuration: ${m.duration}\n'
              'Route: ${m.route}\nInstructions: ${m.instruction}\n\n'
              'Confirmation records your review. It is not pharmacist approval and does not change dosing.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Details correct — include')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final current = s.medicines.where((m) => m.id == id).firstOrNull;
    if (current == null || jsonEncode(current.toJson()) != original) {
      setState(
        () => error = 'Medicine details changed during review. Review the latest details again.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      current.verified = true;
      if (!current.purchased) s.selectedIds.add(id);
      await s.commit();
      await load();
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          busy = false;
        });
    }
  }

  Widget amount(String label, int? value, {bool big = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(tr(label), style: TextStyle(fontSize: big ? 14 : 12)),
        ),
        Flexible(
          child: Text(
            tr(value == null ? 'Not complete' : money(value)),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: big ? 24 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  Widget missingNotice() => note(
    tr(
      'An estimate is incomplete while a medicine has no confirmed price. Unknown prices are never treated as free.',
    ),
  );

  List<Widget> priceSummary(BuildContext c) {
    final s = Scope.of(c);
    return [
      for (final row in rows)
        Builder(
          builder: (c) {
            final m = s.medicines.firstWhere((m) => m.id == row['medicine_id']);
            final q = row['quote'] as Map?;
            return Tile(
              outlined: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Bubble(Icons.medication_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr('${m.name} ${m.strength}'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Edit prescription details'),
                        onPressed: () => go(c, 'medicine', arguments: m.id),
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 19,
                          color: blue,
                        ),
                      ),
                    ],
                  ),
                  gap(10),
                  small(
                    tr(
                      '${m.quantity} course units · ${m.neededToBuy} to buy · ${m.form}',
                    ),
                  ),
                  if (m.stockUnits == null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr('Already purchased'),
                        style: TextStyle(fontSize: 12),
                      ),
                      value: m.purchased,
                      onChanged: busy
                          ? null
                          : (v) async {
                              setState(() => busy = true);
                              m.purchased = v;
                              if (v) s.selectedIds.remove(m.id);
                              try {
                                await s.commit();
                                await load();
                              } catch (e) {
                                if (mounted)
                                  setState(() {
                                    error = '$e';
                                    busy = false;
                                  });
                              }
                            },
                    ),
                  if (m.neededToBuy > 0) ...[
                    amount('Purchase estimate', row['line_total_minor']),
                    if (q != null) ...[
                      small(
                        tr(
                          '৳${q['unit_price_bdt']} per unit · ${q['pack_label']}',
                        ),
                      ),
                      small(
                        tr(
                          '${row['packs']} pack(s) · ${row['supplied_units']} units supplied\nArogga · ${q['available'] == true ? 'Listed in stock' : 'Listed unavailable'}',
                        ),
                      ),
                    ] else
                      small(
                        tr(
                          m.priceConfirmed
                              ? 'Your entered unit price · ${money(m.unitPrice)}'
                              : 'Match an exact product to fetch its current price.',
                        ),
                      ),
                    if (row['reason'] != 'Included')
                      small(
                        tr(row['reason']),
                        color: row['line_total_minor'] == null
                            ? Colors.orange
                            : muted,
                      ),
                  ] else
                    Pill(tr('No additional purchase needed'), color: mint),
                ],
              ),
            );
          },
        ),
      if ((plan!['unpriced_count'] as int) > 0) missingNotice(),
      Tile(
        outlined: false,
        color: soft,
        child: amount(
          'Known total + delivery reserve',
          plan!['known_full_total_minor'],
          big: true,
        ),
      ),
      ActionButton(
        tr('Update All Online Prices'),
        icon: Icons.price_check,
        onTap: () => batchPrices(c),
      ),
      gap(10),
      ActionButton(tr('View Total'), onTap: () => go(c, 'total-cost')),
      gap(12),
      TextButton(
        onPressed: () => go(c, 'reminders'),
        child: Text(tr('Already have your medicines? Set alarms →')),
      ),
    ];
  }

  List<Widget> totalCost(BuildContext c) => [
    Tile(
      outlined: false,
      child: Column(
        children: [
          const Bubble(Icons.shopping_cart_outlined, size: 58),
          gap(12),
          amount(
            'Full purchase estimate',
            plan!['full_total_minor'],
            big: true,
          ),
          amount(
            'Known medicine cost',
            (plan!['known_full_total_minor'] as int) -
                (plan!['delivery_reserve_minor'] as int),
          ),
          amount('Delivery reserve', plan!['delivery_reserve_minor']),
          small(
            tr(
              'Delivery is a reserve you enter, not a supplier shipping quote. Final charges are shown on Arogga.',
            ),
          ),
        ],
      ),
    ),
    if ((plan!['unpriced_count'] as int) > 0) missingNotice(),
    note(
      tr(
        'Prices include whole sales packs. Any extra units are packaging surplus, not an instruction to take more medicine.',
      ),
      color: blue,
    ),
    ActionButton(
      tr('Use Full Estimate'),
      onTap: plan!['full_total_minor'] == null
          ? null
          : () => useBudget(c, false),
    ),
    gap(12),
    ActionButton(
      tr('Set My Budget'),
      icon: Icons.account_balance_wallet_outlined,
      onTap: () => go(c, 'budget'),
    ),
    gap(12),
    TextButton(
      onPressed: () => go(c, 'pharmacies'),
      child: Text(tr('Buy in person · Find nearby pharmacies')),
    ),
  ];

  List<Widget> budgetForm(BuildContext c) => [
    Tile(
      outlined: false,
      child: Form(
        key: form,
        child: Column(
          children: [
            TextFormField(
              controller: budgetInput,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: tr('Total budget (BDT, including delivery)'),
              ),
              validator: amountValid,
            ),
            gap(14),
            TextFormField(
              controller: deliveryInput,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: tr('Delivery reserve (BDT)'),
              ),
              validator: (v) =>
                  tr(amountValid(v) ??
                  ((minorAmount(v ?? '') ?? 0) > 10000000
                      ? 'Delivery reserve is too large'
                      : null)),
            ),
            gap(12),
            small(
              tr(
                'The reserve is not a live delivery quote. Change it when the supplier shows the actual fee.',
              ),
            ),
          ],
        ),
      ),
    ),
    Tile(
      outlined: false,
      color: soft,
      child: amount(
        'Full purchase estimate',
        plan?['full_total_minor'],
        big: true,
      ),
    ),
    if ((plan?['unpriced_count'] as int? ?? 0) > 0) missingNotice(),
    note(
      tr(
        'See how many individual units fit your budget, then check separately what Arogga can supply in packs.',
      ),
    ),
    ActionButton(
      tr('Calculate Budget'),
      icon: Icons.calculate_outlined,
      onTap: () => useBudget(c, true),
    ),
  ];

  Future<void> useBudget(BuildContext c, bool custom) async {
    if (custom && !(form.currentState?.validate() ?? false)) return;
    final s = Scope.of(c);
    setState(() => busy = true);
    try {
      s.budgetSet = custom;
      if (custom) {
        s.budget = minorAmount(budgetInput.text)!;
        s.delivery = minorAmount(deliveryInput.text)!;
      }
      await s.commit();
      if (s.needsSignIn) {
        throw StateError(
          'Budget saved on this device. Sign in again to calculate prices and prepare the cart.',
        );
      }
      final next = await s.purchasePlan(automatic: true);
      s.selectedIds
        ..clear()
        ..addAll(
          (next['rows'] as List)
              .where((r) => r['included'] == true)
              .map<String>((r) => r['medicine_id'] as String),
        );
      await s.commit();
      if (c.mounted) go(c, custom ? 'budget-result' : 'quantities');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Widget> individualEstimate(BuildContext c, int budget) {
    final state = Scope.of(c);
    final delivery = plan!['delivery_reserve_minor'] as int? ?? 0;
    final priced = <UnitNeed>[];
    final unavailable = <String>[];
    for (final row in rows) {
      final units =
          row['purchase_units'] as int? ?? row['prescribed_units'] as int? ?? 0;
      if (units <= 0) continue;
      final id = row['medicine_id'] as String;
      final label = [
        row['name'],
        row['strength'],
      ].whereType<String>().join(' ').trim();
      final med = state.medicines.where((m) => m.id == id).firstOrNull;
      final quote = row['quote'];
      final price = quote is Map
          ? estimatedUnitMinor(
              quote['pack_price_minor'] as int?,
              quote['units_per_pack'] as int?,
            )
          : med != null && med.priceConfirmed && med.quoteId == null
          ? med.unitPrice
          : null;
      if (med?.verified != true || price == null || price <= 0) {
        unavailable.add(
          '$label — ${med?.verified != true ? 'review prescription' : 'no verified unit price'}',
        );
        continue;
      }
      priced.add(UnitNeed(id, units, price, label: label));
    }
    final selected = allocateUnits(priced, budget - delivery);
    final subtotal = priced.fold<int>(
      0,
      (sum, m) => sum + m.unitMinor * selected[m.id]!,
    );
    final total = subtotal > 0 ? subtotal + delivery : 0;
    return [
      Heading(tr('Individual-unit budget estimate')),
      note(
        tr(
          'A cost estimate for a pharmacy that sells individual units. It is not an Arogga order or a change to your prescription. Confirm availability and ask your pharmacist about any shortfall.',
        ),
        color: blue,
      ),
      if (priced.isEmpty)
        Text(
          tr(
            'Review medicines and get a verified price to calculate quantities.',
          ),
        ),
      for (final m in priced)
        Tile(
          outlined: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(m.label),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              small(
                tr(
                  '${selected[m.id]} of ${m.requested} units · ${money(m.unitMinor)} per unit',
                ),
              ),
              if (selected[m.id] == 0)
                small(tr('Not affordable in this estimate.'))
              else
                Text(tr(money(m.unitMinor * selected[m.id]!))),
            ],
          ),
        ),
      for (final label in unavailable) small(tr(label)),
      Tile(
        outlined: false,
        color: soft,
        child: Column(
          children: [
            amount('Individual-unit subtotal', subtotal),
            amount('Delivery reserve included', subtotal > 0 ? delivery : 0),
            amount('Estimated total', total, big: true),
            amount('Budget remaining', budget - total),
          ],
        ),
      ),
      Heading(tr('Arogga pack estimate')),
    ];
  }

  List<Widget> result(BuildContext c) {
    final total = plan!['full_total_minor'] as int?;
    final budget = plan!['budget_minor'] as int?;
    return [
      if ((plan!['delivery_shortfall_minor'] as int? ?? 0) > 0)
        note(
          tr(
            'Budget is below the delivery reserve. No medicine purchase fits until the budget or reserve is adjusted.',
          ),
        ),
      if (budget != null) ...individualEstimate(c, budget),
      Tile(
        outlined: false,
        child: Column(
          children: [
            amount('Your budget', budget, big: true),
            amount('Full purchase estimate', total, big: true),
            if (plan!['shortfall_minor'] != null)
              amount(
                'Additional amount for full list',
                plan!['shortfall_minor'],
              ),
          ],
        ),
      ),
      if (total != null && total > 0 && budget != null) ...[
        Heading(tr('Budget progress')),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            minHeight: 12,
            value: (budget / total).clamp(0.0, 1.0),
          ),
        ),
        gap(15),
      ],
      Tile(
        outlined: false,
        child: Column(
          children: [
            amount('Delivery reserve', plan!['delivery_reserve_minor']),
            amount('Selected medicine cost', plan!['selected_subtotal_minor']),
            amount('Selected total', plan!['selected_total_minor'], big: true),
          ],
        ),
      ),
      if (plan!['incomplete'] == true)
        note(
          tr(
            'Your current basket does not include every medicine you still need. Review exclusions with a pharmacist; your prescription remains unchanged.',
          ),
        ),
      ActionButton(
        tr('Review Arogga Pack Quantities'),
        onTap: () => go(c, 'quantities'),
      ),
    ];
  }

  List<Widget> quantities(BuildContext c) {
    final s = Scope.of(c);
    return [
      if ((plan!['delivery_shortfall_minor'] as int? ?? 0) > 0) ...[
        note(
          tr(
            'Your total budget is below the delivery reserve. Available for medicines: ৳0. Adjust your budget or delivery reserve.',
          ),
        ),
        TextButton(
          onPressed: () => go(c, 'budget'),
          child: Text(tr('Adjust budget / delivery')),
        ),
      ],
      for (final row in rows)
        Tile(
          outlined: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('${row['name']} ${row['strength']}'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: small(
                  tr('${row['prescribed_units']} prescribed units'),
                ),
                value: row['included'] == true,
                onChanged:
                    row['review_required'] == true ||
                        row['reason'] == 'Already purchased' ||
                        row['line_total_minor'] == null
                    ? null
                    : (v) async {
                        setState(() => busy = true);
                        if (v == true)
                          s.selectedIds.add(row['medicine_id']);
                        else
                          s.selectedIds.remove(row['medicine_id']);
                        try {
                          await s.commit();
                          await load();
                        } catch (e) {
                          if (mounted)
                            setState(() {
                              error = '$e';
                              busy = false;
                            });
                        }
                      },
              ),
              Pill(
                tr(
                  row['included'] == true
                      ? 'Included'
                      : row['reason'] == 'Already purchased'
                      ? 'Already purchased'
                      : 'Not Included',
                ),
                color: row['included'] == true ? mint : muted,
              ),
              gap(8),
              amount('Remaining purchase quantity', row['line_total_minor']),
              if (row['quote'] != null)
                small(
                  tr(
                    'Buy ${row['packs']} whole pack(s) · ${row['supplied_units']} units supplied',
                  ),
                ),
              if (row['affordable_units'] != null)
                small(
                  tr(
                    'Individually affordable: ${row['affordable_units']} / ${row['purchase_units'] ?? row['prescribed_units']} units to buy. Cost comparison only.',
                  ),
                ),
              if (row['included'] != true)
                small(tr(row['reason']), color: muted),
              if (row['review_required'] == true)
                TextButton(
                  onPressed: () =>
                      confirmMedicine(row['medicine_id'] as String),
                  child: Text(tr('Confirm medicine details & include')),
                ),
              if (row['review_required'] == true)
                TextButton(
                  onPressed: () async {
                    await Navigator.of(c)
                        .pushNamed('/medicine', arguments: row['medicine_id']);
                    if (mounted) await load();
                  },
                  child: Text(tr('Review medicine to enable purchase')),
                ),
            ],
          ),
        ),
      Tile(
        outlined: false,
        color: soft,
        child: Column(
          children: [
            amount('Selected medicines', plan!['selected_subtotal_minor']),
            amount('Delivery charged for this basket', plan!['delivery_minor']),
            amount(
              'Configured delivery reserve',
              plan!['delivery_reserve_minor'],
            ),
            amount('Total', plan!['selected_total_minor'], big: true),
            if (plan!['remaining_minor'] != null)
              amount('Budget remaining', plan!['remaining_minor']),
          ],
        ),
      ),
      note(
        tr(
          'Only complete prescribed quantities are selected automatically. Individual affordability is not a dosing recommendation.',
        ),
      ),
      ActionButton(tr('Review Selections'), onTap: () => go(c, 'basket')),
    ];
  }

  List<Widget> basket(BuildContext c) => [
    if (plan!['cart_ready'] != true)
      note(
        tr(
          'Cart preparation needs at least one selected, reviewed medicine with a current exact product price, within your budget. Use Review Quantities to resolve the reason shown for each excluded item.',
        ),
      ),
    TextButton(
      onPressed: () => go(c, 'quantities'),
      child: Text(tr('Review quantities and medicine details')),
    ),
    for (final included in [true, false]) ...[
      Heading(tr(included ? 'Included' : 'Not Included')),
      for (final r in rows.where((r) => (r['included'] == true) == included))
        Tile(
          outlined: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('${r['name']} ${r['strength']}'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              gap(6),
              small(
                tr(
                  '${r['prescribed_units']} prescribed units · ${r['reason']}',
                ),
              ),
              if (r['review_required'] == true)
                TextButton(
                  onPressed: () => confirmMedicine(r['medicine_id'] as String),
                  child: Text(tr('Confirm medicine details & include')),
                ),
              if (r['line_total_minor'] != null)
                amount('Estimate', r['line_total_minor']),
              if (r['included'] == true && r['cart_eligible'] != true)
                small(
                  tr(
                    'An exact, current Arogga product match is required for cart assistance.',
                  ),
                  color: Colors.orange,
                ),
            ],
          ),
        ),
    ],
    Tile(
      outlined: false,
      color: soft,
      child: Column(
        children: [
          amount('Medicines', plan!['selected_subtotal_minor']),
          amount('Delivery charged for this basket', plan!['delivery_minor']),
          amount(
            'Configured delivery reserve',
            plan!['delivery_reserve_minor'],
          ),
          amount('Basket total', plan!['selected_total_minor'], big: true),
        ],
      ),
    ),
    if (plan!['incomplete'] == true) ...[
      note(
        tr(
          'Incomplete prescription basket. Review excluded items with your pharmacist.',
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: acceptIncomplete,
        onChanged: (v) => setState(() => acceptIncomplete = v ?? false),
        title: Text(
          tr(
            'I understand which medicines are excluded. This does not mark their details as reviewed or change my prescription.',
          ),
          style: TextStyle(fontSize: 12),
        ),
      ),
    ],
    if (plan!['duplicate_products'] == true)
      note(
        tr(
          'The same supplier product is matched to more than one medicine entry. Review duplicate entries before using the cart assistant.',
        ),
      ),
    ActionButton(
      tr('Prepare Cart on Arogga'),
      icon: Icons.shopping_cart_outlined,
      onTap:
          plan!['cart_ready'] != true ||
              plan!['incomplete'] == true && !acceptIncomplete
          ? null
          : () => openCart(c),
    ),
    gap(12),
    ActionButton(
      tr('Buy at a Nearby Pharmacy'),
      icon: Icons.local_pharmacy_outlined,
      onTap: () => go(c, 'pharmacies'),
    ),
    gap(10),
    TextButton(
      onPressed: () => go(c, 'budget'),
      child: Text(tr('Adjust budget')),
    ),
    small(
      tr(
        'The assistant works in your on-device Arogga session. You review the cart, handle login/prescription verification and complete payment manually.',
      ),
    ),
  ];

  Future<void> openCart(BuildContext c) async {
    setState(() => busy = true);
    try {
      final fresh = await Scope.of(c).purchasePlan();
      String signature(Map<String, dynamic> p) => jsonEncode(
        (p['rows'] as List)
            .where((r) => r['included'] == true)
            .map(
              (r) => [
                r['medicine_id'],
                r['line_total_minor'],
                r['packs'],
                r['quote']?['quote_id'],
              ],
            )
            .toList(),
      );
      if (signature(fresh) != signature(plan!) || fresh['cart_ready'] != true) {
        if (mounted)
          setState(() {
            plan = fresh;
            error = 'The estimate changed. Refresh and review the basket before continuing.';
            acceptIncomplete = false;
          });
        return;
      }
      if (!c.mounted) return;
      await Navigator.push(
        c,
        MaterialPageRoute(
          builder: (_) => AroggaCartLive(
            rows: (fresh['rows'] as List)
                .where((r) => r['included'] == true)
                .map((r) => Map<String, dynamic>.from(r))
                .toList(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? amountValid(String? v) =>
      minorAmount(v ?? '') == null || (minorAmount(v ?? '') ?? 0) > 100000000
      ? 'Enter a non-negative BDT amount with up to two decimals'
      : null;
}
