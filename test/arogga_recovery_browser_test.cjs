// Optional rendered-DOM regression: npm install --no-save playwright
// Set CHROMIUM_PATH to an installed Chromium/Chrome executable, or install
// Playwright Chromium with npx playwright install chromium.
const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{})});
 try {
 const page=await browser.newPage({viewport:{width:390,height:700}});
 // This is a local supplier-layout fixture, NOT a live retailer transaction.
 await page.route('**/*',route=>route.fulfill({contentType:'text/html',body:`
 <button id="cart"><img src="/assets/svg/icon-v2/cart.svg"><span id="badge">0</span></button>
 <div style="height:700px">Product image</div>
 <main id="product-42-variant-43"><h1>Test Brand</h1><section>
 <div data-pv-id="43"><div class="product_single_label_generate">10 Tablets (1 Strip)</div>
 <div class="product_single_price_generate">৳21.60</div></div>
 <button id="quantity">20 Tablets (2 Strips)</button></section></main>
 <script>
 window.optionClicks=0;window.menuClicks=0;window.cartClicks=0;window.saved=0;
 document.querySelector('#cart').onclick=()=>{window.cartClicks++};
 document.querySelector('#quantity').onclick=()=>{
  window.menuClicks++;
  if(document.querySelector('#picker'))throw Error('Duplicate menu click');
  const panel=document.createElement('div');panel.id='picker';
  panel.innerHTML='<h3>Select quantity</h3><ul><li><button type="button"><span>10 Tablets (1 Strip)</span></button></li><li><button type="button"><span>20 Tablets (2 Strips)</span></button></li></ul>';
  document.body.append(panel);
  panel.querySelectorAll('button').forEach((b,i)=>b.onclick=()=>{
   window.optionClicks++; window.saved=i+1;panel.remove();
   // Delay badge acknowledgement: a stale label alone is insufficient.
  });
 };
 </script>`}));
 await page.goto('https://www.arogga.com/product/42/test');
 await page.addScriptTag({content:fs.readFileSync(path.join(__dirname,'../assets/arogga_assistant.js'),'utf8')});
 const quote={product_id:'42',variant_id:'43',product_name:'Test Brand',pack_label:'10 Tablets (1 Strip)',pack_price_minor:1080,target_packs:2,units_per_pack:10,previous_document:'run:0'};
 const step=()=>page.evaluate(q=>medaiCartStep(q),quote);
 for(let cycle=0;cycle<3;cycle++){
  await page.evaluate(()=>{window.saved=0;document.querySelector('#badge').textContent='0'});
  const scroll=await page.evaluate(()=>window.scrollY);
  assert.equal((await step()).status,'clicked');
  assert.equal((await step()).status,'clicked');
  assert.equal((await step()).status,'waiting');
  assert.equal((await step()).status,'waiting');
  assert.equal(await page.evaluate(()=>window.saved),2);
  await page.evaluate(()=>document.querySelector('#badge').textContent='1');
  assert.equal((await step()).status,'ready');
  assert.equal((await step()).status,'ready');
  assert.deepEqual(await page.evaluate(()=>[window.menuClicks,window.optionClicks,window.cartClicks]),[cycle+1,cycle+1,0]);
  assert.equal(await page.evaluate(()=>window.scrollY),scroll);
 }
 console.log('Rendered DOM passed: 3 fill/remove/refill cycles; exact two-strip choice; delayed badge; no repeated selection, drawer click or scroll jump.');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
