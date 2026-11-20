# Med.ai medicine workflow release — start here

This is an update to your existing Flutter/FastAPI project. The navy, cyan/blue/violet gradients, vector logo, cards, typography, artwork and bottom navigation are retained. Medicine capture/entry, reminders, live price lookup, budgets and a pharmacy map are connected to actual data/services. Your trained OCR model is not bundled.

## Install into D:\med_ai_flutter

1. Stop the running Flutter process and backend (Ctrl+C in each terminal). Extract the new ZIP separately; do not merge its old and new Dart source folders by hand.
2. In a PowerShell terminal opened in the extracted **med_ai** folder, run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\INSTALL_UPDATE.ps1" -Project "D:\med_ai_flutter"
   ```

   The installer backs up old lib/test/assets/tool and backend app/static/tests outside your project, copies the new code, and configures Android desugaring, notification receivers, location permissions and the navy native launch screen. It preserves your existing android runner, Java/Gradle versions, signing configuration, backend `.env`, database, uploaded documents and virtual environment. It also moves old `.medai-backup` files out of Android `res`, fixing the resource-merger error from the earlier startup script.
3. In your first VS Code PowerShell terminal:

   ```powershell
   cd D:\med_ai_flutter
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\START_BACKEND.ps1"
   ```

   Keep this terminal open. New backend packages install into the existing venv. Startup adds a quote table automatically; it does not replace patient records or regenerate an existing encryption key. The health response at `http://127.0.0.1:8000/health` should report version **1.2.0**.
4. With your Samsung A52 unlocked and connected by USB, in a second terminal:

   ```powershell
   cd D:\med_ai_flutter
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\RUN_SAMSUNG_USB.ps1"
   ```

   This uses device **R58RC2S3KND**, maps phone port **18000** to PC port **8000**, gets Flutter packages, analyzes source, and runs the app. For a different device, pass `-Device YOUR_DEVICE_ID`. Reapply the mapping after disconnect/reboot. No LAN IP is needed for this USB workflow.

For a new project with no native runner, start with `START_HERE_WINDOWS.md`, then run both configuration scripts against that project. Back up the backend `.env` with its data folder. Never copy a new key over an existing database.

## Use the medicine workflow

1. Home → **Add Medicine** creates an item manually. Enter exactly the prescription's name, strength, form, frequency, meal timing, duration, route and special instructions that are available. Enter the total prescribed purchase quantity; unknown fields can stay blank. The unit price is optional. Check the review box only after comparing with the prescription.
2. Home → **Scan Prescription** opens camera/gallery capture. Save the image securely, then choose **Read / Review Prescription**. Until the structured OCR model is connected, the app says so and offers manual entry from the saved image; it does not invent a medicine list. Once your model is connected, candidates appear in the same review screen and can be edited/saved. See `OCR_MODEL_INTEGRATION.md`.
3. In **Your Medicines**, choose **Set reminder times**. Add daily times for reviewed medicines, select the timezone, and press **Save and Schedule**. Grant notification and Alarms & reminders access for precise scheduling. Reminders repeat daily until disabled/removed; treatment duration and free-text frequency are not automatically interpreted. Reschedule after installing this update because notification IDs are now stable across list reordering. These are scheduled medication notifications, not a full-screen clock-alarm app.
4. If a medicine is already bought, turn on **Already purchased**. It remains in the medicine/reminder list and is excluded from procurement costs.
5. Open **Prices & Budget**. For each unpurchased medicine, choose **Find Online Price**, use Arogga's real search page, select the exact product, then tap **Use This Product Listing**. Alternatively paste an exact product link. The server fetches its public listing and validates displayed price, BDT currency, strength, form and sales-pack size. Confirm the brand and that your entered quantity means the displayed individual base units, not packs.
6. **View Total** shows the known full purchase estimate including a delivery reserve. Supplier prices are real retrieved values, not bundled demo prices. The delivery reserve is user-entered; final shipping/taxes/coupons are confirmed by Arogga. Missing or expired prices keep the estimate explicitly incomplete. You can enter a manually checked unit price when a listing cannot be found; manual prices do not qualify for automatic cart filling.
7. Accept the full estimate or **Set My Budget**. The calculator selects complete prescribed quantities in medicine-list order, accounting for whole sales packs. It displays the shortfall, individual affordability, and Included/Not Included states. It does not rank clinical importance, substitute medicines, change a dose or shorten a prescribed course. Review exclusions with a pharmacist.
8. **Review Budget Basket → Prepare Cart on Arogga** opens an on-device supplier WebView. Allow the assistant to verify the exact product/pack/price and add packs using visible website controls. It pauses on login/OTP, unknown controls, mismatches and existing higher quantities. It does not bypass verification or clear pre-existing cart items. Open the supplier cart, review everything and finish address/prescription verification/order submission/payment manually. Read the limits in `AROGGA_INTEGRATION.md`.
9. **Buy at a Nearby Pharmacy** opens a real OpenStreetMap-based map after you grant location access. It lists actual mapped pharmacies with distances/directions and reported contact details, not fictional stock. If coverage or the public map search fails, use the external Google Maps search. An area can be entered without granting GPS permission.

## What still needs verification on your phone

Run `flutter test`, then check camera access, secure storage, notification/precise-alarm permissions, notification delivery with the screen locked, GPS permission denial, map tiles, and Arogga login/cart behavior. The browser bot is best-effort source code, not a verified retail partnership or a guaranteed checkout integration. No live customer order or payment was submitted during development.

See `VALIDATION.md` for executed checks and limitations. This release does not validate OCR accuracy, diagnose conditions or provide treatment recommendations.
