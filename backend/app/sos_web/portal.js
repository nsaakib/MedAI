'use strict';
const get = id => document.getElementById(id);
let token = '', permissions = [], last = '', running = false, generation = 0, gpsWatch = null;
const labels = {queued:'Waiting for operator',awaiting_driver:'Reserved · waiting for driver',dispatched:'Driver accepted',en_route:'On the way',arrived:'At patient location',cancel_requested:'Cancellation pending',no_coverage:'No confirmed ambulance',out_of_service:'Out of service',on_the_way:'On the way',at_patient_location:'At patient location',manual:'Call driver manually',submitted_to_gateway:'Submitted to SMS gateway (not delivery confirmation)'};
const label = s => labels[s] || String(s).replaceAll('_',' ');
const status = (text,error=false) => { get('notice').textContent=text; get('notice').classList.toggle('error',error); };
function el(tag,text='',cls='') { const n=document.createElement(tag); n.textContent=text; if(cls)n.className=cls; return n; }
function action(text,fn,cls='') {
  const b=el('button',text,cls);
  b.type='button';
  b.onclick=async()=>{ if(b.disabled)return; b.disabled=true;
    try{await fn(); last=''; await refresh();}catch(e){status(e.message,true);}finally{b.disabled=false;}
  }; return b;
}
function line(block,title,value){block.append(el('p',title+': '+(value??'Not recorded')));}
function link(title,url){const a=el('a',title);a.href=url;a.target='_blank';a.rel='noopener noreferrer';return a;}
function phoneLink(phone){const a=el('a',String(phone||''));if(/^[+0-9 -]{5,35}$/.test(phone||''))a.href='tel:'+phone.replace(/[^+0-9]/g,'');return a;}
function mapLink(p){return link('Open directions in Google Maps','https://www.google.com/maps/dir/?api=1&destination='+encodeURIComponent(p.lat+','+p.lng));}
async function api(path,method='GET',body) {
  const response=await fetch('/api'+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},
    body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',signal:AbortSignal.timeout(7000)});
  if(response.status===204)return null;
  const data=await response.json().catch(()=>null);
  if(!response.ok)throw new Error(typeof data?.detail==='string'?data.detail:Array.isArray(data?.detail)?data.detail.map(d=>String(d.loc?.at(-1)||'field')+': '+d.msg).join('; '):'Request not confirmed ('+response.status+').');
  return data;
}
function stopGPS(){if(gpsTimer!==null)clearInterval(gpsTimer);gpsTimer=null;gpsWatch=null;gpsMessage='Location sharing is off.';}
function reset(){generation++;stopGPS();token=''; permissions=[];last='';get('active').replaceChildren();get('workspace').hidden=true;get('login').hidden=false;get('signup').hidden=true;get('signup').reset();get('driver-created').hidden=true;get('driver-credentials').textContent='';status('Signed out.');}
get('login').onsubmit=async e=>{
  e.preventDefault();const f=new FormData(e.currentTarget); const button=e.currentTarget.querySelector('button');
  button.disabled=true;
  try{
    const session=await api('/auth/login','POST',{email:f.get('email'),password:f.get('password')});
    token=session.token;
    await showRole();
  }catch(e){reset();status(e.message,true);}
  finally{get('login').reset();button.disabled=false;}
};
get('logout').onclick=async()=>{try{await api('/auth/logout','POST');}catch(_){}reset();};
get('role').onchange=()=>{generation++;last='';stopGPS();get('active').replaceChildren();refresh();};
get('refresh').onclick=()=>{last='';refresh();};
function plot(node,patient,vehicles) {
  if(!patient)return;
  const ns='http://www.w3.org/2000/svg', svg=document.createElementNS(ns,'svg');
  svg.setAttribute('role','img');svg.setAttribute('aria-label','Relative location plot: patient and vehicles with recent GPS');
  let view=[0,0,100,64];
  const draw=()=>svg.setAttribute('viewBox',view.join(' '));
  draw();
  function tag(name,attrs,text) {
    const x=document.createElementNS(ns,name);Object.entries(attrs).forEach(([k,v])=>x.setAttribute(k,v));
    if(text)x.textContent=text;svg.append(x);
  }
  for(let x=0;x<=100;x+=10)tag('line',{x1:x,y1:0,x2:x,y2:64,class:'gridline'});
  for(let y=0;y<=64;y+=8)tag('line',{x1:0,y1:y,x2:100,y2:y,class:'gridline'});
  const points=[{name:'Patient',point:patient,cls:'patient'},...vehicles.filter(v=>v.location).map(v=>({name:v.id,point:v.location,cls:'vehicle'}))];
  const scale=Math.max(.003,...points.map(p=>Math.max(Math.abs(patient.lng-p.point.lng),Math.abs(patient.lat-p.point.lat)*1.5)));
  for(const p of points) {
    const x=49+(p.point.lng-patient.lng)*38/scale, y=32-(p.point.lat-patient.lat)*38/scale;
    tag('circle',{cx:x,cy:y,r:1.7,class:p.cls});
    tag('text',{x:x+2,y:y-1,class:'marker-label'},p.name);
  }
  svg.addEventListener('wheel',e=>{e.preventDefault();const f=e.deltaY<0?.85:1.15;
    const w=Math.max(12,Math.min(180,view[2]*f)); const h=w*.64;
    view=[view[0]+(view[2]-w)/2,view[1]+(view[3]-h)/2,w,h];draw();
  },{passive:false});
  let cursor;
  svg.addEventListener('pointerdown',e=>{cursor=[e.clientX,e.clientY];svg.setPointerCapture(e.pointerId);});
  svg.addEventListener('pointerup',()=>cursor=null);
  svg.addEventListener('pointermove',e=>{if(!cursor)return;view[0]-=(e.clientX-cursor[0])*view[2]/svg.clientWidth;view[1]-=(e.clientY-cursor[1])*view[3]/svg.clientHeight;cursor=[e.clientX,e.clientY];draw();});
  const controls=el('div','','row'); controls.append(action('Reset map',async()=>{view=[0,0,100,64];draw();},'ghost'),mapLink(patient));
  // Reset is a local view action; it must not refresh the dispatch board.
  controls.firstChild.onclick=()=>{view=[0,0,100,64];draw();};
  node.append(svg,el('p','Relative GPS map · drag or scroll to explore. No road ETA.','map-caption'),controls);
}
let gpsTimer=null, gpsBusy=false, gpsMessage='';
function publishDriverFix(base,id) {
  const trip=latestJobs.find(j=>['dispatched','en_route','arrived'].includes(j.status))?.assignment;
  if (!token || generation!==id || gpsBusy || gpsWatch===null || !trip) return;
  const currentToken=token;
  gpsBusy=true;
  navigator.geolocation.getCurrentPosition(async p=>{
    try {
      if (!token || token!==currentToken || generation!==id || gpsWatch===null ||
          !latestJobs.some(j=>j.assignment?.id===trip.id && ['dispatched','en_route','arrived'].includes(j.status))) return;
      await api(base+'/jobs/'+trip.id+'/location','POST',
        {lat:p.coords.latitude,lng:p.coords.longitude,accuracy:Math.min(20000,p.coords.accuracy)});
      gpsMessage='Location shared at '+new Date().toLocaleTimeString()+'.';
    } catch(_) { gpsMessage='Location update was not confirmed. Check the connection.'; }
    finally { gpsBusy=false; if(id===generation) updateGpsMessage(); }
  }, error=>{
    gpsBusy=false;
    gpsMessage=error.code===1?'Location permission denied. Enable it in the browser to share your location.':'Could not get a fresh GPS fix.';
    if(id===generation) updateGpsMessage();
  },{enableHighAccuracy:true,maximumAge:0,timeout:7500});
}

