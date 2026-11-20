import 'localization.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier, Uint8List;
import 'package:flutter/widgets.dart'
    show
        BuildContext,
        InheritedNotifier,
        WidgetsBinding,
        WidgetsBindingObserver,
        AppLifecycleState;
import 'package:cryptography/cryptography.dart';

import 'services/api.dart';
import 'services/vault.dart';
import 'services/reminders.dart';
import 'services/medicine_schedule.dart';
import 'services/purchase_math.dart';
import 'services/retailer_session.dart';

String identifier() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String money(int minor) => '৳${(minor / 100).toStringAsFixed(2)}';
int? minorAmount(String value) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
  return (double.parse(value.trim()) * 100).round();
}

class Medicine {
  Medicine({
    String? id,
    this.name = '',
    this.strength = '',
    this.form = '',
    this.frequency = '',
    this.meal = '',
    this.duration = '',
    this.route = '',
    this.instruction = '',
    this.quantity = 1,
    this.unitPrice = 0,
    this.verified = false,
    this.sourceDocumentId,
    this.quantityUnit = 'unit',
    this.purchased = false,
    bool? priceConfirmed,
    this.productMatchConfirmed = false,
    this.quoteId,
    this.priceQuote,
    this.stockUnits,
    this.unitsTaken = 0,
    this.confirmedDoseUnits,
    this.courseStart,
    this.refillThreshold,
    this.paracetamolGroup = false,
    this.antibioticGroup = false,
  }) : id = id ?? identifier(),
       priceConfirmed = priceConfirmed ?? unitPrice > 0;
  final String id;
  String name, strength, form, frequency, meal, duration, route, instruction;
  int quantity, unitPrice;
  bool verified, purchased, priceConfirmed, productMatchConfirmed;
  String? sourceDocumentId, quoteId;
  String quantityUnit;
  Map<String, dynamic>? priceQuote;
  int? stockUnits, confirmedDoseUnits, refillThreshold;
  int unitsTaken;
  String? courseStart;
  bool paracetamolGroup, antibioticGroup;
  bool get paracetamol => paracetamolGroup || isParacetamol(name, form);
  int get remainingCourse => max(0, quantity - unitsTaken);
  int get neededToBuy => stockUnits == null
      ? (purchased ? 0 : quantity)
      : max(0, remainingCourse - stockUnits!);
  int get lowStockLevel =>
      refillThreshold ?? (dailyUnits(frequency, confirmedDoseUnits) ?? 1) * 3;
  bool get lowStock =>
      stockUnits != null && neededToBuy > 0 && stockUnits! <= lowStockLevel;

