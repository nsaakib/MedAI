/* Med.ai: normal visible product controls only. No requests, tokens or checkout clicks. */
// Arogga's live login sheet has no role=dialog. Detect rendered login inputs
// as well as accessible dialogs; never inspect or copy their entered values.
function medaiLoginRequired(doc = document) {
  const visible = el => el && !el.hidden &&
    (typeof el.getClientRects !== 'function' || el.getClientRects().length > 0);
  const fields = Array.from(doc.querySelectorAll('input'));
  if (fields.some(el => visible(el) &&
      /phone number|mobile number|enter.*otp|verification code|one.time.code/i.test(
        [el.getAttribute('placeholder'), el.getAttribute('aria-label'),
         el.getAttribute('autocomplete')].filter(Boolean).join(' ')))) return true;
  return Array.from(doc.querySelectorAll('[role="dialog"], [aria-modal="true"]'))
    .some(el => visible(el) && /login|log in|sign in|otp|verification|phone number|captcha/i.test(el.innerText));
}
// Read only the visible "Select quantity" popup. A strip is the priced pack
// for this layout; both the tablet total and strip count must agree.
function medaiStripPicker(q, doc, visible, norm) {
  const labels = 'button,li,[role="option"],[role="menuitem"],div,span,p,label,h2,h3,h4';
  const leaf = (el, matches) => visible(el) && matches(norm(el.textContent)) &&
    !Array.from(el.children).some(child => matches(norm(child.textContent)));
  const heading = t => /^select\s+(?:a\s+)?quantity\s*[:*]?$/.test(t);
  const headings = Array.from(doc.querySelectorAll(labels)).filter(el => leaf(el, heading));
  if (!headings.length) return null;
  const strip = /^(\d+)\s*(tablets?|capsules?)\s*\(\s*(\d+)\s*strips?\s*\)$/;
  const base = strip.exec(norm(q.pack_label));
  if (headings.length !== 1 || !base || Number(base[3]) !== 1 ||
      !Number.isSafeInteger(q.units_per_pack) || q.units_per_pack < 1 ||
      Number(base[1]) !== q.units_per_pack) return {};
  let panel = headings[0].parentElement;
  for (let depth = 0; panel && depth < 5 && !/^(BODY|HTML|MAIN)$/i.test(panel.tagName);
       depth++, panel = panel.parentElement) {
    const rows = Array.from(panel.querySelectorAll(labels)).filter(el => leaf(el, t => strip.test(t)));
    if (!rows.length) continue;
    const matches = rows.filter(el => {
      const [, units, form, strips] = strip.exec(norm(el.textContent));
      return Number(strips) === q.target_packs &&
        form.replace(/s$/, '') === base[2].replace(/s$/, '') && Number(units) === q.target_packs * q.units_per_pack;
    });
    if (matches.length !== 1) return {};
    // Click the exact label; the event bubbles to Arogga's row handler.
    const option = matches[0];
    if (option.closest('a,[disabled],[aria-disabled="true"],[aria-busy="true"],[inert],button[type="submit"]')) return {};
    return {option};
  }
  return {};
}

// Arogga's mobile cart button is identified by the cart artwork; its text
// alone can omit the word Cart. A positive badge is only a consistency check,
// never evidence of the exact product or quantity by itself.
function medaiCartIconButtons(doc, win, visible) {
  const origin = win.location.href || 'https://www.arogga.com';
  const buttons = Array.from(doc.querySelectorAll('img[src]')).filter(img => {
    try {
      const src = new URL(img.getAttribute('src'), origin);
      const asset = src.pathname === '/_next/image' ? new URL(src.searchParams.get('url') || '/', origin) : src;
      return src.origin === new URL(origin).origin &&
        asset.origin === src.origin && asset.pathname === '/assets/svg/icon-v2/cart.svg';
    } catch (_) { return false; }
  }).map(img => img.closest('button')).filter(visible);
  return [...new Set(buttons)];
}

function medaiCartBadgeCount(doc, win, visible) {
  const buttons = medaiCartIconButtons(doc, win, visible);
  if (buttons.length !== 1) return null;
  const labels = Array.from(buttons[0].querySelectorAll('span')).filter(visible)
    .map(el => el.textContent.trim()).filter(text => /^\d+$/.test(text));
  if (labels.length === 0) return 0; // Arogga omits the badge for an empty cart.
  return labels.length === 1 ? Number(labels[0]) : null;
}

