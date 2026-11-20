import '../localization.dart';

import 'dart:async';

import 'package:timezone/timezone.dart' as tz;

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import 'workspace.dart';
import 'schedule_home.dart';
import 'medicine_setup.dart';
import 'inventory_live.dart';
import 'brand_choices.dart';
import '../services/medicine_schedule.dart';
import '../services/dose_tracking.dart';

class MedicineListLive extends StatefulWidget {
  const MedicineListLive({super.key, this.sectionTitle, this.section});
  final String? sectionTitle;
  final int? section;
  @override
  State<MedicineListLive> createState() => _MedicineListLiveState();
}

class _MedicineListLiveState extends State<MedicineListLive> {
  Timer? refresh;
  @override
  void initState() {
    super.initState();
    refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    final section = widget.section;
    final selected = section == null
        ? s.medicines
        : medicinesInSection(s, section!);
    return AppFrame(
      back: true,
      title: tr(widget.sectionTitle ?? 'Your Medicines'),
      subtitle: tr('Your reviewed prescription and purchase status.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SyncStatus(),
          if (selected.isEmpty)
            note(
              tr(
                section == null
                    ? 'No medicines yet. Add an item from your prescription.'
                    : 'No medicines in this section.',
              ),
              color: blue,
            ),
          for (final m in selected) ...[
            Tile(
              outlined: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Bubble(Icons.medication_outlined, size: 35),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('${m.name} ${m.strength}'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            small(
                              tr(
                                [
                                  m.frequency,
                                  m.meal,
                                  m.duration,
                                ].where((x) => x.isNotEmpty).join(' · '),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Edit medicine'),
                        onPressed: () => go(c, 'medicine', arguments: m.id),
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: blue,
                          size: 19,
                        ),
                      ),
                    ],
                  ),
                  gap(12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Pill(
                        tr(m.verified ? 'Reviewed by you' : 'Needs review'),
                        color: m.verified ? mint : Colors.orange,
                      ),
                      Pill(tr('${m.quantity} prescribed units')),
                      Pill(
                        tr(
                          m.neededToBuy == 0
                              ? 'No purchase needed'
                              : 'Need to buy',
                        ),
                        color: m.neededToBuy == 0 ? mint : blue,
                      ),
                      if (m.neededToBuy > 0)
                        Pill(
                          tr(
                            m.hasPrice
                                ? '${money(m.purchaseTotal)} estimate'
                                : 'Price needed',
                          ),
                          color: m.hasPrice ? blue : muted,
                        ),
                    ],
                  ),
                  TodayDoseStatus(
                    key: ValueKey(m.id),
                    medicine: m,
                    section: section,
                  ),
                  gap(12),
                  FilledButton.tonalIcon(
                    style: medicineActionStyle,
                    onPressed: () => showBrandChoices(c, s, m),
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(tr('Brand alternatives')),
                  ),
                  FilledButton.tonalIcon(
                    style: medicineActionStyle,
                    onPressed: m.verified
                        ? () => automaticSchedule(c, s, m)
                        : null,
                    icon: const Icon(Icons.add_alarm),
                    label: Text(tr('Auto-schedule reminders')),
                  ),
                ],
              ),
            ),
            InventoryCard(medicineId: m.id),
          ],
          ActionButton(
            tr('Scan Prescription'),
            icon: Icons.camera_alt_outlined,
            onTap: () => go(c, 'add'),
          ),
          gap(12),
          ActionButton(
            tr('Add Medicine'),
            icon: Icons.add,
            onTap: () => go(c, 'medicine'),
          ),
          gap(12),
          ActionButton(
            tr('Prices & Budget'),
            icon: Icons.account_balance_wallet_outlined,
            onTap: () => go(c, 'prices'),
          ),
          gap(12),
          TextButton(
            onPressed: () => go(c, 'reminders'),
            child: Text(tr('Set reminder times →')),
          ),
        ],
      ),
    );
  }
}