function updateGpsMessage(){
  const line=get('gps-status');
  if(line)line.textContent=gpsMessage;
}

function driverPanels(container,base,jobs) {
  const driverCard=el('section','','card driver-location');
  driverCard.append(el('h2','Location sharing'));
  const toggle=action(gpsWatch===null?'Share trip location':'Stop sharing',async()=>{
    if(gpsWatch!==null){stopGPS();return;}
    if(!window.isSecureContext||!navigator.geolocation)throw new Error('Open Partner Operations over HTTPS on the driver’s phone.');
    const id=generation;
    gpsMessage='Waiting for the first GPS fix.';
    gpsWatch=id;
    gpsTimer=setInterval(()=>publishDriverFix(base,id),8000);
    publishDriverFix(base,id);
  });
  const explanation=el('p','Keep this page open and allow location access. Location is shared only during an accepted trip.','muted');
  const locationStatus=el('p',gpsMessage,'muted');
  locationStatus.id='gps-status';
  driverCard.append(explanation,toggle,locationStatus);
  container.append(driverCard);
  if(!jobs.length)container.append(el('p','No active assignments.'));
  for(const j of jobs){
    const panel=el('article','','card');panel.append(el('h2','Request '+j.id),el('p',label(j.status),'badge'));
    line(panel,'Ambulance',j.assignment?.ambulance_id);
    if(j.patient){
      const contact=el('p','Patient contact: ');contact.append(phoneLink(j.patient.phone));panel.append(contact);
      line(panel,'Address',j.patient.address||'Use coordinates');line(panel,'Incident note',j.patient.note||'Not supplied');
      panel.append(mapLink(j.patient));
    }
    const send=(a,reason='')=>api(base+'/jobs/'+j.assignment.id,'POST',{action:a,reason});
    if(j.status==='awaiting_driver') {
      panel.append(action('Accept assignment',()=>send('accept')));
      const reason=el('input');reason.placeholder='Rejection reason';reason.maxLength=200;panel.append(reason);
      panel.append(action('Reject and return to operator',async()=>{if(!reason.value.trim())throw new Error('Enter a reason.');await send('reject',reason.value.trim());},'ghost'));
    }
    if(j.status==='dispatched')panel.append(action('On the way',()=>send('en_route')));
    if(j.status==='en_route')panel.append(action('At patient location',()=>send('arrived')));
    if(j.status==='arrived')panel.append(action('Complete trip',()=>send('complete')));
    if(j.status==='cancel_requested')panel.append(el('p','Contact the operator to confirm cancellation before taking any other assignment.'));
    container.append(panel);
  }
}
function operatorPanels(container,base,board){
  const active=board.requests.filter(r=>['queued','awaiting_driver','dispatched','en_route','arrived','cancel_requested'].includes(r.status));
  container.append(el('h2','Emergency queue · '+active.length+' active'));
  if(!board.requests.length)container.append(el('p','No requests received.'));
  for(const r of board.requests){
    const panel=el('article','','card'+(r.status==='queued'?' primary':''));
    panel.append(el('h3','Request '+r.id),el('p',label(r.status),'badge'));
    if(r.patient){
      const contact=el('p','Patient contact: ');contact.append(phoneLink(r.patient.phone));panel.append(contact);
      line(panel,'Address',r.patient.address||'Use coordinates');
      line(panel,'Location',r.patient.lat+', '+r.patient.lng);
      line(panel,'Incident note',r.patient.note||'Not supplied');
      line(panel,'Requested equipment',r.patient.equipment.join(', ')||'Not specified');
      line(panel,'Requested category',r.patient.category||'Not specified');
      if(r.patient.last_driver_reason)line(panel,'Driver rejection',r.patient.last_driver_reason);
      if(['queued','awaiting_driver','dispatched','en_route','arrived','cancel_requested'].includes(r.status))
        plot(panel,r.patient,r.assignment?[{id:r.assignment.ambulance_id,location:r.assignment.location}]:r.recommended||[]);
    }
    if(r.history?.some(h=>h.action==='driver_timeout')&&r.status==='queued'){
      panel.append(el('p','Previous driver did not respond. Confirm another available vehicle.','badge'));
    }
    if(r.assignment){
      line(panel,'Ambulance',r.assignment.ambulance_id);
      if(r.assignment.sms)line(panel,'SMS',label(r.assignment.sms.state));
      const number=r.assignment.driver?.phone;
      if(number){const p=el('p','Operator phone fallback: ');p.append(phoneLink(number));panel.append(p);}
    }
    if(board.enabled&&r.status==='queued'){
      const choices=r.recommended||[];
      if(choices.length)panel.append(el('h4','Suggested vehicles (match, GPS freshness, distance)'));
      for(const v of choices) {
        const desc=v.id+' · '+v.category+' · '+(v.distance_km===null?'No fresh GPS':v.distance_km+' km straight-line');
        const row=el('div','','row');row.append(el('span',desc),action('Reserve '+v.id,async()=>{
          if(confirm('Reserve this ambulance and request driver acceptance?'))await api(base+'/requests/'+r.id+'/assign','POST',{vehicle_id:v.id});
        }));panel.append(row);
      }
      const select=el('select');select.setAttribute('aria-label','Choose any suitable available ambulance');
      for(const v of board.fleet.filter(v=>v.status==='available'&&r.patient.equipment.every(e=>v.equipment.includes(e))&&(!r.patient.category||r.patient.category===v.category))){
        const o=el('option',v.id+' · '+v.category);o.value=v.id;select.append(o);
      }
      if(select.options.length){
        const row=el('div','','row');row.append(select,action('Reserve selected vehicle',async()=>{
          if(confirm('Reserve '+select.value+' and request driver acceptance?'))await api(base+'/requests/'+r.id+'/assign','POST',{vehicle_id:select.value});
        },'ghost'));panel.append(row);
      }else panel.append(el('p','No suitable ambulance is currently marked available. Do not confirm dispatch.'));
      panel.append(action('Decline this request',async()=>{
        if(confirm('Decline this center’s request? Med.ai will look for another matching partner if the patient allowed it.'))await api(base+'/requests/'+r.id+'/decline','POST',{});
      },'ghost'));
    }
    if(r.status==='cancel_requested')panel.append(action('Confirm cancellation after contacting driver',async()=>{
      if(confirm('Confirm the driver has been informed? This takes the vehicle offline.'))await api(base+'/requests/'+r.id+'/confirm-cancel','POST',{});
    }));
    container.append(panel);
  }
  container.append(el('h2','Ambulance fleet','section-title'));
  const grid=el('div','','grid');
  for(const v of board.fleet){
    const panel=el('article','','card');panel.append(el('h3',v.id),el('p',label(v.status),'badge'));
    line(panel,'Registration',v.registration);line(panel,'Driver',v.driver.name);
    panel.append(phoneLink(v.driver.phone));
    line(panel,'Category',v.category);line(panel,'Equipment',v.equipment.join(', ')||'Not specified');
    line(panel,'GPS',v.location?v.location.lat+', '+v.location.lng:'No recent fix');
    const states=['available','offline','out_of_service','busy'];
    if(sandbox && board.enabled && states.includes(v.status) && v.id.startsWith('TEST-')){
      const next=v.category==='advanced'?'basic':'advanced';
      panel.append(action('Configure sandbox vehicle: '+next,async()=>{
        const org=permissions[Number(get('role').value)].org_id;
        await api('/sos/partner/'+encodeURIComponent(org)+'/test-fleet','POST',{vehicle_id:v.id,category:next});
      },'ghost'));
    }
    if(board.enabled&&states.includes(v.status)){
      const s=el('select');s.setAttribute('aria-label','Availability for '+v.id);
      for(const a of states){const o=el('option',label(a));o.value=a;o.selected=a===v.status;s.append(o);}
      panel.append(s,action('Update availability',()=>api(base+'/fleet/'+v.id,'POST',{status:s.value})));
    }
    grid.append(panel);
  }
  container.append(grid);
}
let latestJobs=[];
async function refresh(){
  if(!token||running)return; const p=permissions[Number(get('role').value)];if(!p)return;
  const id=generation;running=true;
  try{
    const base='/sos/'+p.role+'/'+encodeURIComponent(p.org_id);
    const payload=await api(base+(p.role==='operator'?'/board':'/jobs'),p.role==='operator'?'POST':'GET');
    if(id!==generation||!token)return;
    status(p.role==='operator'&&!payload.enabled?'Live intake disabled. Do not tell patients a vehicle was dispatched.':(sandbox?'SANDBOX · ':'')+'Connected · updated '+new Date().toLocaleTimeString());
    const serialized=JSON.stringify(payload)+String(gpsWatch!==null);
    if(serialized===last)return;last=serialized;
    const block=get('active');block.replaceChildren();
    if(p.role==='operator')operatorPanels(block,base,payload);
    else {
      const oldTrip=latestJobs.find(j=>['dispatched','en_route','arrived'].includes(j.status))?.assignment?.id;
      latestJobs=payload;
      const trip=payload.find(j=>['dispatched','en_route','arrived'].includes(j.status))?.assignment?.id;
      if (trip && trip!==oldTrip && gpsWatch!==null) publishDriverFix(base,id);
      driverPanels(block,base,payload);
    }
  }catch(e){if(id===generation)status('Updates unavailable. Displayed information may be stale. '+e.message,true);}
  finally{running=false;}
}
setInterval(refresh,4000);