function medaiCartStep(q, doc = document, win = window) {
  const norm = s => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const visible = el => el && !el.hidden && (typeof el.getClientRects !== 'function' || el.getClientRects().length > 0);
  // WebView futures cannot cancel a queued evaluation. An evaluation from
  // an older row must become harmless even if the platform delivers it late.
  if (Number.isFinite(q.deadline_ms) && Date.now() >= q.deadline_ms)
    return {status:'manual',message:'The verification step expired. No additional click was sent.'};
  if (q.run_token && new URLSearchParams(win.location.search || '').get('_medai_run') !== q.run_token)
    return {status:'waiting',message:'Waiting for the assigned fresh product page.'};
  if (win.location.protocol !== 'https:' || !['www.arogga.com', 'arogga.com'].includes(win.location.hostname)) return {status:'blocked',message:'Not on the supplier origin.'};
  if (((q.run_token || q.previous_document) && doc.readyState === 'loading') ||
      (q.previous_document && win.__medaiBeforeNavigation === q.previous_document))
    return {status:'waiting',message:'Waiting for a fresh Arogga product page.'};
  if (!Number.isInteger(q.target_packs) || q.target_packs < 1 || q.target_packs > 100) return {status:'manual',message:'Use supplier controls for this quantity.'};
  if (medaiLoginRequired(doc)) return {status:'login_required',message:'Arogga requires sign-in. Enter your phone number and OTP in the Arogga panel below. When it closes, tap Fill / Resume Cart. No item is confirmed added yet.'};
  const root = doc.getElementById(`product-${q.product_id}-variant-${q.variant_id}`);
  if (!root) return {status:'waiting',message:'Waiting for the exact product page.'};
  const title = root.querySelector('h1');
  const variant = root.querySelector(`[data-pv-id="${q.variant_id}"]`);
  const label = variant && variant.querySelector('.product_single_label_generate');
  const price = variant && variant.querySelector('.product_single_price_generate');
  if (!title || !variant || !label || !price) return {status:'waiting',message:'Waiting for product title, pack and price controls.'};
  if (norm(title.textContent) !== norm(q.product_name)) return {status:'manual',message:'Product title differs from the reviewed estimate.'};
  const packPattern = /^(\d+)\s*(tablets?|capsules?)\s*\(\s*(\d+)\s*strips?\s*\)$/;
  const basePack = packPattern.exec(norm(q.pack_label));
  const livePack = packPattern.exec(norm(label.textContent));
  const compatiblePack = basePack && livePack && Number(basePack[3]) === 1 &&
    Number(basePack[1]) === q.units_per_pack && livePack[2].replace(/s$/, '') === basePack[2].replace(/s$/, '') &&
    Number(livePack[1]) === Number(livePack[3]) * q.units_per_pack;
  if (norm(label.textContent) !== norm(q.pack_label) && !compatiblePack)
    return {status:'manual',message:'Pack label differs from the reviewed estimate.'};
  const amount = price && Number(String(price.textContent).replace(/[^0-9.]/g,''));
  if (!Number.isFinite(amount) || !Number.isSafeInteger(q.pack_price_minor) || q.pack_price_minor <= 0) return {status:'manual',message:'Supplier price could not be verified.'};
  const pending = win.__medaiPending;
  const sameItem = pending && pending.id === q.product_id && pending.variant === q.variant_id && pending.target === q.target_packs;
  const picker = medaiStripPicker(q, doc, visible, norm);
  if (picker) {
    if (!sameItem || !['add','select','picked'].includes(pending.phase))
      return {status:'manual',message:'An untracked quantity menu is open. Review it manually.'};
    if (pending.phase === 'picked')
      return Date.now() - pending.at >= 20000 ? {status:'manual',message:'Quantity menu did not close after selection. Review the supplier cart.'} : {status:'waiting',message:'Waiting for quantity selection acknowledgement.'};
    if (!picker.option) return Date.now() - pending.at >= 12000 ? {status:'manual',message:'The exact reviewed strip quantity was not found in the supplier menu.'} : {status:'waiting',message:'Waiting for exact strip quantity options.'};
    // Initial product and price were checked before opening this exact menu.
    // Do not depend on underlying Add to Cart being visible behind the modal.
    win.__medaiPending = {...pending, phase:'picked', at:Date.now()};
    picker.option.click();
    return {status:'clicked',before:pending.before,message:'Selected the requested quantity. Waiting for Arogga to confirm it.'};
  }
  const scope = variant.parentElement;
  const buttons = Array.from(scope.querySelectorAll('button')).filter(visible);
  const addCandidates = buttons.filter(b => /^add\s*to\s*cart$/i.test(norm(b.textContent)) ||
    /^add\s*to\s*cart$/i.test(norm(b.getAttribute('aria-label'))));
  if (addCandidates.length > 1) return {status:'manual',message:'Multiple Add to Cart controls found for the variant.'};
  const add = addCandidates[0];
  if (buttons.some(b => /^loading\s*add to cart$/i.test(norm(b.textContent))))
    return {status:'waiting',message:'Waiting for Arogga to finish initializing its cart controls.'};
  // Arogga renders cart quantity as a labelled button after strip selection.
  // The displayed price then becomes the selected-quantity total.
  const stripPattern = /^(\d+)\s*(tablets?|capsules?)\s*\(\s*(\d+)\s*strips?\s*\)$/;
  const selectedButtons = buttons.filter(b => stripPattern.test(norm(b.textContent)));
  if (selectedButtons.length > 1) return {status:'manual',message:'Multiple quantity controls are visible. Review the supplier cart.'};
  const selected = selectedButtons[0];
  let count = 0, plus;
  if (selected) {
    const base = stripPattern.exec(norm(q.pack_label));
    const parts = stripPattern.exec(norm(selected.textContent));
    if (add || !base || Number(base[3]) !== 1 ||
        !Number.isSafeInteger(q.units_per_pack) || q.units_per_pack < 1 ||
        Number(base[1]) !== q.units_per_pack ||
        parts[2].replace(/s$/, '') !== base[2].replace(/s$/, '') ||
        Number(parts[1]) !== Number(parts[3]) * q.units_per_pack)
      return {status:'manual',message:'Selected unit and strip counts do not match the reviewed pack.'};
    count = Number(parts[3]);
  }
  if (!add && !selected) {
    const inputs = Array.from(scope.querySelectorAll('input[type="number"], [role="spinbutton"]')).filter(visible);
    const input = inputs.length === 1 ? inputs[0] : null;
    if (input) count = Number(input.value || input.getAttribute('aria-valuenow'));
    else {
      const counts = Array.from(scope.querySelectorAll('span')).filter(visible).map(s=>s.textContent.trim()).filter(t=>/^\d{1,4}$/.test(t));
      const unique = [...new Set(counts)];
      if (unique.length !== 1) return {status:'waiting',message:'Waiting for a recognizable quantity control.'};
      count = Number(unique[0]);
    }
    plus = buttons.find(b => /^\+$/.test(b.textContent.trim()) || /^(increase|increment|add)( item)? quantity$/i.test(b.getAttribute('aria-label') || b.getAttribute('title') || ''));
  }
  if (!Number.isInteger(count) || count < 0) return {status:'manual',message:'Quantity control is unclear.'};
  // A cached product label can survive removal while the cart badge is zero.
  // The supplier quantity menu sets the absolute quantity (not an increment).
  // Re-select the exact reviewed quantity once; do not open the cart drawer,
  // whose network-dependent open handler can stall even when the picker works.
  const badge = medaiCartBadgeCount(doc, win, visible);
  const needsReconcile = !!selected && badge === 0;
  const expectedMinor = q.pack_price_minor * (selected ? count : 1);
  if (!Number.isSafeInteger(expectedMinor) || Math.round(amount*100) !== expectedMinor)
    return sameItem && Date.now() - pending.at < 12000 ? {status:'waiting',message:'Waiting for supplier price to update after the quantity action.'} : {status:'manual',message:'Supplier price changed for the verified quantity. Refresh your estimate before continuing.'};
  if (count > q.target_packs) return {status:'manual',message:'Your existing supplier cart has more of this product. Review it manually; nothing was removed.'};
  if (count === q.target_packs && badge !== null && badge > 0 && (selected || plus) &&
      !(sameItem && count <= pending.before && ['add','select'].includes(pending.phase))) {
    win.__medaiPending = null;
    return {status:'ready',count};
  }
  if (sameItem && (pending.phase === 'picked' || count <= pending.before)) {
    if (Date.now() - win.__medaiPending.at >= 20000)
      return {status:'manual',message:pending.phase === 'picked'
        ? 'Arogga has not confirmed the selected quantity and cart badge. No repeat selection was sent. Open Supplier Cart to check the saved items, then resume.'
        : 'Arogga did not acknowledge the cart click. Nothing more was clicked. Use Fill / Resume to reload the page, verify its saved quantity and retry.'};
    return {status:'waiting',message:'Waiting for supplier acknowledgement; no duplicate click is sent.'};
  }
  if (selected && badge === null)
    return {status:'waiting',message:'Waiting for the supplier cart indicator before changing quantity.'};
  if (selected && count === q.target_packs && !needsReconcile)
    return {status:'waiting',message:'Waiting for Arogga to confirm the selected quantity.'};
  if (count === q.target_packs && !needsReconcile) return {status:'waiting',message:'Waiting for cart indicator confirmation.'};
  const button = add || selected || plus;
  if (!button || button.disabled || button.getAttribute('aria-busy') === 'true' || button.closest('[disabled],[aria-disabled="true"],[inert],button[type="submit"]')) return {status:'waiting',message:'Waiting for supplier controls.'};
  // A server-rendered Next page can show an enabled button before React
  // attaches handlers. A synthetic click then does nothing.
  if ((win.__next_f || win.__NEXT_DATA__) &&
      !Object.keys(button).some(k => /^__react(?:Props|Fiber|Events)/.test(k)))
    return {status:'waiting',message:'Waiting for the supplier button to become interactive.'};
  win.__medaiPending = {id:q.product_id,variant:q.variant_id,target:q.target_packs,
    phase:add ? 'add' : selected ? 'select' : 'increment',before:count,at:Date.now()};
  button.click();
  return {status:'clicked',before:count,message:needsReconcile
    ? 'Restoring the reviewed quantity through Arogga’s quantity menu…'
    : 'Opening the supplier quantity control…'};
}
// Called only after the user opts in. It touches the visible Arogga sign-in
// form, never requests SMS access or reads an OTP.
function medaiPrepareOtp(doc = document, win = window) {
  if (win.location.protocol !== 'https:' || win.location.port ||
      !['www.arogga.com','arogga.com'].includes(win.location.hostname)) return;
  const fields = Array.from(doc.querySelectorAll('input[placeholder="Enter OTP"]'))
    .filter(el => !el.hidden && el.getClientRects().length > 0);
  if (fields.length !== 1 || !fields[0].closest('form')) return;
  fields[0].setAttribute('autocomplete', 'one-time-code');
  fields[0].setAttribute('inputmode', 'numeric');
}

