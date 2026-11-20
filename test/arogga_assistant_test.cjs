const assert=require('node:assert/strict');
const {medaiCartStep,medaiLoginRequired,medaiOpenSupplierCart}=require('../assets/arogga_assistant.js');
const quote={product_id:'42',variant_id:'43',product_name:'Test Brand',pack_label:'10 Tablets (1 Strip)',pack_price_minor:1140,target_packs:2,units_per_pack:10};
function fixture(){
 const s={count:0,clicks:0,price:'৳11.40',title:'Test Brand',pack:'10 Tablets (1 Strip)',dialog:null,quantityKnown:true};
 const button=(text,action,aria='')=>({textContent:text,disabled:false,hidden:false,getClientRects:()=>[{}],scrollIntoView:()=>assert.fail('Product button must not jump the page'),getAttribute:n=>n==='aria-label'?aria:null,click:()=>{s.clicks++;action();}});
 const add=button('Add To Cart',()=>{}),plus=button('+',()=>{},'Increase quantity');
 const scope={querySelectorAll:sel=>sel==='button'?s.count===0?[add]:[plus]:sel==='span'&&s.count>0?[{textContent:String(s.count)}]:[],querySelector:sel=>s.count>0&&s.quantityKnown?{value:String(s.count)}:null};
 const variant={parentElement:scope,querySelector:sel=>({textContent:sel.includes('label')?s.pack:s.price})};
 const root={querySelector:sel=>sel==='h1'?{textContent:s.title}:sel.startsWith('[data-pv-id=')?variant:null};
 const cart={hidden:false,disabled:false,getClientRects:()=>[{}],click:()=>{s.cartOpens=(s.cartOpens||0)+1;},
  querySelectorAll:()=>s.badge===undefined?[]:[{textContent:String(s.badge)}]};
 const cartImage={getAttribute:()=>s.cartAsset||'/assets/svg/icon-v2/cart.svg',closest:()=>cart};
 const doc={querySelectorAll:sel=>sel==='img[src]'?(s.showCart?[cartImage]:[]):sel==='input'?(s.loginFields||[]):(sel.includes('h4')?(s.picker?[s.picker]:[]):(s.dialog?[s.dialog]:[])),querySelector:()=>s.dialog,getElementById:id=>id==='product-42-variant-43'?root:null};
 const win={location:{protocol:'https:',hostname:'www.arogga.com'}};
 return {s,doc,win};
}
let f=fixture();f.win.location.hostname='evil.example';assert.equal(medaiCartStep(quote,f.doc,f.win).status,'blocked');assert.equal(f.s.clicks,0);
f=fixture();f.s.price='৳12.00';assert.equal(medaiCartStep(quote,f.doc,f.win).status,'manual');assert.equal(f.s.clicks,0);
f=fixture();f.s.title='Different Brand';assert.equal(medaiCartStep(quote,f.doc,f.win).status,'manual');
f=fixture();f.s.pack='20 Tablets';assert.equal(medaiCartStep(quote,f.doc,f.win).status,'manual');
f=fixture();assert.equal(medaiCartStep(quote,f.doc,f.win).status,'clicked');assert.equal(f.s.clicks,1);assert.equal(medaiCartStep(quote,f.doc,f.win).status,'waiting');assert.equal(f.s.clicks,1);
f.s.count=1;assert.equal(medaiCartStep(quote,f.doc,f.win).status,'clicked');assert.equal(f.s.clicks,2);assert.equal(medaiCartStep(quote,f.doc,f.win).status,'waiting');assert.equal(f.s.clicks,2);f.s.count=2;assert.equal(medaiCartStep(quote,f.doc,f.win).status,'ready');assert.equal(f.s.clicks,2);
f=fixture();f.s.count=3;assert.equal(medaiCartStep(quote,f.doc,f.win).status,'manual');assert.equal(f.s.clicks,0);
f=fixture();f.s.dialog={hidden:false,getClientRects:()=>[{}],innerText:'Login with OTP'};assert.equal(medaiCartStep(quote,f.doc,f.win).status,'login_required');assert.equal(f.s.clicks,0);
f=fixture();assert.equal(medaiCartStep({...quote,target_packs:101},f.doc,f.win).status,'manual');
console.log('Cart assistant checks passed: origin, identity, price, pack, quantity, pending-click deduplication, existing cart, login and bounds.');
// Server-rendered loading controls must never receive a cart click.
f=fixture();
let b=f.doc.getElementById('product-42-variant-43').querySelector('[data-pv-id="43"]').parentElement.querySelectorAll('button')[0];
b.textContent='Loading Add To Cart';
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'waiting');assert.equal(f.s.clicks,0);
b.textContent='Add To Cart';f.win.__next_f=[];
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'waiting');assert.equal(f.s.clicks,0);
b.__reactProps$test={onClick:()=>{}};
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'clicked');assert.equal(f.s.clicks,1);
f.win.__medaiPending.at=Date.now()-21000;
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'manual');assert.equal(f.s.clicks,1);
// A delayed acknowledgement is read before timeout, without duplicate adds.
f.s.count=2;
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'ready');assert.equal(f.s.clicks,1);
console.log('Hydration/loading/stalled-click regression checks passed.');