class TodayDoseStatus extends StatefulWidget {
  const TodayDoseStatus({super.key, required this.medicine, this.section});
  final Medicine medicine;
  final int? section;
  @override
  State<TodayDoseStatus> createState() => _TodayDoseStatusState();
}

class _TodayDoseStatusState extends State<TodayDoseStatus> {
  final saving = <String>{};

  Future<void> mark(
    AppState s,
    String key,
    Map<String, dynamic> reminder,
  ) async {
    final day = s.notification.dayNow(s.timezone);
    if (!widget.medicine.verified || !s.medicines.contains(widget.medicine))
      return;
    if (key != scheduledDoseKey(reminder['id'] as String, day) ||
        !activeScheduledDose(reminder, day) ||
        s.doses.any((d) => d['scheduled_key'] == key) ||
        !saving.add(key))
      return;
    if (s.doses.length >= 5000) {
      saving.remove(key);
      message(
        context,
        tr('Intake history is full'),
        tr('This dose could not be saved.'),
      );
      return;
    }
    setState(() {});
    final row = <String, dynamic>{
      'id': identifier(),
      'medicine_id': widget.medicine.id,
      'logged_at': DateTime.now().toUtc().toIso8601String(),
      'scheduled_key': key,
    };
    s.doses.add(row);
    try {
      await s.commit();
    } catch (_) {
      s.doses.remove(row);
      if (mounted)
        message(
          context,
          tr('Dose not saved'),
          tr('Check available storage and try again.'),
        );
    } finally {
      saving.remove(key);
      if (mounted) setState(() {});
    }
  }