function medaiSendLogin(phone, doc = document, win = window) {
  if (win.location.protocol !== 'https:' || win.location.port || !['www.arogga.com','arogga.com'].includes(win.location.hostname))
    return 'blocked';
  if (!/^01[3-9]\d{8}$/.test(phone)) return 'manual';
  const visible = el => el && !el.hidden && el.getClientRects().length > 0;
  const fields = Array.from(doc.querySelectorAll('input[placeholder="Enter phone number"]')).filter(visible);
  if (fields.length !== 1) return 'manual';
  const input = fields[0];
  const form = input.closest('form');
  if (!form || input.disabled || input.readOnly || form.querySelector('input[placeholder="Enter OTP"]'))
    return 'manual';
  if (!Array.from(form.querySelectorAll('button')).some(b => visible(b) && /\+880?\)?\s*BD/i.test(b.textContent)))
    return 'manual';
  const buttons = Array.from(form.querySelectorAll('button[type="submit"]'))
    .filter(b => visible(b) && /^send$/i.test(b.textContent.trim()));
  if (buttons.length !== 1) return 'manual';
  if (win.__medaiSentLogin) return 'sent';
  const button = buttons[0];
  if ((win.__next_f || win.__NEXT_DATA__) && !Object.keys(button).some(k => /^__react(?:Props|Fiber|Events)/.test(k)))
    return 'manual';
  if (input.value && input.value !== phone) return 'manual';
  if (input.value !== phone) {
    const setter = Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype, 'value')?.set;
    if (!setter) return 'manual';
    setter.call(input, phone);
    input.dispatchEvent(new win.Event('input', {bubbles:true}));
    return input.value === phone ? 'filled' : 'manual';
  }
  if (button.disabled) return 'filled';
  win.__medaiSentLogin = true;
  button.click();
  return 'sent';
}
if (typeof module !== 'undefined') module.exports = {medaiCartStep, medaiLoginRequired, medaiOpenSupplierCart, medaiSendLogin};

function medaiOpenSupplierCart(doc = document, win = window) {
  if (win.location.protocol !== 'https:' || !['www.arogga.com','arogga.com'].includes(win.location.hostname)) return 'blocked';
  const icons = medaiCartIconButtons(doc, win, b => b && !b.hidden && !b.disabled && b.getClientRects().length > 0);
  if (icons.length === 1) { icons[0].click(); return 'opened'; }
  if (icons.length > 1) return 'manual';
  const candidates = Array.from(doc.querySelectorAll('button,a[href]')).filter(b => {
    if (b.disabled || !b.getClientRects().length) return false;
    const name = (b.getAttribute('aria-label') || b.getAttribute('title') || b.textContent || '').trim();
    if (/^(?:\d*\s*cart|open (?:shopping )?cart|shopping cart|view cart)$/i.test(name)) return true;
    const href = b.getAttribute('href');
    if (!href) return false;
    try {
      const u = new URL(href, win.location.href || 'https://www.arogga.com');
      return ['www.arogga.com','arogga.com'].includes(u.hostname) && u.protocol === 'https:' && /^\/cart\/?$/.test(u.pathname);
    } catch (_) { return false; }
  });
  if (candidates.length !== 1) return 'manual';
  candidates[0].click();
  return 'opened';
}