let sandbox = false;
async function showRole() {
  permissions=await api('/sos/roles');
  if(!permissions.length){
    const history=await api('/sos/partner/enrollment');
    if(history.length){
      const item=history[0];
      await api('/auth/logout','POST'); reset();
      status('Your registration is pending verification. Organization ID: '+item.organization_id);
    }else{
      showSignup(true);
      status('Signed in. Register your organization to request partner access.');
    }
    return;
  }
  get('role').replaceChildren(...permissions.map((p,i)=>{
    const o=el('option',p.org_id+' · '+p.role);o.value=String(i);return o;
  }));
  get('login').hidden=true;
  get('signup').hidden=true;
  get('workspace').hidden=false;
  status(sandbox?'SANDBOX · No live dispatch or SMS.':'Signed in.');
  await refresh();
}

function showSignup(existing=false) {
  get('login').hidden=true;
  const form=get('signup');
  form.hidden=false;
  for(const label of form.querySelectorAll('.new-account')){
    label.hidden=existing;
    label.querySelector('input').disabled=existing;
  }
  if(sandbox){
    form.elements.phone.value='01700000000';
    form.elements.lat.value='23.7806';
    form.elements.lng.value='90.4070';
  }
}

get('open-signup').onclick=()=>showSignup();
get('back-login').onclick=async()=>{
  try{if(token)await api('/auth/logout','POST');}catch(_){}
  reset();
};
get('signup').onsubmit=async e=>{
  e.preventDefault();
  const form=e.currentTarget, f=new FormData(form), button=form.querySelector('button');
  button.disabled=true;
  try{
    if(!token){
      const session=await api('/auth/register','POST',{email:f.get('email'),password:f.get('password'),name:f.get('name')});
      token=session.token;
    }
    const result=await api('/sos/partner/enrollment','POST',{
      ...Object.fromEntries(['name','organization','address','phone'].map(k=>[k,f.get(k)])),
      lat:Number(f.get('lat')),lng:Number(f.get('lng'))
    });
    form.reset();
    if(result.driver_email){
      get('driver-created').hidden=false;
      get('driver-credentials').textContent=result.driver_email+'\n'+result.driver_password;
    }
    await showRole();
  }catch(e){status(e.message+' If this email already exists, use Sign in first.',true);}
  finally{button.disabled=false;}
};
api('/sos/config').then(config=>{
  sandbox=config.mode==='sandbox';
  if(sandbox){
    get('live-call').hidden=true;
    get('signup-help').textContent='LOCAL SANDBOX: use fictional details and an example.test email. No real ambulances or SMS.';
    if(!token)status('SANDBOX · Log in or register a test partner. No live dispatch or SMS.');
  }
}).catch(e=>status('Could not load dispatch settings. '+e.message,true));