  bool manualSaving = false;
  Future<void> manualMark() async {
    if (manualSaving || !widget.medicine.verified) return;
    final s = Scope.of(context), owner = Scope.of(context).userId;
    setState(() => manualSaving = true);
    try {
      final units = await askUnits(
        context,
        tr('Mark taken'),
        tr('Individual units actually taken'),
        min: 1,
        initial: widget.medicine.confirmedDoseUnits,
      );
      if (units == null ||
          !mounted ||
          owner != s.userId ||
          !s.signedIn ||
          !s.medicines.contains(widget.medicine))
        return;
      if (s.doses.length >= 5000 ||
          widget.medicine.unitsTaken + units > 100000) {
        if (mounted)
          message(
            context,
            tr('Intake history is full'),
            tr('This dose could not be saved.'),
          );
        return;
      }
      final row = <String, dynamic>{
        'id': identifier(),
        'medicine_id': widget.medicine.id,
        'logged_at': DateTime.now().toUtc().toIso8601String(),
        'units': units,
      };
      final oldStock = widget.medicine.stockUnits;
      widget.medicine.unitsTaken += units;
      if (oldStock != null)
        widget.medicine.stockUnits = (oldStock - units)
            .clamp(0, 100000)
            .toInt();
      s.doses.add(row);
      try {
        await s.commit();
      } catch (_) {
        s.doses.remove(row);
        widget.medicine.unitsTaken -= units;
        widget.medicine.stockUnits = oldStock;
        if (mounted)
          message(
            context,
            tr('Dose not saved'),
            tr('Check available storage and try again.'),
          );
      }
    } finally {
      if (mounted) setState(() => manualSaving = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    final day = s.notification.dayNow(s.timezone);
    int minute(Map<String, dynamic> r) =>
        (r['hour'] as int) * 60 + (r['minute'] as int);
    final section = widget.section;
    final reminders =
        s.reminders
            .where(
              (r) =>
                  r['medicine_id'] == widget.medicine.id &&
                  activeScheduledDose(r, day) &&
                  (section == null ||
                      section == 3 ||
                      (r['meal_slot'] ?? scheduleSection(minute(r))) ==
                          section),
            )
            .toList()
          ..sort((a, b) => minute(a).compareTo(minute(b)));
    final manualToday = s.doses.where((row) {
      if (row['medicine_id'] != widget.medicine.id ||
          row['scheduled_key'] != null)
        return false;
      final stamp = DateTime.tryParse(row['logged_at'] as String? ?? '');
      if (stamp == null) return false;
      final local = tz.TZDateTime.from(stamp, tz.getLocation(s.timezone));
      return local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }).length;
    if (reminders.isEmpty)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (manualToday > 0) Pill(tr('Dose recorded today'), color: mint),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton.tonalIcon(
              style: medicineActionStyle,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(tr('Mark taken')),
              onPressed: !widget.medicine.verified || manualSaving
                  ? null
                  : manualMark,
            ),
          ),
        ],
      );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Today’s doses'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final r in reminders)
            Builder(
              builder: (context) {
                final key = scheduledDoseKey(r['id'] as String, day);
                final taken = s.doses.any((d) => d['scheduled_key'] == key);
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(
                          TimeOfDay(
                            hour: r['hour'] as int,
                            minute: r['minute'] as int,
                          ).format(context),
                        ),
                      ),
                    ),
                    if (taken)
                      Pill(tr('Taken'), color: mint)
                    else
                      FilledButton.tonalIcon(
                        style: medicineActionStyle,
                        onPressed:
                            !widget.medicine.verified || saving.contains(key)
                            ? null
                            : () => mark(s, key, r),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(tr('Pending · Mark taken')),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class MedicineLive extends StatefulWidget {
  const MedicineLive({super.key, this.id, this.initial});
  final String? id;
  final Map<String, dynamic>? initial;
  @override
  State<MedicineLive> createState() => _MedicineLiveState();
}

class _MedicineLiveState extends State<MedicineLive> {
  final form = GlobalKey<FormState>();
  final fieldKeys = List.generate(10, (_) => GlobalKey());
  String? saveError;
  bool loaded = false,
      verified = false,
      busy = false,
      purchased = false,
      manualPrice = false,
      autoRemind = false,
      antibioticGroup = false;
  final quantityInput = TextEditingController();
  String doseUnits = '';
  DateTime? courseDate;
  late Medicine medicine;
  late List<String> values;
  String? source;
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    if (!loaded) {
      medicine =
          s.medicines.where((m) => m.id == widget.id).firstOrNull ??
          (widget.initial == null
              ? Medicine()
              : Medicine(
                  name: widget.initial!['name'] ?? '',
                  strength: widget.initial!['strength'] ?? '',
                  form: widget.initial!['form'] ?? '',
                  frequency: widget.initial!['frequency'] ?? '',
                  meal: widget.initial!['meal'] ?? '',
                  duration: widget.initial!['duration'] ?? '',
                  route: widget.initial!['route'] ?? '',
                  instruction: widget.initial!['instruction'] ?? '',
                  sourceDocumentId: widget.initial!['source_document_id'],
                ));
      values = [
        medicine.name,
        medicine.strength,
        medicine.form,
        medicine.frequency,
        medicine.meal,
        medicine.duration,
        medicine.route,
        medicine.instruction,
        widget.id == null ? '' : '${medicine.quantity}',
        medicine.unitPrice == 0
            ? ''
            : (medicine.unitPrice / 100).toStringAsFixed(2),
      ];
      courseDate = DateTime.tryParse(medicine.courseStart ?? '');
      quantityInput.text = values[8];
      doseUnits = medicine.confirmedDoseUnits?.toString() ?? '';
      antibioticGroup = medicine.antibioticGroup;
      verified = medicine.verified;
      purchased = medicine.purchased;
      manualPrice = medicine.quoteId == null;
      source = medicine.sourceDocumentId ?? s.currentDocumentId;
      loaded = true;
    }
    final start = courseDate ?? DateTime.now();
    final days = courseDays(values[5], start);
    final perDay = dailyUnits(values[3], int.tryParse(rxText(doseUnits)));
    final canCalculate =
        verified &&
        countedForm(values[2]) &&
        days != null &&
        perDay != null &&
        days * perDay <= 100000 &&
        !isPrn('${values[3]} ${values[7]}');
    return AppFrame(
      back: true,
      bottom: false,
      title: tr('Medication Details'),
      subtitle: tr('Enter only what your prescription says.'),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tile(
              outlined: false,
              child: Column(
                children: [
                  const Bubble(Icons.medication_outlined, size: 50),
                  gap(15),
                  for (int i = 0; i < values.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        key: fieldKeys[i],
                        initialValue: i == 8 ? null : values[i],
                        controller: i == 8 ? quantityInput : null,
                        onChanged: (v) {
                          if (const [2, 3, 5, 7].contains(i))
                            setState(() => values[i] = v.trim());
                        },
                        style: const TextStyle(fontSize: 12),
                        keyboardType: i >= 8
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: tr(
                            [
                              'Medicine name',
                              'Strength',
                              'Dosage form',
                              'Frequency as prescribed',
                              'Meal timing',
                              'Duration',
                              'Route',
                              'Special instructions',
                              'Quantity for this prescription or refill',
                              'Unit price (BDT, optional)',
                            ][i],
                          ),
                        ),
                        onSaved: (v) => values[i] = i == 8
                            ? rxText(v ?? '').trim()
                            : (v ?? '').trim(),
                        validator: (v) {
                          if (i == 0 && (v == null || v.trim().isEmpty))
                            return tr('Required');
                          if (i == 8 &&
                              (int.tryParse(rxText(v ?? '').trim()) == null ||
                                  (int.tryParse(rxText(v ?? '').trim()) ?? 0) <
                                      1 ||
                                  (int.tryParse(rxText(v ?? '').trim()) ?? 0) >
                                      100000))
                            return tr('Enter a quantity from 1 to 100000');
                          if (i == 9 &&
                              (v ?? '').trim().isNotEmpty &&
                              (minorAmount(v ?? '') == null ||
                                  (minorAmount(v ?? '') ?? 0) > 100000000))
                            return tr('Enter a price with up to two decimals');
                          return tr(null);
                        },
                      ),
                    ),
                  if (medicine.stockUnits == null && widget.id != null)
                    small(
                      tr(
                        'Track the supply after saving from your medicine list.',
                      ),
                    ),
                  if (countedForm(values[2]) &&
                      slotDoses(values[3]) == null &&
                      days != null &&
                      explicitDose(values[3]).$1 == null)
                    TextFormField(
                      initialValue: doseUnits,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('Units per dose as written'),
                        helperText: tr(
                          'Example: 1 if prescribed one tablet each time',
                        ),
                      ),
                      onChanged: (v) => setState(() => doseUnits = v.trim()),
                      onSaved: (v) => doseUnits = v?.trim() ?? '',
                      validator: (v) {
                        final text = rxText(v ?? '');
                        final amount = int.tryParse(text);
                        return tr(
                          text.isNotEmpty &&
                                  (amount == null || amount < 1 || amount > 99)
                              ? 'Enter a whole number from 1 to 99'
                              : null,
                        );
                      },
                    ),
                  if (canCalculate)
                    TextButton.icon(
                      icon: const Icon(Icons.calculate_outlined),
                      onPressed: () {
                        quantityInput.text = '${days! * perDay!}';
                      },
                      label: Text(
                        tr(
                          'Use ${days! * perDay!} units ($days days × $perDay per day)',
                        ),
                      ),
                    )
                  else
                    small(
                      tr(
                        days == null
                            ? 'No fixed course total. Enter the quantity prescribed for this refill.'
                            : !verified
                            ? 'Review the prescription to calculate the quantity.'
                            : 'For calculation, enter a fixed frequency and the prescribed units per dose.',
                      ),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      tr(
                        courseDate == null
                            ? 'Course start: today (tap to change)'
                            : 'Course start: ${dateKey(courseDate!)}',
                      ),
                    ),
                    onPressed: () async {
                      final today = DateTime.now();
                      final selected = await showDatePicker(
                        context: c,
                        initialDate: courseDate ?? today,
                        firstDate:
                            (courseDate != null && courseDate!.year < 2020)
                            ? courseDate!
                            : DateTime(2020),
                        lastDate: DateTime(today.year + 5),
                      );
                      if (selected != null && mounted)
                        setState(() => courseDate = selected);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: antibioticGroup,
                    onChanged: (v) =>
                        setState(() => antibioticGroup = v ?? false),
                    title: Text(tr('Show under Antibiotics')),
                    subtitle: Text(
                      tr(
                        'Use only if the medicine label or prescription identifies it as an antibiotic.',
                      ),
                    ),
                  ),
                  if (medicine.quoteId != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr('Use a manually checked price instead'),
                        style: TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        tr(
                          'Replaces the online quote; manual prices do not enable cart assistance.',
                        ),
                        style: TextStyle(fontSize: 11),
                      ),
                      value: manualPrice,
                      onChanged: (v) => setState(() => manualPrice = v),
                    ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(source),
                    initialValue: source,
                    decoration: InputDecoration(
                      labelText: tr('Source document (optional)'),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(tr('No linked document')),
                      ),
                      if (source != null &&
                          !s.documents.any((d) => d['id'] == source))
                        DropdownMenuItem<String>(
                          value: source,
                          child: Text(tr('Linked document (not loaded)')),
                        ),
                      for (final d in {
                        for (final d in s.documents)
                          if (d['id'] is String) d['id']: d,
                      }.values)
                        DropdownMenuItem(
                          value: d['id'] as String,
                          child: Text(
                            tr(
                              '${d['kind']} · ${(d['id'] as String).length > 8 ? (d['id'] as String).substring(0, 8) : d['id']}',
                            ),
                          ),
                        ),
                    ],
                    onChanged: busy ? null : (v) => setState(() => source = v),
                    isExpanded: true,
                  ),
                  gap(12),
                  if (medicine.stockUnits == null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr('Already purchased'),
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        tr('Keep reminders; exclude from the shopping budget.'),
                        style: TextStyle(fontSize: 11),
                      ),
                      value: purchased,
                      onChanged: (v) => setState(() => purchased = v),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: verified,
                    onChanged: (v) => setState(() => verified = v ?? false),
                    title: Text(
                      tr('I checked these fields against the prescription.'),
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: autoRemind,
              onChanged: !verified
                  ? null
                  : (v) => setState(() => autoRemind = v ?? false),
              title: Text(tr('Set up reminders after saving')),
            ),
            if (saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  saveError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ActionButton(
              tr(busy ? 'Saving…' : 'Save Medication'),
              onTap: busy ? null : save,
            ),
            if (widget.id != null)
              TextButton.icon(
                onPressed: busy ? null : remove,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: Text(
                  tr('Remove from medicine list'),
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Remove this medicine?')),
        content: Text(
          tr(
            'This removes it from your current list and cancels its reminders. Source documents and historical dose logs are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Keep')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Remove')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = Scope.of(context);
    setState(() => busy = true);
    try {
      for (final r in s.reminders.where(
        (r) => r['medicine_id'] == medicine.id,
      )) {
        await s.notification.cancelReminder(r['id'] as String);
      }
      s.reminders.removeWhere((r) => r['medicine_id'] == medicine.id);
      s.medicines.removeWhere((m) => m.id == medicine.id);
      s.selectedIds.remove(medicine.id);
      await s.commit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) message(context, tr('Could not remove'), tr('$e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    quantityInput.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final error =
          invalid.first.errorText ??
          tr<String>('Check the highlighted fields.');
      setState(() => saveError = error);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && invalid.first.context.mounted) {
          Scrollable.ensureVisible(
            invalid.first.context,
            duration: const Duration(milliseconds: 250),
            alignment: 0.2,
          );
        }
      });
      return;
    }
    form.currentState!.save();
    final s = Scope.of(context);
    final owner = s.userId;
    final previousMedicines = List<Medicine>.from(s.medicines);
    final previousReminders = s.reminders
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final previousSelected = Set<String>.from(s.selectedIds);
    final previousPending = s.pendingEvent;
    final cancellations = <String>[];
    bool persisted = false;
    setState(() {
      busy = true;
      saveError = null;
    });
    try {
      if (s.userId == null)
        throw StateError(tr('Sign in before saving medicine details.'));
      // Saving a medicine must not depend on notification plugin initialization.
      final dhaka = DateTime.now().toUtc().add(const Duration(hours: 6));
      final start =
          courseDate ?? DateTime.utc(dhaka.year, dhaka.month, dhaka.day);
      if (!mounted) return;
      final dose =
          int.tryParse(rxText(doseUnits)) ?? explicitDose(values[3]).$1;
      final amount = int.parse(values[8]);
      final latest =
          s.medicines.where((x) => x.id == medicine.id).firstOrNull ?? medicine;
      final identityChanged =
          medicine.name != values[0] ||
          medicine.strength != values[1] ||
          medicine.form != values[2];
      final enteredPrice = minorAmount(values[9]) ?? 0;
      final effectivePrice =
          identityChanged && enteredPrice == medicine.unitPrice
          ? 0
          : enteredPrice;
      final keepQuote =
          !manualPrice &&
          !identityChanged &&
          medicine.quoteId != null &&
          medicine.productMatchConfirmed &&
          enteredPrice == medicine.unitPrice;
      final m = Medicine(
        id: medicine.id,
        name: values[0],
        strength: values[1],
        form: values[2],
        frequency: values[3],
        meal: values[4],
        duration: values[5],
        route: values[6],
        instruction: values[7],
        quantity: amount,
        stockUnits: identityChanged ? null : latest.stockUnits,
        unitsTaken: identityChanged ? 0 : latest.unitsTaken,
        confirmedDoseUnits: dose,
        courseStart: dateKey(start),
        refillThreshold: identityChanged ? null : latest.refillThreshold,
        paracetamolGroup: latest.paracetamolGroup,
        antibioticGroup: antibioticGroup,
        unitPrice: effectivePrice,
        purchased: purchased,
        quantityUnit: identityChanged ? 'unit' : medicine.quantityUnit,
        priceConfirmed: !keepQuote && effectivePrice > 0,
        quoteId: keepQuote ? medicine.quoteId : null,
        priceQuote: keepQuote ? medicine.priceQuote : null,
        productMatchConfirmed: keepQuote,
        verified: verified,
        sourceDocumentId: source,
      );
      // A medicine excluded solely because review was pending must become a
      // selection candidate when the user explicitly completes that review.
      if (!medicine.verified && m.verified && !m.purchased) {
        s.selectedIds.add(m.id);
      }
      if (m.neededToBuy == 0 || !m.verified) s.selectedIds.remove(m.id);
      if (!m.verified ||
          identityChanged ||
          latest.frequency != m.frequency ||
          latest.meal != m.meal ||
          latest.duration != m.duration ||
          latest.instruction != m.instruction ||
          (latest.courseStart != null && latest.courseStart != m.courseStart)) {
        for (final r in s.reminders) {
          if (r['medicine_id'] == m.id) r['enabled'] = false;
        }
        cancellations.addAll(
          s.reminders
              .where((r) => r['medicine_id'] == m.id)
              .map((r) => r['id'] as String),
        );
      }
      final index = s.medicines.indexWhere((x) => x.id == m.id);
      if (index < 0) {
        s.medicines.add(m);
      } else {
        s.medicines[index] = m;
      }
      var added = 0;
      try {
        added = autoRemind ? 0 : addSharedMealReminders(s, m);
      } catch (_) {
        // Keep the edited medicine even if optional reminder preparation fails.
        s.reminders
          ..clear()
          ..addAll(previousReminders.map((r) => Map<String, dynamic>.from(r)));
        for (final r in s.reminders) {
          if (cancellations.contains(r['id'])) r['enabled'] = false;
        }
      }
      await s.commit();
      persisted = true;
      if (s.userId != owner) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Medicine saved on this device.'))),
        );
      }
      // Device scheduling is separate from durable medicine persistence.
      if (cancellations.isNotEmpty || added > 0) {
        if (autoRemind) {
          try {
            await Future.wait(
              cancellations.map((id) => s.notification.cancelReminder(id)),
            ).timeout(const Duration(seconds: 5));
          } catch (_) {}
        } else {
          unawaited(_refreshSavedMedicineAlarms(s, cancellations));
        }
      }
      if (mounted && autoRemind && m.verified) {
        await automaticSchedule(context, s, m);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!persisted && s.userId == owner) {
        s.medicines
          ..clear()
          ..addAll(previousMedicines);
        s.reminders
          ..clear()
          ..addAll(previousReminders);
        s.selectedIds
          ..clear()
          ..addAll(previousSelected);
        s.pendingEvent = previousPending;
        s.emit();
      }
      if (mounted) {
        final text = persisted
            ? tr(
                'Medicine saved. Open Medicine Reminders to finish scheduling.',
              )
            : '${tr('Could not save')}: $e';
        setState(() => saveError = text);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _refreshSavedMedicineAlarms(AppState s, List<String> ids) async {
    try {
      await Future.wait(
        ids.map((id) => s.notification.cancelReminder(id)),
      ).timeout(const Duration(seconds: 5));
      await s
          .applyReminders(prompt: false)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Saved reminder configuration remains available for explicit rescheduling.
    }
  }
}

class RemindersLive extends StatefulWidget {
  const RemindersLive({super.key});
  @override
  State<RemindersLive> createState() => _RemindersLiveState();
}

class _RemindersLiveState extends State<RemindersLive> {
  bool busy = false, permissionBusy = false;
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    return AppFrame(
      back: true,
      title: tr('Medicine Reminders'),
      subtitle: tr('Choose times from your prescribed schedule.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.schedule_outlined, color: blue),
            title: Text(tr('Bangladesh time')),
            subtitle: Text(tr('Asia/Dhaka')),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => setupMeals(c, s),
            icon: const Icon(Icons.restaurant_outlined),
            label: Text(tr('Meal times and offsets')),
          ),
          gap(15),
          for (final r in s.reminders)
            Tile(
              outlined: false,
              child: Row(
                children: [
                  const Bubble(Icons.notifications_none),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(
                        '${s.medicines.where((m) => m.id == r['medicine_id']).firstOrNull?.name ?? 'Medicine'}\n${(r['hour'] as int).toString().padLeft(2, '0')}:${(r['minute'] as int).toString().padLeft(2, '0')}',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Switch(
                    value: r['enabled'] == true,
                    onChanged: (v) async {
                      if (!v)
                        await s.notification.cancelReminder(r['id'] as String);
                      r['enabled'] = v;
                      s.changed();
                    },
                  ),
                  IconButton(
                    tooltip: tr('Remove reminder'),
                    onPressed: () async {
                      await s.notification.cancelReminder(r['id'] as String);
                      s.reminders.remove(r);
                      s.changed();
                    },
                    icon: const Icon(Icons.delete_outline, color: muted),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: busy || permissionBusy
                ? null
                : () => chooseMedicine(c, s),
            icon: const Icon(Icons.add_alarm),
            label: Text(tr('Add reminder')),
          ),
          TextButton.icon(
            onPressed: busy || permissionBusy
                ? null
                : () async {
                    try {
                      if (!await s.notification.testAlarm() && c.mounted) {
                        message(
                          c,
                          tr('Notification permission needed'),
                          tr('Allow Med.ai notifications and try again.'),
                        );
                      }
                    } catch (_) {
                      if (c.mounted)
                        message(
                          c,
                          tr('Could not play alarm'),
                          tr(
                            'Check the Medicine alarms category and alarm volume in Android settings.',
                          ),
                        );
                    }
                  },
            icon: const Icon(Icons.volume_up_outlined),
            label: Text(tr('Test alarm sound')),
          ),
          if (s.medicines.where((m) => m.verified).isEmpty)
            note(
              tr(
                'Review a medicine against your prescription before setting its reminders.',
              ),
              color: blue,
            ),
          gap(12),
          TextButton.icon(
            onPressed: busy || permissionBusy
                ? null
                : () async {
                    setState(() => permissionBusy = true);
                    try {
                      await enableMedicineAlerts(c, s);
                    } finally {
                      if (mounted) setState(() => permissionBusy = false);
                    }
                  },
            icon: const Icon(Icons.notification_important_outlined),
            label: Text(tr('Manage phone alarm permissions')),
          ),
          ActionButton(
            tr(busy ? 'Scheduling…' : 'Save and Schedule on This Device'),
            icon: Icons.notifications_active_outlined,
            onTap: busy || permissionBusy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await s.commit();
                      final allowed = await s.applyReminders().timeout(
                        const Duration(seconds: 24),
                      );
                      if (c.mounted)
                        message(
                          c,
                          tr(
                            allowed
                                ? 'Reminders scheduled'
                                : 'Notification permission needed',
                          ),
                          tr(
                            allowed
                                ? 'Reminders are scheduled in ${s.timezone}. ${reminderDelivery(s)}'
                                : 'Enable notifications in your device settings, then schedule again.',
                          ),
                        );
                    } catch (e) {
                      if (c.mounted)
                        message(c, tr('Could not schedule'), tr(e.toString()));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
          ),
          gap(10),
          small(
            tr(
              'Open or dismiss the alert to stop the sound. Choose reminder times from the prescription, then tap Save and Schedule on this phone.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> chooseMedicine(BuildContext c, AppState s) async {
    final choices = s.medicines
        .where(
          (m) =>
              m.verified && !isPrn('${m.frequency} ${m.instruction} ${m.meal}'),
        )
        .toList();
    if (choices.isEmpty) {
      message(
        c,
        tr('No eligible medicines'),
        tr('Review a medicine before creating its reminder.'),
      );
      return;
    }
    final selected = await showModalBottomSheet<Medicine>(
      context: c,
      useSafeArea: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          for (final m in choices)
            ListTile(
              title: Text(tr(m.name)),
              subtitle: Text(tr(m.strength)),
              onTap: () => Navigator.pop(sheet, m),
            ),
        ],
      ),
    );
    if (selected != null && c.mounted) await add(c, selected);
  }

  Future<void> add(BuildContext c, Medicine m) async {
    final s = Scope.of(c);
    if (s.reminders.length >= 50) {
      message(
        c,
        tr('Reminder limit'),
        tr('This release supports 50 daily reminders per account.'),
      );
      return;
    }
    final time = await showTimePicker(context: c, initialTime: TimeOfDay.now());
    if (time == null || !c.mounted) return;
    if (s.reminders.any(
      (r) =>
          r['medicine_id'] == m.id &&
          r['enabled'] == true &&
          r['hour'] == time.hour &&
          r['minute'] == time.minute &&
          r['end_date'] == null,
    )) {
      message(
        c,
        tr('Reminder already set'),
        tr('This medicine already has a daily reminder at that time.'),
      );
      return;
    }
    s.reminders.add({
      'id': identifier(),
      'medicine_id': m.id,
      'hour': time.hour,
      'minute': time.minute,
      'enabled': true,
    });
    await s.commit();
  }
}
