# Arogga price and cart integration

## Implemented now

The app opens Arogga's real search in an on-device WebView. A user selects the exact prescribed product or pastes its product link. The backend reads that product's public HTML and JSON-LD; it does not call an undocumented private API, enumerate a medicine catalogue or use a paid search service. It verifies the displayed price against structured BDT price data, reads strength/form/base unit/sales unit and rejects ambiguous or conflicting listings. It uses bounded responses, timeouts, a two-minute source cache and account-scoped encrypted quote records. A quote is usable for up to 24 hours from its source-check time; checkout can still differ.

Unit estimates are derived from the actual sales pack. Procurement totals round up to whole packs and use integer paisa, not rounded unit price multiplied by prescription quantity. A quantity-unit confirmation prevents interpreting strips as tablets or millilitres as bottles. The prescribed strength/form must match the selected listing; brand identity is also checked explicitly by the user. The app does not substitute a cheaper brand or invent a missing price.

A manual price entry remains available for offline/shop estimates, but it cannot qualify for automated Arogga cart filling. Unknown/expired/unmatched prices are not zero and leave the full estimate incomplete. Delivery is a user-entered reserve; the app does not promise a live shipping quote, coupon eligibility, tax amount, stock reservation or final payable total.

## Cart assistant

After the user reviews a basket and enables assistance, the app's WebView script:

1. Checks that it is on Arogga's HTTPS origin and the reviewed product/variant.
2. Verifies the visible name, sales-pack label and current displayed price.
3. Reads the quantity from the product's normal visible cart controls.
4. Clicks Add To Cart or an explicit increase-quantity control one step at a time, waiting for acknowledgement rather than blindly repeating a click.
5. Stops when the expected quantity is visible, or pauses for any mismatch, login/OTP prompt, unreadable control, timeout or existing higher cart quantity.

It does not remove existing cart items, fill payment credentials, read OTP input values, call private cart endpoints, bypass CAPTCHA/verification, submit prescriptions, press Place Order or make payment. Supplier login/storage is kept in the native WebView, not sent to the Med.ai backend. Browser session state is cleared on Med.ai account changes/sign-out and can be cleared using the session button. Users must still verify which supplier account/cart is active.

The native **Open Supplier Cart** action can open a uniquely identified visible cart button. **The implemented automation boundary is cart preparation, not a guaranteed end-to-end pre-payment checkout bot.** Address entry, prescription upload/verification, checkout, order submission and payment remain manual in the supplier interface. This is necessary because no documented public cart/checkout API was identified during this research, and live authentication/checkout behavior has not been verified here.

The assistant is conservative, limited to 20 distinct medicine rows and 100 packs per row. Duplicate supplier-product matches disable automated preparation until the user reviews/merges duplicate medicine entries. Source/layout changes may require updating the adapter. If controls cannot be verified, users can use the supplier page manually. No real customer order/payment was submitted during development. JavaScript logic passed synthetic-DOM tests; live authenticated cart filling has not been verified on the user's phone.

## What production integration requires

Arogga's terms describe prescription verification and restrictions on unauthorized commercial use. A product integration needs a confirmed supplier arrangement, supported catalogue/price/cart contracts, allowed use of source content, and a test account/environment. We did not contact Arogga or obtain partner credentials. Browser automation is not equivalent to an authorized retail partnership or stable API. A supported partner API can replace `backend/app/market.py` and the WebView cart adapter without changing medicine records or the UI theme.

## Research sources

- Arogga terms: https://www.arogga.com/page/tos
- Arogga FAQ: https://www.arogga.com/page/faqs
- Representative public product inspected: https://www.arogga.com/product/12474/napa-500-tablet-500mg
- Official WebView package: https://pub.dev/packages/webview_flutter

Search-engine prices may be stale; runtime estimates come from the fetched source listing. These links document the implementation investigation, not a recommendation to take a medicine or assurance that automation remains compatible.