// Live Arogga uses a role-less sheet and a text input, not input[type=tel].
f=fixture();
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'clicked');
f.win.__medaiPending.at=Date.now()-21000;
f.s.dialog={hidden:true,innerText:'',getClientRects:()=>[]};
f.s.loginFields=[{hidden:false,getClientRects:()=>[{}],getAttribute:n=>n==='placeholder'?'Enter phone number':null}];
assert.equal(medaiLoginRequired(f.doc),true);
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'login_required');
assert.equal(f.s.clicks,1); // login must take precedence over stalled-click error
f.s.loginFields[0].hidden=true;
assert.equal(medaiLoginRequired(f.doc),false);
f.s.loginFields[0].hidden=false;
f.s.loginFields[0].getAttribute=n=>n==='autocomplete'?'one-time-code':null;
assert.equal(medaiLoginRequired(f.doc),true);
console.log('Role-less login sheet, OTP, hidden inputs and pending-click login checks passed.');

// Arogga's first click opens a menu; the second is the exact reviewed quantity.
function showPicker(f, options) {
  const picked = [];
  const rows = options.map(textContent => ({
    textContent, children: [], closest: () => null,
    click: () => picked.push(textContent),
  }));
  const panel = {tagName:'DIV', querySelectorAll: () => rows};
  f.s.picker = {textContent:'Select quantity', children:[], parentElement:panel};
  return picked;
}
f=fixture();
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'clicked');
const picked = showPicker(f,['10 Tablets (1 Strip)','20 Tablets (2 Strips)','30 Tablets (3 Strips)']);
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'clicked');
assert.deepEqual(picked,['20 Tablets (2 Strips)']);
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'waiting');
assert.equal(picked.length,1);
f.s.picker=null;
f.s.count=1;
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'waiting');
assert.equal(f.s.clicks,1); // Do not send + while the quantity selection is pending.
f.s.count=2;
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'ready');

for (const rows of [
  ['20 Tablets (3 Strips)','30 Tablets (2 Strips)'],
  ['20 Tablets (2 Strips)','20 Tablets (2 Strips)'],
]) {
  f=fixture();
  medaiCartStep(quote,f.doc,f.win);
  const rejected = showPicker(f,rows);
  assert.equal(medaiCartStep(quote,f.doc,f.win).status,'manual');
  assert.deepEqual(rejected,[]);
}
f=fixture();
const unrelated = showPicker(f,['20 Tablets (2 Strips)']);
assert.equal(medaiCartStep(quote,f.doc,f.win).status,'manual');
assert.deepEqual(unrelated,[]);
assert.equal(f.s.clicks,0);
console.log('Quantity picker checks passed: exact match, acknowledgement, no duplicate or ambiguous selections.');

// Screenshot regression: the selected strip button is the quantity control and
// the displayed amount is a line total, not the original one-strip price.
const napaQuote = {...quote, pack_price_minor:1080};
function selectedFixture(text='20 Tablets (2 Strips)', price='৳21.60') {
  const f=fixture();
  f.s.price=price;f.s.showCart=true;f.s.badge=1;
  const scope=f.doc.getElementById('product-42-variant-43').querySelector('[data-pv-id="43"]').parentElement;
  const b={textContent:text,disabled:false,hidden:false,getClientRects:()=>[{}],
    getAttribute:()=>null,click:()=>{f.s.clicks++;}};
  const old=scope.querySelectorAll;
  scope.querySelectorAll=selector=>selector==='button'?[b]:old(selector);
  f.selectedButton=b;
  return f;
}
f=selectedFixture();
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'ready');
assert.equal(f.s.clicks,0);
assert.equal(f.s.clicks,0);
// Do not use the desired total as a shortcut: quantity and price must both match.
f=selectedFixture('20 Tablets (2 Strips)','৳22.00');
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'manual');
f=selectedFixture('20 Tablets (2 Strips)','৳10.80');
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'manual');
f=selectedFixture('20 Tablets (3 Strips)','৳32.40');
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'manual');
f=selectedFixture('30 Tablets (3 Strips)','৳32.40');
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'manual');
// Updating an existing one-strip selection uses the same exact-quantity menu.
f=selectedFixture('10 Tablets (1 Strip)','৳10.80');
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'clicked');
const updated=showPicker(f,['10 Tablets (1 Strip)','20 Tablets (2 Strips)']);
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'clicked');
assert.deepEqual(updated,['20 Tablets (2 Strips)']);
f.s.picker=null;f.selectedButton.textContent='20 Tablets (2 Strips)';f.s.price='৳21.60';
assert.equal(medaiCartStep(napaQuote,f.doc,f.win).status,'ready');
assert.equal(f.s.clicks,1);
assert.equal(f.s.clicks,1);
console.log('Selected-strip totals passed: 10.80 x 2 = 21.60, changed prices, inconsistent units, excess quantities and no duplicate adds.');

