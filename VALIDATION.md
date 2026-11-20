# Medicine Workflow Release 3 — validation

## Executed checks

- **44 backend tests passed**, using isolated databases/keys. Coverage includes authentication/account isolation, encryption, synchronization/revision conflicts, document ownership, clinician consent, reviewed-reference retrieval, and the new medicine workflow. New checks cover strict source URLs, product/pack/price validation, server-owned account-scoped quotes, stale quotes, quantity-unit matching, whole-pack budgets, unknown prices, purchased items, duplicate cart matches, OCR candidate validation and location input bounds.
- **Full Dart static analysis: no issues found**, including application and test source. Dependencies were resolved against public Flutter 3.35 framework sources using standalone Dart 3.13.7. This is static analysis, not an engine/device run.
- Standalone Dart purchase checks passed: pack rounding, integer-paisa totals, unit/form aliases and invalid pack rejection. Standalone reviewed-reference checks passed.
- **Four Android configuration tests passed**, covering Kotlin/Groovy configuration, idempotency, notification receivers/permissions, desugaring, retained settings and safe launch-resource backups, including migration of old backups out of Android resources.
- Node cart-assistant checks passed: supplier origin, product identity, pack/price matching, quantity bounds, pending-click deduplication, existing cart and login pauses.
- **Real Chromium local DOM fixture passed**: adds exactly two sales packs, verifies resulting quantity, blocks a changed price, and never clicks Place Order. This is a local synthetic supplier-page fixture, not an authenticated live retailer checkout test.
- A live public Arogga product fetch succeeded through the price adapter: the tested Napa 500 listing exposed a 10-tablet strip and a BDT 11.40 pack price at check time. This observation is not a fixed catalogue value or a price guarantee; the app fetches current values.
- An actual local Uvicorn HTTP smoke check passed: startup/health, protected endpoints, registration, medicine synchronization, source-snapshot quote retrieval, whole-pack selection, shortfall calculation and the truthful not-configured OCR capability. No retailer cart/order/payment was touched.
- Python source compilation checks passed. Existing artwork assets were retained.

The backend tests emit one upstream Starlette/httpx TestClient deprecation warning; all tests pass.

## Not executed or not provided

- Flutter widget/model test execution under the Flutter engine, rendered phone visual QA, Android/iOS compilation or APK installation.
- Samsung camera, secure storage, GPS, WebView cookies/login and native alarm delivery/battery behavior. Run the device acceptance steps in MEDICINE_RELEASE_WINDOWS.md.
- Windows execution of the PowerShell updater/runner. Their native configuration Python components were tested separately.
- Live authenticated Arogga cart preparation or checkout. A read-only browser attempt encountered a certificate-authority error; certificate validation was not disabled. The public price fetch succeeded separately. Retailer UI changes may require updating the conservative assistant.
- Automatic address entry, prescription approval, final order submission or payment. These remain manual on the supplier website.
- A trained handwriting/structured-prescription OCR checkpoint. The adapter and review flow are implemented; default behavior offers manual entry without fabricated candidates.
- Clinical efficacy evaluation, security penetration testing, recovery drills, production deployment or retail partnership approval.

No Flutter CLI bootstrap was retried after its earlier blocked metadata access. A clean static analyzer result is not an Android build result. Run `flutter test` and the phone acceptance sequence locally before relying on native features.