  bool get quoteFresh =>
      productMatchConfirmed &&
      priceQuote?['expires_at'] is int &&
      (priceQuote!['expires_at'] as int) >
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
  int get purchaseTotal => neededToBuy == 0
      ? 0
      : quoteFresh
      ? packTotal(
          neededToBuy,
          priceQuote!['units_per_pack'] as int,
          priceQuote!['pack_price_minor'] as int,
        )
      : priceConfirmed && quoteId == null
      ? neededToBuy * unitPrice
      : 0;
  bool get hasPrice =>
      quoteFresh || priceConfirmed && quoteId == null && unitPrice > 0;
  int get total => quantity * unitPrice;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'strength': strength,
    'form': form,
    'frequency': frequency,
    'meal': meal,
    'duration': duration,
    'route': route,
    'instruction': instruction,
    'quantity': quantity,
    'unit_price_minor': unitPrice,
    'verified': verified,
    'source_document_id': sourceDocumentId,
    'purchased': purchased,
    'quantity_unit': quantityUnit,
    'price_confirmed': priceConfirmed,
    'quote_id': quoteId,
    'product_match_confirmed': productMatchConfirmed,
    'price_quote': priceQuote,
    'stock_units': stockUnits,
    'units_taken': unitsTaken,
    'confirmed_dose_units': confirmedDoseUnits,
    'course_start': courseStart,
    'refill_threshold': refillThreshold,
    'paracetamol_group': paracetamolGroup,
    'antibiotic_group': antibioticGroup,
  };
  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
    id: j['id'],
    name: j['name'],
    strength: j['strength'] ?? '',
    form: j['form'] ?? '',
    frequency: j['frequency'] ?? '',
    meal: j['meal'] ?? '',
    duration: j['duration'] ?? '',
    route: j['route'] ?? '',
    instruction: j['instruction'] ?? '',
    quantity: j['quantity'],
    unitPrice: j['unit_price_minor'],
    verified: j['verified'] ?? false,
    sourceDocumentId: j['source_document_id'],
    purchased: j['purchased'] ?? false,
    quantityUnit: j['quantity_unit'] ?? 'unit',
    priceConfirmed:
        j['price_confirmed'] ?? (j['unit_price_minor'] as int? ?? 0) > 0,
    productMatchConfirmed: j['product_match_confirmed'] ?? false,
    quoteId: j['quote_id'],
    stockUnits: j['stock_units'],
    unitsTaken: j['units_taken'] ?? 0,
    confirmedDoseUnits: j['confirmed_dose_units'],
    courseStart: j['course_start'],
    refillThreshold: j['refill_threshold'],
    paracetamolGroup: j['paracetamol_group'] ?? false,
    antibioticGroup: j['antibiotic_group'] ?? false,
    priceQuote: j['price_quote'] is Map
        ? Map<String, dynamic>.from(j['price_quote'])
        : null,
  );
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({Api? api, Vault? vault})
    : api = api ?? Api(),
      vault = vault ?? Vault() {
    this.api.onUnauthorized = () {
      needsSignIn = true;
      error = 'Your session expired. Sign in to continue.';
      emit();
    };
  }
  final Api api;
  final Vault vault;
  final notification = ReminderService();
  String? userId;
  bool ready = false, syncing = false, conflict = false;
  String? error, pendingEvent;
  int version = 0;
  String name = '',
      email = '',
      phone = '',
      allergies = '',
      journal = '',
      mood = '',
      language = 'English';
  String get timezone => 'Asia/Dhaka';
  final medicines = <Medicine>[];
  List<int> mealMinutes = [];
  int? beforeMealMinutes, afterMealMinutes;
  bool preciseReminders = false;
  String? _lastReminderWindow;
  bool get mealsConfigured => mealMinutes.length == 3;

  Future<bool> applyReminders({bool? exact, bool prompt = true}) =>
      notification.schedule(
        reminders
            .where(
              (r) =>
                  medicines.any((m) => m.id == r['medicine_id'] && m.verified),
            )
            .toList(),
        timezone,
        exact: exact ?? preciseReminders,
        prompt: prompt,
        medicineLabels: {
          for (final m in medicines)
            if (m.verified) m.id: m.name,
        },
      );

  final vitals = <Map<String, dynamic>>[],
      doses = <Map<String, dynamic>>[],
      reminders = <Map<String, dynamic>>[],
      documents = <Map<String, dynamic>>[],
      uploads = <Map<String, dynamic>>[];
  final selectedIds = <String>{};
  int budget = 0, delivery = 0;
  bool budgetSet = false;
  Uint8List? document;
  String docType = 'Prescription', docLanguage = 'eng';
  String? currentDocumentId;
  Map<String, dynamic>? knowledgePack;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  int _sessionEpoch = 0;
  bool needsSignIn = false;
  Timer? _retry;
  bool _observing = false;
  bool get signedIn => userId != null && api.token != null;
  bool get pricesComplete =>
      medicines.every((m) => m.neededToBuy == 0 || m.hasPrice);
  int get subtotal => medicines.fold(0, (sum, m) => sum + m.purchaseTotal);
  int get selectedSubtotal => medicines
      .where((m) => selectedIds.contains(m.id))
      .fold(0, (sum, m) => sum + m.purchaseTotal);
  int get selectedTotal =>
      selectedSubtotal + (selectedIds.isEmpty ? 0 : delivery);
  int get remaining => budget - selectedTotal;
  Map<String, dynamic> get snapshot => {
    'name': name,
    'email': email,
    'phone': phone,
    'allergies': allergies,
    'journal': journal,
    'mood': mood,
    'language': language,
    'timezone': timezone,
    'meal_minutes': mealMinutes,
    'precise_reminders': preciseReminders,
    'before_meal_minutes': beforeMealMinutes,
    'after_meal_minutes': afterMealMinutes,
    'medicines': medicines.map((m) => m.toJson()).toList(),
    'vitals': vitals,
    'doses': doses,
    'reminders': reminders,
    'budget': budget,
    'budget_set': budgetSet,
    'delivery': delivery,
    'selected_ids': selectedIds.toList(),
  };
  void hydrate(Map<String, dynamic> j) {
    name = j['name'] ?? '';
    email = j['email'] ?? '';
    phone = j['phone'] ?? '';
    allergies = j['allergies'] ?? '';
    journal = j['journal'] ?? '';
    mood = j['mood'] ?? '';
    language = j['language'] ?? language;
    UiLanguage.use(language);
    preciseReminders = j['precise_reminders'] == true;
    mealMinutes = (j['meal_minutes'] as List? ?? []).cast<int>().toList();
    beforeMealMinutes = j['before_meal_minutes'];
    afterMealMinutes = j['after_meal_minutes'];
    budget = j['budget'] ?? 0;
    budgetSet = j['budget_set'] ?? budget > 0;
    delivery = j['delivery'] ?? 0;
    medicines
      ..clear()
      ..addAll(
        (j['medicines'] as List? ?? []).map(
          (m) => Medicine.fromJson(Map<String, dynamic>.from(m)),
        ),
      );
    for (final entry in {
      'vitals': vitals,
      'doses': doses,
      'reminders': reminders,
    }.entries) {
      entry.value
        ..clear()
        ..addAll(
          (j[entry.key] as List? ?? []).map(
            (v) => Map<String, dynamic>.from(v),
          ),
        );
    }
    selectedIds
      ..clear()
      ..addAll((j['selected_ids'] as List? ?? []).cast<String>());
  }

  Future<void> setLanguage(String code) async {
    await UiLanguage.save(code);
    language = code == 'bn' ? 'Bangla' : 'English';
    emit();
    if (signedIn) await commit();
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    await UiLanguage.initialize();
    language = UiLanguage.locale.value.languageCode == 'bn'
        ? 'Bangla'
        : 'English';
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    _retry = Timer.periodic(const Duration(seconds: 30), (_) {
      if (signedIn &&
          !needsSignIn &&
          !syncing &&
          (pendingEvent != null || uploads.isNotEmpty || error != null))
        unawaited(sync());
    });
    try {
      final session = await vault.readSession();
      if (session != null && session['base_url'] == Api.baseUrl) {
        userId = session['user_id'];
        api.token = session['token'];
        final cache = await vault.read(userId!);
        if (cache != null) {
          hydrate(Map<String, dynamic>.from(cache['state']));
          version = cache['version'] ?? 0;
          pendingEvent = cache['pending'];
          knowledgePack = cache['knowledge_pack'] is Map
              ? Map<String, dynamic>.from(cache['knowledge_pack'])
              : null;
          documents.addAll(
            (cache['documents'] as List? ?? []).map(
              (d) => Map<String, dynamic>.from(d),
            ),
          );
          uploads.addAll(
            (cache['uploads'] as List? ?? []).map(
              (d) => Map<String, dynamic>.from(d),
            ),
          );
        }
        unawaited(sync());
      }
    } catch (_) {
      error = 'Could not unlock the local record. Please sign in again.';
      userId = null;
      api.token = null;
    }
    ready = true;
    emit();
  }

  Future<void> authenticate(
    String mail,
    String password, {
    String? fullName,
  }) async {
    final r = await api.request(
      'POST',
      fullName == null ? '/auth/login' : '/auth/register',
      {
        'email': mail,
        'password': password,
        if (fullName != null) 'name': fullName,
      },
    );
    if (r['role'] != 'patient')
      throw ApiError(403, 'Use the care-team website for clinician accounts.');
    _sessionEpoch++;
    knowledgePack = null;
    needsSignIn = false;
    error = null;
    api.token = r['token'];
    userId = r['user_id'];
    version = 0;
    pendingEvent = null;
    conflict = false;
    documents.clear();
    uploads.clear();
    final cache = await vault.read(userId!);
    if (cache != null) {
      hydrate(Map<String, dynamic>.from(cache['state']));
      version = cache['version'] ?? 0;
      pendingEvent = cache['pending'];
      knowledgePack = cache['knowledge_pack'] is Map
          ? Map<String, dynamic>.from(cache['knowledge_pack'])
          : null;
      documents.addAll(
        (cache['documents'] as List? ?? []).map(
          (d) => Map<String, dynamic>.from(d),
        ),
      );
      uploads.addAll(
        (cache['uploads'] as List? ?? []).map(
          (d) => Map<String, dynamic>.from(d),
        ),
      );
    }
    await vault.session({
      'user_id': userId,
      'token': api.token,
      'base_url': Api.baseUrl,
    });
    if (cache == null) {
      final remote = await api.request('GET', '/state');
      hydrate(Map<String, dynamic>.from(remote['state']));
      version = remote['version'];
      await persist();
    }
    await sync();
    emit();
  }

  Future<void> persist() {
    if (userId == null) return Future.value();
    final user = userId!;
    final data = Map<String, dynamic>.from(
      jsonDecode(
            jsonEncode({
              'state': snapshot,
              'version': version,
              'pending': pendingEvent,
              'documents': documents,
              'uploads': uploads,
              'knowledge_pack': knowledgePack,
            }),
          )
          as Map,
    );
    final next = _writes
        .catchError((Object _) {})
        .then((_) => vault.write(user, data));
    _writes = next;
    return next;
  }

  Future<void> commit() async {
    pendingEvent = identifier();
    await persist();
    emit();
    unawaited(sync());
  }

  void changed() => unawaited(
    commit().catchError((Object e) {
      error = 'Could not save on this device. Check available storage.';
      emit();
    }),
  );
  Future<void> sync() async {
    if (syncing || !signedIn || conflict) return;
    final epoch = _sessionEpoch;
    final newReports = <String>[];
    syncing = true;
    error = null;
    emit();
    try {
      while (uploads.isNotEmpty) {
        final upload = uploads.first;
        final result = await api.upload(
          upload['client_id'],
          base64Decode(upload['bytes']),
          upload['kind'],
          upload['language'],
        );
        if (epoch != _sessionEpoch) return;
        final i = documents.indexWhere((d) => d['id'] == result['id']);
        if (i < 0) {
          documents.add({...result, 'uploaded': true});
        } else {
          documents[i] = {...result, 'uploaded': true};
        }
        if (result['kind'] == 'Lab Report')
          newReports.add(result['id'] as String);
        uploads.removeAt(0);
        await persist();
        emit();
      }
      while (pendingEvent != null) {
        final event = pendingEvent!;
        final body = jsonDecode(
          jsonEncode({
            'event_id': event,
            'base_version': version,
            'state': snapshot,
          }),
        );
        final result = await api.request('POST', '/sync', body);
        if (epoch != _sessionEpoch) return;
        version = result['version'];
        if (pendingEvent == event) pendingEvent = null;
        await persist();
      }
      final remote = await api.request('GET', '/state');
      if (epoch != _sessionEpoch) return;
      // Never replace edits made while this read was in flight.
      if (pendingEvent == null) {
        hydrate(Map<String, dynamic>.from(remote['state']));
        version = remote['version'];
      }
      final remoteDocs = await api.request('GET', '/documents') as List;
      if (epoch != _sessionEpoch) return;
      final local = documents.where((d) => d['uploaded'] != true).toList();
      final existingReports = {for (final d in documents) d['id']: d};
      documents
        ..clear()
        ..addAll(
          remoteDocs.map((d) {
            final old = existingReports[d['id']];
            final keep =
                old != null &&
                ((old['report_metadata_revision'] as int? ?? 0) >
                    (d['report_metadata_revision'] as int? ?? 0));
            return {
              ...Map<String, dynamic>.from(keep ? old : d),
              'uploaded': true,
            };
          }),
        )
        ..addAll(local);
      needsSignIn = false;
      await persist();
      try {
        await _replenishReminderWindow();
      } catch (_) {}
    } on ApiError catch (e) {
      if (epoch != _sessionEpoch) return;
      if (e.status == 401) needsSignIn = true;
      if (e.status == 409) conflict = true;
      error = e.message;
    } catch (_) {
      if (epoch != _sessionEpoch) return;
      error =
          'Sync unavailable. Locally saved changes will retry when connected.';
    } finally {
      syncing = false;
      emit();
      if (epoch != _sessionEpoch && signedIn) unawaited(sync());
      if (epoch == _sessionEpoch) {
        for (final id in newReports) {
          unawaited(
            classifyReport(id).catchError((Object _) => <String, dynamic>{}),
          );
        }
      }
    }
    if (pendingEvent != null && !conflict && error == null) unawaited(sync());
  }

  Future<void> reloadServer() async {
    final remote = await api.request('GET', '/state');
    hydrate(Map<String, dynamic>.from(remote['state']));
    version = remote['version'];
    pendingEvent = null;
    conflict = false;
    error = null;
    await persist();
    emit();
  }

  /// Upload the selected image independently of account-state conflicts and
  /// unrelated queued images. Never run concurrently with the sync writer.
  Future<void> ensureDocumentUploaded(String id) async {
    final owner = userId, token = api.token, epoch = _sessionEpoch;
    bool sameAccount() =>
        userId == owner && api.token == token && epoch == _sessionEpoch;
    bool uploaded() =>
        documents.any((d) => d['id'] == id && d['uploaded'] == true);
    if (!signedIn || needsSignIn) {
      throw ApiError(401, 'Sign in again before uploading this prescription.');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (syncing) {
      if (!sameAccount())
        throw ApiError(0, 'Your account changed. Open the prescription again.');
      if (uploaded()) return;
      if (DateTime.now().isAfter(deadline)) {
        throw ApiError(
          0,
          'Another sync is still running. Wait for it to finish, then retry the prescription upload.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!sameAccount())
      throw ApiError(0, 'Your account changed. Open the prescription again.');
    if (uploaded()) return;
    final queued = uploads.where((d) => d['id'] == id).toList();
    if (queued.isEmpty) {
      throw ApiError(
        0,
        'The local image is unavailable for upload. Select the prescription photo again.',
      );
    }
    final upload = Map<String, dynamic>.from(queued.first);
    syncing = true;
    emit();
    try {
      final result = await api.upload(
        upload['client_id'],
        base64Decode(upload['bytes']),
        upload['kind'],
        upload['language'],
      );
      if (!sameAccount())
        throw ApiError(0, 'Your account changed. Open the prescription again.');
      if (result['id'] != id) {
        throw ApiError(
          0,
          'The server returned a different document. The queued image was kept; sign in again and retry.',
        );
      }
      final index = documents.indexWhere((d) => d['id'] == id);
      if (index < 0) {
        documents.add({...result, 'uploaded': true});
      } else {
        documents[index] = {...result, 'uploaded': true};
      }
      uploads.removeWhere(
        (d) => d['client_id'] == upload['client_id'] && d['id'] == id,
      );
      await persist();
      emit();
    } on ApiError catch (e) {
      if (sameAccount() && e.status == 401) needsSignIn = true;
      rethrow;
    } finally {
      syncing = false;
      emit();
      if (!sameAccount() && signedIn) unawaited(sync());
    }
  }

  Future<String> queueDocument(
    Uint8List bytes, {
    String? kind,
    String? language,
  }) async {
    if (bytes.length > 12 * 1024 * 1024)
      throw StateError('Choose an image smaller than 12 MB.');
    if (uploads.length >= 5)
      throw StateError('Sync your queued documents before adding more.');
    final client = identifier();
    final hash = await Sha256().hash(utf8.encode('$userId:$client'));
    final id = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, 32);
    currentDocumentId = id;
    document = bytes;
    uploads.add({
      'id': id,
      'client_id': client,
      'bytes': base64Encode(bytes),
      'kind': kind ?? docType,
      'language': language ?? docLanguage,
    });
    documents.insert(0, {
      'id': id,
      'kind': kind ?? docType,
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'ocr_text': '',
      'ocr_status': 'queued',
      'uploaded': false,
    });
    await persist();
    emit();
    await sync();
    return id;
  }

  final _reportClassifications = <String, Future<Map<String, dynamic>>>{};

  Future<Map<String, dynamic>> classifyReport(String id) {
    final key = '$_sessionEpoch:$id';
    return _reportClassifications.putIfAbsent(key, () async {
      try {
        return await _classifyReport(id);
      } finally {
        _reportClassifications.remove(key);
      }
    });
  }

  Future<Map<String, dynamic>> _classifyReport(String id) async {
    final epoch = _sessionEpoch, owner = userId, token = api.token;
    await ensureDocumentUploaded(id);
    if (epoch != _sessionEpoch || owner != userId || token != api.token) {
      throw StateError('Your account changed. Open the report again.');
    }
    final result = Map<String, dynamic>.from(
      await api.request('POST', '/documents/$id/classify') as Map,
    );
    if (result['id'] != id || result['kind'] != 'Lab Report') {
      throw StateError(
        'Report identification returned an invalid response. Retry.',
      );
    }
    if (epoch != _sessionEpoch || owner != userId || token != api.token) {
      throw StateError('Your account changed. Open the report again.');
    }
    final index = documents.indexWhere((d) => d['id'] == id);
    if (index >= 0) {
      final previous = documents[index];
      if ((previous['report_metadata_revision'] as int? ?? 0) <=
          (result['report_metadata_revision'] as int? ?? 0)) {
        documents[index] = {...result, 'uploaded': true};
        await persist();
        emit();
      }
    }
    return result;
  }

  Future<void> updateReportDetails(
    String id,
    Map<String, dynamic> details,
  ) async {
    if (!signedIn || needsSignIn || syncing) {
      throw StateError('Wait for sync to finish and check your connection.');
    }
    final epoch = _sessionEpoch;
    syncing = true;
    emit();
    try {
      final result = await api.request(
        'PATCH',
        '/documents/$id/report',
        details,
      );
      if (epoch != _sessionEpoch) return;
      final index = documents.indexWhere((d) => d['id'] == id);
      if (index != -1) {
        documents[index] = {
          ...Map<String, dynamic>.from(result as Map),
          'uploaded': true,
        };
        await persist();
      }
    } finally {
      syncing = false;
      emit();
      if (signedIn &&
          (epoch != _sessionEpoch ||
              uploads.isNotEmpty ||
              pendingEvent != null)) {
        unawaited(sync());
      }
    }
  }

  Future<Map<String, dynamic>> purchasePlan({
    bool automatic = false,
    bool fullCost = false,
  }) async {
    // commit() starts synchronization in the background. Wait for it rather
    // than treating a normal in-flight save as a failed purchase request.
    final deadline = DateTime.now().add(const Duration(seconds: 65));
    while (syncing) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Sync is taking too long. Retry when connected.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (needsSignIn) {
      throw StateError('Sign in again to fetch prices and prepare your cart.');
    }
    await sync();
    if (pendingEvent != null || conflict || error != null || syncing)
      throw StateError(
        'Sync the current medicine list before estimating your basket.',
      );
    return Map<String, dynamic>.from(
      await api.request('POST', '/shopping/plan', {
        'base_version': version,
        'budget_minor': fullCost || !budgetSet ? null : budget,
        'delivery_minor': delivery,
        'selected_ids': automatic || fullCost ? null : selectedIds.toList(),
      }),
    );
  }

  Future<void> submitCase(String reason, List<String> docs) async {
    await sync();
    if (pendingEvent != null || uploads.isNotEmpty || error != null)
      throw StateError(
        'Sync your record and documents before submitting a review request.',
      );
    await api.request('POST', '/cases', {
      'reason': reason,
      'document_ids': docs,
      'consent': true,
    });
  }

  Future<void> downloadKnowledgePack() async {
    final owner = userId;
    final epoch = _sessionEpoch;
    final result = await api.request('GET', '/knowledge/pack');
    if (owner != userId || epoch != _sessionEpoch)
      throw StateError('Account changed during download.');
    final previous = knowledgePack;
    knowledgePack = Map<String, dynamic>.from(result);
    try {
      await persist();
    } catch (_) {
      knowledgePack = previous;
      emit();
      rethrow;
    }
    emit();
  }

  Future<void> removeKnowledgePack() async {
    final previous = knowledgePack;
    knowledgePack = null;
    try {
      await persist();
    } catch (_) {
      knowledgePack = previous;
      emit();
      rethrow;
    }
    emit();
  }

  Future<void> logout() async {
    try {
      await RetailerSession.clear();
    } catch (_) {}
    _sessionEpoch++;
    knowledgePack = null;
    needsSignIn = false;
    try {
      await notification.cancel();
    } catch (_) {}
    try {
      await api.request('POST', '/auth/logout');
    } catch (_) {}
    await vault.session(null);
    api.token = null;
    userId = null;
    document = null;
    currentDocumentId = null;
    documents.clear();
    uploads.clear();
    medicines.clear();
    vitals.clear();
    doses.clear();
    reminders.clear();
    mealMinutes = [];
    beforeMealMinutes = afterMealMinutes = null;
    preciseReminders = false;
    _lastReminderWindow = null;
    selectedIds.clear();
    pendingEvent = null;
    name = '';
    email = '';
    phone = '';
    allergies = '';
    journal = '';
    mood = '';
    budget = 0;
    delivery = 0;
    conflict = false;
    error = null;
    emit();
  }

  Future<void> _replenishReminderWindow() async {
    final activeUser = userId;
    if (activeUser == null) return;
    final date = dateKey(await notification.localDay(timezone));
    final exactAllowed = await notification.hasDeviceAlarmPermission();
    final key = '$activeUser:$timezone:$date:$exactAllowed';
    if (_lastReminderWindow == key || userId != activeUser) return;
    _lastReminderWindow = key;
    if (!await applyReminders(prompt: false)) _lastReminderWindow = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        sync()
            .then((_) => _replenishReminderWindow())
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    api.close();
    super.dispose();
  }
}

class Scope extends InheritedNotifier<AppState> {
  const Scope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<Scope>()!.notifier!;
}
