# Med.ai — Flutter UI prototype

A responsive Flutter implementation of the MedAI One interactive prototype, including the later price and budget screens. Light surfaces, navy text, blue/violet accents, mint states, generous spacing, and responsive sidebar/mobile navigation.

\## 🎬 Project Demonstration



\### Idea to Unicorn 2026 — Official Competition Demo



Watch our 3-minute English demonstration showcasing Med.ai's AI-powered healthcare capabilities, prescription recognition, RAG-based medical report analysis, medication management, budget optimization, and Ambulance System.



\[!\[Watch Med.ai Demo](https://img.youtube.com/vi/M9BDn0C7zi4/0.jpg)](https://youtu.be/M9BDn0C7zi4)



\*\*\[▶ Watch the Official 3-Minute Demo](https://youtu.be/M9BDn0C7zi4)\*\*Run in VS Code (Windows)

1. Install Flutter stable and the VS Code Flutter extension. Run `flutter doctor` and complete the Android or web prerequisites.
2. Extract this ZIP and open the `med\_ai\_flutter` folder in VS Code.
3. Open **Terminal → New Terminal** in that folder.
4. Generate platform runners once. You can run the included `setup.ps1` script (Windows) or `bash setup.sh` (macOS/Linux), which protects the supplied source while generating runners. Alternatively, run:

```powershell
flutter create --project-name med\_ai --platforms=android,ios,web .
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

Flutter creates the platform boilerplate around the supplied app source. It should retain existing files; keep your original ZIP as a backup. If a default counter test is generated, remove that generated test only; retain `budget\_test.dart` and `widget\_test.dart` from this package.

For Android, start an emulator or connect a phone with USB debugging enabled, run `flutter devices`, then `flutter run -d DEVICE\_ID`. iOS requires macOS/Xcode.

**No API key is needed for this prototype.** The Google Maps button launches a search externally; it does not call Places API or display live pharmacy data in the app.

## iOS photo/camera permissions

After generating the iOS runner, add these entries inside the top-level `<dict>` in `ios/Runner/Info.plist` before testing photo capture:

```xml
<key>NSCameraUsageDescription</key>
<string>Take a photo of your prescription or medical report.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Select a prescription or medical report for preview.</string>
```

This implementation only picks still images and does not require microphone permission. Android image\_picker uses the platform picker/camera; do not add broad storage permissions. Browser camera behavior depends on browser/device support; Choose image and Try a demo document are always the intended fallbacks.

## Included screens and behavior

* **Home:** large health overview, four quick stats, vertically stacked morning/afternoon/night medicines, taken toggles, total medicine cost, shortcut to AI assistant.
* **Scan:** prescription/report mode, device camera and gallery picker, image preview, sample document, staged demo processing, editable extraction, review gate before confirming.
* **Medicine editor:** name, strength, dosage form, frequency, meal, duration, route, special instruction, prescribed quantity, unit price, review checkbox.
* **Medicines:** per-item prices, subtotal/delivery/total, reminder toggles, budget navigation.
* **Budget:** validated budget input, live selected basket calculations, Included/Not Included states, affordable individual quantities, remaining amount/shortfall, session save.
* **Nearby:** illustrative map with selectable pins/cards and real external Google Maps search by area or near me.
* **Health:** sample metrics and trend graphics, device-integration explanation.
* **AI assistant:** interactive message UI with explicitly scripted demo replies.
* **Care finder:** category/area selection and real external Google Maps search.
* **Records:** sample record details and current saved budget plan.
* **Settings:** demo profile, privacy preference preview, integration transparency.

## Exact budget example

|Item|Quantity|Unit price|Total|
|-|-:|-:|-:|
|Demo Medicine A|30|৳10|৳300|
|Demo Medicine B|20|৳15|৳300|
|Demo Medicine C|10|৳20|৳200|

All medicines: ৳800 + ৳50 delivery = ৳850.
Default budget: ৳650. A and B selected: ৳600 + ৳50 = ৳650. C is Not Included. Remaining budget: ৳0.

`Affordable individually` means `min(prescribed quantity, floor(max(0, budget − delivery) / unit price))`. Each line independently uses the entire budget; these quantities are not a jointly optimized basket and are not dose recommendations. Selection includes/excludes whole prescribed quantities. An empty basket has no delivery fee. No clinical priority or automatic dose rationing is implemented.

## What is real and what is demo

**Real local behavior:** navigation, image selection/capture via image\_picker, preview, form validation/editing, review flags, arithmetic, basket selections, preference/taken toggles, session state, message entry, external map search.

**Demo:** OCR/AI extraction (fixed sample values regardless of image), medicine names/prices, laboratory values, pharmacy cards/distances/map, health readings, chat replies, reminders, device connections, records/profile. No order, payment, notifications, diagnosis, authentication, cloud upload or stock lookup occurs. State is in memory only and resets on restart. Photo bytes remain in app memory and are not sent to an AI service.

## Source organization

* `lib/main.dart`: theme and responsive navigation shell.
* `lib/models.dart`: shared local state and budget arithmetic.
* `lib/widgets/ui.dart`: shared visual components.
* `lib/screens/dashboard.dart`: home.
* `lib/screens/scan.dart`: document/photo and review flow.
* `lib/screens/medicines.dart`: editor, price summary, budget calculator.
* `lib/screens/other.dart`: pharmacy map illustration, health, chat, care, records, settings.
* `test/budget\_test.dart`: budget, delivery, quantity bounds, price-edit regression tests.
* `test/widget\_test.dart`: responsive dashboard and budget input tests.

## Connect production services later

Replace the fixed scan outputs with your OCR backend and map its eight extraction fields to `Medicine`. Retain explicit user review and uncertainty. Fetch medicine prices and stock from a pharmacy/inventory integration. Replace sample pharmacy cards with server-side Places Nearby Search results; restrict keys and configure billing quotas. Add secure persistence/authentication, real notification scheduling, and authorized device APIs as separate integrations.

Do not put a private AI/Places web-service key in Dart source. A publicly shipped mobile app cannot keep such a secret.

## Validation status

See `VALIDATION.md` for what was checked in the build environment. Run the Flutter checks above on your machine before treating this as a tested mobile build.

## Official setup references

* https://docs.flutter.dev/reference/create-new-app
* https://docs.flutter.dev/cookbook/design/themes
* https://pub.dev/packages/image\_picker
* https://pub.dev/packages/url\_launcher