// A stale selected label with an explicitly empty cart is reconciled using
// the supplier's exact-quantity picker, never the network-dependent drawer.
const resumeQuote={...napaQuote,previous_document:'run:0'};
f=selectedFixture(); f.s.badge=0;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'clicked');
assert.equal(f.s.clicks,1);
assert.equal(f.s.cartOpens,undefined);
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
const restored=showPicker(f,['10 Tablets (1 Strip)','20 Tablets (2 Strips)']);
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'clicked');
assert.deepEqual(restored,['20 Tablets (2 Strips)']);
f.s.picker=null;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
assert.equal(restored.length,1);
f.s.badge=1;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'ready');
assert.equal(f.s.clicks,1);
assert.equal(f.s.cartOpens,undefined);

// On resume, Android may still evaluate JS in the old document, even while
// its Add To Cart button is visible. Wait for the new document.
f=fixture();f.s.price='৳10.80';f.s.showCart=true;f.s.badge=0;
f.win.__medaiBeforeNavigation=resumeQuote.previous_document;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
assert.equal(f.s.clicks,0);
delete f.win.__medaiBeforeNavigation;
f.doc.readyState='loading';
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
f.doc.readyState='interactive';
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'clicked');
const resumed=showPicker(f,['10 Tablets (1 Strip)','20 Tablets (2 Strips)']);
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'clicked');
assert.deepEqual(resumed,['20 Tablets (2 Strips)']);
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
assert.equal(f.s.clicks,1);
assert.equal(resumed.length,1);

// React can render the quantity before the updated cart badge.
const ack=selectedFixture();ack.win.__medaiPending=f.win.__medaiPending;
ack.s.badge=0;
assert.equal(medaiCartStep(resumeQuote,ack.doc,ack.win).status,'waiting');
ack.s.badge=1; // one distinct cart entry, containing two strips
assert.equal(medaiCartStep(resumeQuote,ack.doc,ack.win).status,'ready');
assert.equal(ack.s.clicks,0);
assert.equal(ack.s.cartOpens,undefined);
assert.equal(medaiOpenSupplierCart(ack.doc,ack.win),'opened');
assert.equal(ack.s.cartOpens,1);
ack.s.cartAsset='/_next/image?url=%2Fassets%2Fsvg%2Ficon-v2%2Fcart.svg&w=64&q=75';
assert.equal(medaiOpenSupplierCart(ack.doc,ack.win),'opened');
assert.equal(ack.s.cartOpens,2);
ack.s.cartAsset='https://other.example/assets/svg/icon-v2/cart.svg';
assert.equal(medaiOpenSupplierCart(ack.doc,ack.win),'manual');
assert.equal(ack.s.cartOpens,2);
console.log('Resume regression passed: stale zero badge, navigation race, re-add, delayed acknowledgement, and explicit mobile cart open.');

// A missing badge is unknown, not an empty cart. No recovery click is allowed.
f=selectedFixture();f.s.showCart=false;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
assert.equal(f.s.clicks,0);
// Changed price/excess quantity must stop BEFORE attempting recovery.
f=selectedFixture('20 Tablets (2 Strips)','৳22.00');f.s.badge=0;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'manual');
assert.equal(f.s.clicks,0);
f=selectedFixture('30 Tablets (3 Strips)','৳32.40');f.s.badge=0;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'manual');
assert.equal(f.s.clicks,0);
// Give asynchronous quantity acknowledgement time, but never re-click on timeout.
f=selectedFixture();f.s.badge=0;
medaiCartStep(resumeQuote,f.doc,f.win);
const once=showPicker(f,['20 Tablets (2 Strips)']);
medaiCartStep(resumeQuote,f.doc,f.win);f.s.picker=null;
f.win.__medaiPending.at=Date.now()-12000;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
f.win.__medaiPending.at=Date.now()-21000;
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'manual');
assert.equal(once.length,1);assert.equal(f.s.clicks,1);
// Login still interrupts recovery; no automatic OTP/password entry.
f=selectedFixture();f.s.badge=0;
f.s.loginFields=[{getAttribute:n=>n==='placeholder'?'Enter phone number':null}];
assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'login_required');
assert.equal(f.s.clicks,0);
console.log('Recovery checks passed: stale selection -> exact picker -> positive badge; no drawer dependency, no duplicate retry, unknown badge/changed price/login stop.');

// Reuse the same page through repeated removals. Completion must clear pending
// state; every refill sets two strips once instead of incrementing by two.
f=selectedFixture();
let selections=0;
for(let cycle=0;cycle<3;cycle++) {
 f.s.badge=0;
 assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'clicked');
 const choice=showPicker(f,['10 Tablets (1 Strip)','20 Tablets (2 Strips)']);
 assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'clicked');
 selections+=choice.length;f.s.picker=null;
 for(let poll=0;poll<4;poll++) assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'waiting');
 f.s.badge=1;
 assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'ready');
 assert.equal(medaiCartStep(resumeQuote,f.doc,f.win).status,'ready');
 assert.equal(f.win.__medaiPending,null);
 assert.equal(f.s.clicks,cycle+1);
 assert.equal(selections,cycle+1);
 assert.equal(f.s.cartOpens,undefined);
}
console.log('Three consecutive fill/remove/refill cycles passed without duplicate selections or cart drawer calls.');
