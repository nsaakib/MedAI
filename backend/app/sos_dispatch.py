"""Partner-operated SOS. Safe default: no live requests unless explicitly enabled."""
import math
import os
import re
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from fastapi import Depends, HTTPException, Response
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from .map_policy import map_config
from .core import now, uid

SCHEMA = """
CREATE TABLE IF NOT EXISTS sos_orgs(
 id TEXT PRIMARY KEY, verified INTEGER NOT NULL DEFAULT 0, payload BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS sos_members(
 user_id TEXT NOT NULL REFERENCES users(id), org_id TEXT NOT NULL REFERENCES sos_orgs(id),
 role TEXT NOT NULL CHECK(role IN ('operator','driver')), verified INTEGER NOT NULL DEFAULT 0,
 last_seen INTEGER NOT NULL DEFAULT 0, payload BLOB NOT NULL,
 PRIMARY KEY(user_id,org_id,role));
CREATE TABLE IF NOT EXISTS sos_vehicles(
 id TEXT PRIMARY KEY, org_id TEXT NOT NULL REFERENCES sos_orgs(id),
 driver_id TEXT NOT NULL REFERENCES users(id), status TEXT NOT NULL, registration_hash TEXT NOT NULL UNIQUE, payload BLOB NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS sos_vehicle_driver ON sos_vehicles(driver_id);
CREATE TABLE IF NOT EXISTS sos_requests(
 id TEXT PRIMARY KEY, patient_id TEXT NOT NULL REFERENCES users(id), request_key TEXT NOT NULL,
 org_id TEXT REFERENCES sos_orgs(id), status TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL,
 deadline INTEGER NOT NULL, payload BLOB NOT NULL, UNIQUE(patient_id,request_key));
CREATE UNIQUE INDEX IF NOT EXISTS sos_one_patient ON sos_requests(patient_id)
 WHERE status IN ('queued','awaiting_driver','dispatched','en_route','arrived','cancel_requested');
CREATE INDEX IF NOT EXISTS sos_org_queue ON sos_requests(org_id,status,created);
CREATE TABLE IF NOT EXISTS sos_routing_reason(
 request_id TEXT PRIMARY KEY REFERENCES sos_requests(id), reason TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sos_skipped_partners(
 request_id TEXT NOT NULL REFERENCES sos_requests(id), org_id TEXT NOT NULL REFERENCES sos_orgs(id),
 PRIMARY KEY(request_id,org_id));
CREATE TABLE IF NOT EXISTS sos_assignments(
 id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES sos_requests(id),
 vehicle_id TEXT NOT NULL REFERENCES sos_vehicles(id), driver_id TEXT NOT NULL REFERENCES users(id),
 active INTEGER NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS sos_one_vehicle ON sos_assignments(vehicle_id) WHERE active=1;
CREATE UNIQUE INDEX IF NOT EXISTS sos_one_assignment ON sos_assignments(request_id) WHERE active=1;
CREATE INDEX IF NOT EXISTS sos_driver_queue ON sos_assignments(driver_id,active);
CREATE TABLE IF NOT EXISTS sos_gps(
 vehicle_id TEXT PRIMARY KEY REFERENCES sos_vehicles(id), recorded INTEGER NOT NULL, payload BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS sos_events(
 id INTEGER PRIMARY KEY, target TEXT NOT NULL, actor TEXT NOT NULL, action TEXT NOT NULL, created INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS sos_event_target ON sos_events(target,id);
CREATE TABLE IF NOT EXISTS sos_outbox(
 id TEXT PRIMARY KEY REFERENCES sos_assignments(id), state TEXT NOT NULL,
 tries INTEGER NOT NULL, ready INTEGER NOT NULL, lease TEXT, payload BLOB NOT NULL);
"""
ACTIVE = "('queued','awaiting_driver','dispatched','en_route','arrived','cancel_requested')"
WEB = Path(__file__).with_name('sos_web')
EQUIPMENT = {'oxygen', 'stretcher', 'monitor', 'ventilator', 'neonatal'}
FLEET = {'available','offline','out_of_service','busy'}
PHONE = re.compile(r'^(?:\+?88)?01[3-9][0-9]{8}$')


class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)


class Point(Strict):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy: float | None = Field(default=None, ge=0, le=20000)


class ServiceSearch(Point):
    equipment: list[Literal['oxygen','stretcher','monitor','ventilator','neonatal']] = Field(default_factory=list,max_length=5)
    category: Literal['basic','advanced','neonatal'] | None = None


class Intake(ServiceSearch):
    request_key: str = Field(min_length=16, max_length=80, pattern=r'^[a-zA-Z0-9_-]+$')
    phone: str = Field(max_length=20)
    address: str = Field(default='', max_length=220)
    note: str = Field(default='', max_length=350)
    consent: Literal[True]
    allow_reroute: bool = False


class Assign(Strict):
    vehicle_id: str = Field(min_length=1,max_length=80)


class Action(Strict):
    action: Literal['accept','reject','en_route','arrived','complete']
    reason: str = Field(default='', max_length=200)


class Availability(Strict):
    status: Literal['available','offline','out_of_service','busy']


def init(store):
    with store.db() as db:
        db.executescript(SCHEMA)


def config_int(name, default, lower, upper):
    try:
        return max(lower,min(upper,int(os.environ.get(name, str(default)))))
    except ValueError:
        return default


def driver_wait():
    return config_int('MEDAI_SOS_DRIVER_TIMEOUT',90,30,600)


def secure_origin():
    try:
        base = urlsplit(os.getenv('MEDAI_SOS_PUBLIC_BASE_URL',''))
        return (base.scheme == 'https' and bool(base.hostname)
                and not (base.username or base.password or base.query or base.fragment)
                and base.path in ('','/'))
    except ValueError:
        return False


def enabled():
    return os.getenv('MEDAI_SOS_ENABLED') == '1' and secure_origin()


def event(db, actor, target, action):
    db.execute('INSERT INTO sos_events(target,actor,action,created) VALUES(?,?,?,?)',
               (target,actor,action,now()))


def distance(a,b):
    phi, psi = map(math.radians,(a['lat'],b['lat']))
    x = math.sin((psi-phi)/2)**2 + math.cos(phi)*math.cos(psi)*math.sin(math.radians(b['lng']-a['lng'])/2)**2
    return round(6371*2*math.asin(math.sqrt(min(x,1))),2)


def expire(db, store, allow_new_partner=False):
    t=now()
    for r in db.execute("SELECT * FROM sos_requests WHERE status IN ('queued','awaiting_driver') AND deadline <= ?",(t,)).fetchall():
        key=r['id']
        if r['status']=='queued':
            if reroute(db, store, r, 'operator_timeout', exclude_partner=True, allow_new_partner=allow_new_partner):
                continue
            db.execute("UPDATE sos_requests SET status='no_coverage',updated=? WHERE id=?",(t,key))
            event(db,'system',key,'operator_timeout')
            continue
        release(db,key,'timed_out','offline')
        if reroute(db, store, r, 'driver_timeout', allow_new_partner=allow_new_partner):
            continue
        db.execute("UPDATE sos_requests SET status='queued',deadline=?,updated=? WHERE id=?",(t+120,t,key))
        event(db,'system',key,'driver_timeout')


def release(db, request_id, status, fleet='available'):
    row=db.execute('SELECT * FROM sos_assignments WHERE request_id=? AND active=1',(request_id,)).fetchone()
    if row:
        db.execute('UPDATE sos_assignments SET active=0,status=?,updated=? WHERE id=?',(status,now(),row['id']))
        db.execute('UPDATE sos_vehicles SET status=? WHERE id=?',(fleet,row['vehicle_id']))
        db.execute("UPDATE sos_outbox SET state='cancelled' WHERE id=? AND state IN ('queued','leased')",(row['id'],))


def org_info(store, row):
    obj=store.decrypt(row['payload'])
    return {'id':row['id'], **{k:obj.get(k) for k in ('name','address','phone','lat','lng')}}


def fleet_rows(db, store, org_id, patient=None):
    rows=db.execute("""
        SELECT v.*,m.payload AS driver_payload,g.recorded,g.payload AS gps
        FROM sos_vehicles v JOIN sos_members m ON m.org_id=v.org_id AND m.user_id=v.driver_id AND m.role='driver'
        LEFT JOIN sos_gps g ON g.vehicle_id=v.id
        WHERE v.org_id=? AND m.verified=1
      """,(org_id,)).fetchall()
    result=[]
    for row in rows:
        obj=store.decrypt(row['payload'])
        fresh=row['recorded'] is not None and now()-row['recorded']<=120
        gps=store.decrypt(row['gps']) if fresh else None
        distance_km=distance(patient,gps) if patient and gps else None
        result.append({'id':row['id'],'status':row['status'],'driver_id':row['driver_id'],
                       'driver':store.decrypt(row['driver_payload']), **obj,
                       'location':gps, 'location_recorded':row['recorded'], 'distance_km':distance_km,
                       'eta_min':None})
    return result


def suitable(vehicle, equipment, category=None):
    return set(equipment) <= set(vehicle.get('equipment',[])) and (
        category is None or vehicle.get('category') == category
    )


def ranked(fleet, equipment, category=None):
    want=set(equipment)
    pool=[v for v in fleet if v['status']=='available' and suitable(v, want, category)]
    # Equipment is a hard requirement. A located, suitable vehicle precedes one
    # without a fresh fix. Distance is not advertised as road time.
    return sorted(pool,key=lambda v:(v['distance_km'] is None,v['distance_km'] or 0,
                                      len(set(v.get('equipment',[]))-want),v['id']))


def nearby(db, store, point, equipment, category=None):
    orgs=db.execute("""
        SELECT o.* FROM sos_orgs o WHERE o.verified=1 AND EXISTS (
          SELECT 1 FROM sos_members m WHERE m.org_id=o.id AND m.role='operator'
          AND m.verified=1 AND m.last_seen>?)
        """,(now()-90,)).fetchall()
    result=[]
    radius=config_int('MEDAI_SOS_RADIUS_KM',25,1,150)
    for org in orgs:
        o=org_info(store,org)
        km=distance(point,o)
        if km>radius: continue
        fleet = fleet_rows(db,store,org['id'],point)
        pool = ranked(fleet,equipment,category)
        # Account for queued requests against the vehicles they can use. This
        # is an estimate; reservation itself is always atomic.
        queued = db.execute("SELECT payload FROM sos_requests WHERE org_id=? AND status='queued' AND deadline>? ORDER BY created,rowid",
                            (org['id'],now())).fetchall()
        backlog = [store.decrypt(item['payload']) for item in queued]
        remaining = spare_vehicles(fleet,backlog,pool)
        result.append({**o,'distance_km':km,'reported_available':len(pool),
                       'dispatch_slots':len(remaining),'queued_count':len(queued),
                       'fresh_dispatch_distance_km':remaining[0]['distance_km'] if remaining else None,
                       'compatible_fleet':sum(suitable(v,equipment,category) for v in fleet),
                       'fresh_vehicle_distance_km':pool[0]['distance_km'] if pool else None,
                       'eta_min':None})
    return sorted(result,key=lambda r: (
        not r['reported_available'],r['fresh_vehicle_distance_km'] is None,
        r['fresh_vehicle_distance_km'] if r['fresh_vehicle_distance_km'] is not None else r['distance_km'],
        r['distance_km'],r['id']))


# SOS matching v2: keep one currently authorized partner per request.
def spare_vehicles(fleet, backlog, suitable_pool):
    """Find vehicles that can serve this request without displacing older work."""
    # Each queue entry can claim one vehicle. An augmenting path can move a
    # flexible request to a Basic vehicle to keep a scarce Advanced one free.
    options = [[v['id'] for v in ranked(fleet,n['equipment'],n.get('category'))] for n in backlog]
    claims = {}

    def fit(root, owners, forbidden=None):
        queue = [root]
        seen_requests = {root}
        incoming, via = {}, {}
        for idx in queue:
            for vid in options[idx]:
                if vid == forbidden or vid in incoming:
                    continue
                incoming[vid] = idx
                if vid not in owners:
                    while True:
                        req = incoming[vid]
                        owners[vid] = req
                        if req == root:
                            return True
                        vid = via[req]
                req = owners[vid]
                if req not in seen_requests:
                    seen_requests.add(req)
                    via[req] = vid
                    queue.append(req)
        return False

    for idx in range(len(options)):
        fit(idx,claims)
    result = []
    for v in suitable_pool:
        vid = v['id']
        if vid not in claims:
            result.append(v)
            continue
        proposed = claims.copy()
        owner = proposed.pop(vid)
        if fit(owner,proposed,forbidden=vid):
            result.append(v)
    return result


def coverage(db, store, payload, *, exclude=(), capacity=True):
    partners = nearby(db, store, payload, payload['equipment'], payload.get('category'))
    candidates = [p for p in partners if p['id'] not in exclude]
    usable = [p for p in candidates if p['dispatch_slots' if capacity else 'reported_available']]
    if usable:
        # Preserve proximity, but treat partners within a 5 km band as similar.
        # Prefer spare matching capacity / lower queue pressure within that band.
        def key(p):
            km = p['fresh_dispatch_distance_km' if capacity else 'fresh_vehicle_distance_km']
            km = p['distance_km'] if km is None else km
            return (int(km / 5), p['queued_count'] / p['reported_available'],
                    -p['dispatch_slots'], km, p['id'])
        return min(usable, key=key)['id'], None
    if not candidates:
        return None, 'partners_exhausted' if exclude else 'no_staffed_partner'
    if not any(p['compatible_fleet'] for p in candidates):
        return None, 'equipment_or_category_unavailable'
    return None, 'matching_vehicles_busy'


def set_routing_reason(db, request_id, reason):
    if reason:
        db.execute('INSERT OR REPLACE INTO sos_routing_reason VALUES(?,?)', (request_id,reason))
    else:
        db.execute('DELETE FROM sos_routing_reason WHERE request_id=?', (request_id,))


def reroute(db, store, row, reason, *, exclude_partner=False, allow_new_partner=True):
    """Must run inside the same write transaction as release/decline."""
    key, t = row['id'], now()
    payload = store.decrypt(row['payload'])
    if not payload.get('allow_reroute'):
        return False
    if exclude_partner and row['org_id']:
        db.execute('INSERT OR IGNORE INTO sos_skipped_partners VALUES(?,?)', (key,row['org_id']))
    event(db, 'system', key, reason)
    advanced = db.execute("""SELECT count(*) FROM sos_events
          WHERE target=? AND action IN ('partner_rerouted','same_partner_requeued')""", (key,)).fetchone()[0]
    org, why = None, 'partners_exhausted'
    remaining = row['created'] + 260 - t
    if allow_new_partner and advanced < 3 and remaining >= 15:
        excluded = [x[0] for x in db.execute('SELECT org_id FROM sos_skipped_partners WHERE request_id=?',(key,))]
        org, why = coverage(db, store, payload, exclude=excluded)
    if org:
        if org != row['org_id']:
            # Do not share one partner's private driver note with the next partner.
            payload.pop('last_driver_reason',None)
        db.execute("""UPDATE sos_requests SET org_id=?,status='queued',deadline=?,updated=?,payload=? WHERE id=?""",
                   (org,t+min(90,remaining),t,store.encrypt(payload),key))
        set_routing_reason(db,key,None)
        event(db,'system',key,'partner_rerouted' if org != row['org_id'] else 'same_partner_requeued')
    else:
        db.execute("""UPDATE sos_requests SET org_id=NULL,status='no_coverage',deadline=?,updated=? WHERE id=?""",
                   (t,t,key))
        set_routing_reason(db,key,why or 'partners_exhausted')
        event(db,'system',key,'no_coverage')
    return True


def fail(code,text):
    raise HTTPException(code,text)


def register_sos(app, store, auth):
    init(store)
    # Care recovery: sandbox only exists in the loopback test runner.
    from .partner_signup import register_partner_signup
    register_partner_signup(app, store, auth)
    sandbox = app.state.sos_sandbox
    def intake_enabled():
        return sandbox or enabled()

    @app.middleware('http')
    async def protect_dispatch(request, next_):
        path=request.url.path
        protected=path.startswith('/api/sos/') or path.startswith('/sos/')
        sandbox_hosts = {'localhost:8001','127.0.0.1:8001','localhost:18000','127.0.0.1:18000','localhost:8000','127.0.0.1:8000'}
        if sandbox and secure_origin() and request.url.scheme == 'https':
            sandbox_hosts.add(urlsplit(os.environ['MEDAI_SOS_PUBLIC_BASE_URL']).netloc.lower())
        if sandbox and request.headers.get('host','').lower() not in sandbox_hosts:
            return JSONResponse({'detail':'Local sandbox only.'},status_code=403)
        if not sandbox and protected and secure_origin() and request.url.scheme != 'https':
            return JSONResponse({'detail':'Dispatch requires a secure connection.'},status_code=403,
                headers={'Cache-Control':'no-store'})
        return await next_(request)

    def live():
        if not intake_enabled():
            fail(503,'Med.ai partner dispatch is not enabled. For an emergency in Bangladesh, use 999.')

    def member(db,user,org,role):
        if not db.execute("""SELECT 1 FROM sos_members m JOIN sos_orgs o ON m.org_id=o.id
            WHERE m.user_id=? AND m.org_id=? AND m.role=? AND m.verified=1 AND o.verified=1""",
            (user,org,role)).fetchone():
            fail(404,'No authorized dispatch record')

    def detail(db,r,mode):
        data=store.decrypt(r['payload'])
        org=db.execute('SELECT * FROM sos_orgs WHERE id=?',(r['org_id'],)).fetchone()
        a=db.execute("""SELECT a.*,v.payload AS vehicle_payload,v.org_id FROM sos_assignments a
                        JOIN sos_vehicles v ON v.id=a.vehicle_id WHERE a.request_id=? AND a.active=1""",
                         (r['id'],)).fetchone()
        result={k:r[k] for k in ('id','status','created','updated','deadline')}
        result.update(org=org_info(store,org) if org else None, eta_min=None)
        if mode!='patient': result['patient']=data
        else: result['pickup']={k:data[k] for k in ('lat','lng','accuracy') if k in data}
        if mode=='patient' and r['status']=='no_coverage':
            reason=db.execute('SELECT reason FROM sos_routing_reason WHERE request_id=?',(r['id'],)).fetchone()
            result['reason']=reason['reason'] if reason else None
        if mode=='patient' and r['status']=='queued':
            result['rerouted']=bool(db.execute("SELECT 1 FROM sos_events WHERE target=? AND action='partner_rerouted'",(r['id'],)).fetchone())
        if a:
            vehicle=store.decrypt(a['vehicle_payload'])
            driver=db.execute("SELECT payload FROM sos_members WHERE user_id=? AND org_id=? AND role='driver'",
                              (a['driver_id'],a['org_id'])).fetchone()
            gps=db.execute('SELECT * FROM sos_gps WHERE vehicle_id=?',(a['vehicle_id'],)).fetchone()
            result['assignment']={'id':a['id'],'ambulance_id':a['vehicle_id'],'state':a['status'],
                    'category':vehicle.get('category'),
                    'location':store.decrypt(gps['payload']) if gps and gps['recorded']>=a['created'] and now()-gps['recorded']<=35 and a['status']!='reserved' else None,
                    'location_recorded':gps['recorded'] if gps and gps['recorded']>=a['created'] and a['status']!='reserved' else None,
                    'driver':store.decrypt(driver['payload']) if driver and (mode!='patient' or a['status']!='reserved') else None}
            if mode=='operator':
                sms=db.execute('SELECT state,tries FROM sos_outbox WHERE id=?',(a['id'],)).fetchone()
                result['assignment']['sms']=dict(sms) if sms else None
        if mode=='operator':
            result['history']=[dict(row) for row in db.execute('SELECT action,created FROM sos_events WHERE target=? ORDER BY id DESC LIMIT 12',(r['id'],))]
        return result

    @app.get('/sos/portal', include_in_schema=False)
    def portal():
        return FileResponse(WEB/'portal.html')

    @app.get('/sos/portal.js',include_in_schema=False)
    def javascript():
        return FileResponse(WEB/'portal.js', media_type='text/javascript')

    @app.get('/sos/portal.css',include_in_schema=False)
    def css():
        return FileResponse(WEB/'portal.css', media_type='text/css')

    @app.get('/api/sos/config')
    def config():
        return {'enabled':intake_enabled(),'emergency_number':'999','map':map_config(),'mode':'sandbox' if sandbox else 'live' if enabled() else 'disabled'}

    @app.post('/api/sos/nearby')
    def availability(body:ServiceSearch, user=Depends(auth)):
        live()
        with store.db() as db:
            return nearby(db,store,body.model_dump(),body.equipment,body.category)

    @app.get('/api/sos/requests')
    def patient_requests(user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            expire(db, store, intake_enabled())
            rs=db.execute('SELECT * FROM sos_requests WHERE patient_id=? ORDER BY created DESC, rowid DESC LIMIT 8',(user['id'],))
            return [detail(db,r,'patient') for r in rs]

    @app.post('/api/sos/requests')
    def submit(body:Intake,user=Depends(auth)):
        live()
        if user['role']!='patient':
            fail(403,'Patient account required')
        payload=body.model_dump(exclude={'request_key'})
        payload['phone']=re.sub(r'\s+','',body.phone)
        if sandbox and payload['phone'] != '01700000000':
            fail(422,'Use 01700000000 for the sandbox pickup contact.')
        if not PHONE.fullmatch(payload['phone']):
            fail(422,'Enter a valid Bangladesh mobile number.')
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            expire(db, store, intake_enabled())
            prior=db.execute('SELECT * FROM sos_requests WHERE patient_id=? AND request_key=?',(user['id'],body.request_key)).fetchone()
            if prior:
                original={k:v for k,v in store.decrypt(prior['payload']).items() if k!='last_driver_reason'}
                original.setdefault('allow_reroute',False)
                if original!=payload: fail(409,'Request key was already used for different details.')
                return detail(db,prior,'patient')
            active=db.execute(f'SELECT * FROM sos_requests WHERE patient_id=? AND status IN {ACTIVE}',(user['id'],)).fetchone()
            if active: return detail(db,active,'patient')
            if db.execute('SELECT COUNT(*) FROM sos_requests WHERE patient_id=? AND created>=?',(user['id'],now()-60)).fetchone()[0]>=4:
                fail(429,'Too many requests. If you need urgent help, use 999.')
            org, reason=coverage(db, store, payload, capacity=payload['allow_reroute'])
            key=uid()
            state='queued' if org else 'no_coverage'
            db.execute('INSERT INTO sos_requests VALUES(?,?,?,?,?,?,?,?,?)',
                       (key,user['id'],body.request_key,org,state,now(),now(),now()+(90 if payload['allow_reroute'] else 120),store.encrypt(payload)))
            set_routing_reason(db,key,reason)
            event(db,user['id'],key,state)
            return detail(db,db.execute('SELECT * FROM sos_requests WHERE id=?',(key,)).fetchone(),'patient')

    @app.post('/api/sos/requests/{key}/cancel')
    def cancel(key:str,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            expire(db, store, intake_enabled())
            r=db.execute('SELECT * FROM sos_requests WHERE id=? AND patient_id=?',(key,user['id'])).fetchone()
            if not r: fail(404,'Request not found')
            status=r['status']
            if status in ('queued','awaiting_driver'):
                release(db,key,'cancelled')
                status='cancelled'
            elif status in ('dispatched','en_route','arrived'):
                status='cancel_requested'
            if status!=r['status']:
                db.execute('UPDATE sos_requests SET status=?,updated=? WHERE id=?',(status,now(),key))
                event(db,user['id'],key,status)
            return detail(db,db.execute('SELECT * FROM sos_requests WHERE id=?',(key,)).fetchone(),'patient')

    @app.get('/api/sos/roles')
    def roles(user=Depends(auth)):
        with store.db() as db:
            return [dict(r) for r in db.execute("""SELECT m.org_id,m.role FROM sos_members m JOIN sos_orgs o ON o.id=m.org_id
              WHERE m.user_id=? AND m.verified=1 AND o.verified=1""",(user['id'],))]

    @app.post('/api/sos/operator/{org}/board')
    def board(org:str,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            member(db,user['id'],org,'operator')
            expire(db, store, intake_enabled())
            if intake_enabled():
                db.execute("""UPDATE sos_members SET last_seen=? WHERE user_id=? AND org_id=? AND role='operator'
                    AND last_seen<?""",(now(),user['id'],org,now()-10))
            rows=db.execute(f'SELECT * FROM sos_requests WHERE org_id=? AND (status IN {ACTIVE} OR updated>?) ORDER BY created DESC LIMIT 60',(org,now()-600)).fetchall()
            result=[]
            for r in rows:
                result.append(detail(db,r,'operator'))
                if r['status']=='queued':
                    need=result[-1]['patient']
                    fleet=fleet_rows(db,store,org,need)
                    items=ranked(fleet,need['equipment'],need.get('category'))
                    if need.get('allow_reroute'):
                        backlog=[store.decrypt(x['payload']) for x in rows if x['id']!=r['id'] and x['status']=='queued']
                        items=spare_vehicles(fleet,backlog,items) or items
                    result[-1]['recommended']=items[:5]
                else:
                    result[-1]['recommended']=[]
            event(db,user['id'],org,'board.view') if rows and not db.execute(
                "SELECT 1 FROM sos_events WHERE target=? AND actor=? AND action='board.view' AND created>?",
                (org,user['id'],now()-60)).fetchone() else None
            return {'requests':result,'fleet':fleet_rows(db,store,org),'enabled':intake_enabled()}

    @app.post('/api/sos/operator/{org}/fleet/{vid}')
    def availability_set(org:str,vid:str,body:Availability,user=Depends(auth)):
        live()
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            member(db,user['id'],org,'operator')
            expire(db, store, intake_enabled())
            row=db.execute('SELECT * FROM sos_vehicles WHERE id=? AND org_id=?',(vid,org)).fetchone()
            if not row: fail(404,'Ambulance not found')
            if db.execute('SELECT 1 FROM sos_assignments WHERE vehicle_id=? AND active=1',(vid,)).fetchone():
                fail(409,'Ambulance already assigned')
            member(db,row['driver_id'],org,'driver')
            db.execute('UPDATE sos_vehicles SET status=? WHERE id=?',(body.status,vid))
            event(db,user['id'],vid,'fleet.'+body.status)
            return {'status':body.status}

    @app.post('/api/sos/operator/{org}/requests/{key}/assign')
    def assign(org:str,key:str,body:Assign,user=Depends(auth)):
        live()
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            member(db,user['id'],org,'operator')
            expire(db, store, intake_enabled())
            r=db.execute('SELECT * FROM sos_requests WHERE id=? AND org_id=?',(key,org)).fetchone()
            if not r: fail(404,'Request not found')
            if r['status']!='queued' or r['deadline']<=now(): fail(409,'Request is no longer waiting for assignment')
            v=db.execute("SELECT * FROM sos_vehicles WHERE id=? AND org_id=? AND status='available'",(body.vehicle_id,org)).fetchone()
            if not v or db.execute('SELECT 1 FROM sos_assignments WHERE vehicle_id=? AND active=1',(body.vehicle_id,)).fetchone():
                fail(409,'Ambulance is not available')
            member(db,v['driver_id'],org,'driver')
            need=store.decrypt(r['payload'])
            features=store.decrypt(v['payload'])
            if not set(need['equipment']) <= set(features['equipment']) or (
                need.get('category') and need['category']!=features['category']
            ):
                fail(409,'Ambulance does not meet the requested equipment or category')
            if need.get('allow_reroute'):
                fleet=fleet_rows(db,store,org,need)
                fitting=ranked(fleet,need['equipment'],need.get('category'))
                backlog=[store.decrypt(item['payload']) for item in db.execute(
                    "SELECT payload FROM sos_requests WHERE org_id=? AND id<>? AND status='queued' AND deadline>? ORDER BY created,rowid",
                    (org,key,now()))]
                spare=spare_vehicles(fleet,backlog,fitting)
                if spare and v['id'] not in {choice['id'] for choice in spare}:
                    fail(409,'Choose another matching vehicle; this one is needed for a different waiting request.')
            attempt=uid()
            db.execute('INSERT INTO sos_assignments VALUES(?,?,?,?,?,?,?,?)',
                       (attempt,key,v['id'],v['driver_id'],1,'reserved',now(),now()))
            db.execute("UPDATE sos_vehicles SET status='reserved' WHERE id=?",(v['id'],))
            db.execute('DELETE FROM sos_gps WHERE vehicle_id=?',(v['id'],))
            db.execute("UPDATE sos_requests SET status='awaiting_driver',deadline=?,updated=? WHERE id=?",(now()+driver_wait(),now(),key))
            driver=db.execute("SELECT payload FROM sos_members WHERE org_id=? AND user_id=? AND role='driver'",(org,v['driver_id'])).fetchone()
            phone=store.decrypt(driver['payload'])['phone']
            gateway_ready=not sandbox and bool(os.getenv('MEDAI_SOS_SMS_URL') and os.getenv('MEDAI_SOS_SMS_TOKEN'))
            db.execute('INSERT INTO sos_outbox VALUES(?,?,?,?,?,?)',(attempt,'queued' if gateway_ready else 'manual',0,now(),None,store.encrypt({'to':phone})))
            event(db,user['id'],key,'vehicle_reserved')
            return detail(db,db.execute('SELECT * FROM sos_requests WHERE id=?',(key,)).fetchone(),'operator')

    @app.post('/api/sos/operator/{org}/requests/{key}/decline')
    def decline(org:str,key:str,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            member(db,user['id'],org,'operator')
            expire(db, store, intake_enabled())
            r=db.execute("SELECT * FROM sos_requests WHERE id=? AND org_id=? AND status='queued'",(key,org)).fetchone()
            if not r: fail(404,'Waiting request not found')
            if reroute(db,store,r,'operator_declined',exclude_partner=True,allow_new_partner=intake_enabled()):
                return {'status':db.execute('SELECT status FROM sos_requests WHERE id=?',(key,)).fetchone()[0]}
            db.execute("UPDATE sos_requests SET status='no_coverage',updated=? WHERE id=?",(now(),key))
            event(db,user['id'],key,'operator_no_coverage')
            return {'status':'no_coverage'}

    @app.post('/api/sos/operator/{org}/requests/{key}/confirm-cancel')
    def confirm_cancel(org:str,key:str,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            member(db,user['id'],org,'operator')
            r=db.execute("SELECT * FROM sos_requests WHERE id=? AND org_id=? AND status='cancel_requested'",(key,org)).fetchone()
            if not r: fail(404,'Cancellation request not found')
            release(db,key,'cancelled','offline')
            db.execute("UPDATE sos_requests SET status='cancelled',updated=? WHERE id=?",(now(),key))
            event(db,user['id'],key,'operator_confirmed_cancellation')
            return {'status':'cancelled'}

    def driver_record(db,org,attempt,user):
        member(db,user,org,'driver')
        row=db.execute("""SELECT a.* FROM sos_assignments a JOIN sos_vehicles v ON v.id=a.vehicle_id
            WHERE a.id=? AND a.driver_id=? AND a.active=1 AND v.org_id=?""",(attempt,user,org)).fetchone()
        if not row: fail(404,'Assignment is no longer available')
        return row

    @app.get('/api/sos/driver/{org}/jobs')
    def jobs(org:str,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            member(db,user['id'],org,'driver')
            expire(db, store, intake_enabled())
            rows=db.execute("""SELECT r.* FROM sos_requests r JOIN sos_assignments a ON a.request_id=r.id
                               WHERE r.org_id=? AND a.driver_id=? AND a.active=1""",(org,user['id'])).fetchall()
            result=[]
            for r in rows:
                item=detail(db,r,'driver')
                if item['status']=='awaiting_driver':
                    # Drivers can only access contact, notes and exact location after acceptance.
                    item.pop('patient',None)
                result.append(item)
            return result

    @app.post('/api/sos/driver/{org}/jobs/{attempt}')
    def driver_action(org:str,attempt:str,body:Action,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            expire(db, store, intake_enabled())
            a=driver_record(db,org,attempt,user['id'])
            r=db.execute('SELECT * FROM sos_requests WHERE id=?',(a['request_id'],)).fetchone()
            current=r['status']
            key=r['id']
            transitions={('awaiting_driver','accept'):('dispatched','assigned'),
                         ('dispatched','en_route'):('en_route','on_the_way'),
                         ('en_route','arrived'):('arrived','at_patient_location')}
            if current=='awaiting_driver' and body.action=='reject':
                if not body.reason.strip(): fail(422,'Provide a rejection reason')
                release(db,key,'rejected','offline')
                # Keep private response details in an encrypted payload, not the audit text.
                data=store.decrypt(r['payload'])
                data['last_driver_reason']=body.reason.strip()
                db.execute("UPDATE sos_requests SET payload=? WHERE id=?",(store.encrypt(data),key))
                changed=db.execute('SELECT * FROM sos_requests WHERE id=?',(key,)).fetchone()
                if not reroute(db,store,changed,'driver_rejected',allow_new_partner=intake_enabled()):
                    db.execute("UPDATE sos_requests SET status='queued',deadline=?,updated=? WHERE id=?",(now()+120,now(),key))
            elif current in ('arrived','cancel_requested') and body.action=='complete':
                release(db,key,'completed','busy')
                db.execute("UPDATE sos_requests SET status='completed',updated=? WHERE id=?",(now(),key))
            elif (current,body.action) in transitions:
                state,fleet=transitions[current,body.action]
                db.execute('UPDATE sos_requests SET status=?,updated=? WHERE id=?',(state,now(),key))
                db.execute('UPDATE sos_assignments SET status=?,updated=? WHERE id=?',(state,now(),attempt))
                db.execute('UPDATE sos_vehicles SET status=? WHERE id=?',(fleet,a['vehicle_id']))
                if body.action=='accept':
                    db.execute("UPDATE sos_outbox SET state='cancelled' WHERE id=? AND state IN ('queued','leased')",(attempt,))
            else:
                fail(409,'Action cannot be applied to the current status')
            event(db,user['id'],key,'driver.'+body.action)
            fresh=db.execute('SELECT * FROM sos_requests WHERE id=?',(key,)).fetchone()
            if fresh['status'] in ('queued','completed','no_coverage'):
                return {'id':key,'status':fresh['status']}
            return detail(db,fresh,'driver')

    @app.post('/api/sos/driver/{org}/availability-location', status_code=204)
    def availability_location(org:str,body:Point,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            member(db,user['id'],org,'driver')
            v=db.execute("SELECT id FROM sos_vehicles WHERE driver_id=? AND org_id=? AND status='available'",
                         (user['id'],org)).fetchone()
            if not v: fail(409,'No available vehicle attached to this account')
            previous=db.execute('SELECT recorded FROM sos_gps WHERE vehicle_id=?',(v['id'],)).fetchone()
            if not previous or now()-previous['recorded']>=15:
                db.execute('INSERT OR REPLACE INTO sos_gps VALUES(?,?,?)',
                           (v['id'],now(),store.encrypt(body.model_dump())))
                event(db,user['id'],v['id'],'driver.availability_location')
            return Response(status_code=204)

    @app.post('/api/sos/driver/{org}/jobs/{attempt}/location')
    def location(org:str,attempt:str,body:Point,user=Depends(auth)):
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            a=driver_record(db,org,attempt,user['id'])
            if a['status'] not in ('dispatched','en_route','arrived'): fail(409,'Accept the assignment before sharing location')
            gps=db.execute('SELECT recorded FROM sos_gps WHERE vehicle_id=?',(a['vehicle_id'],)).fetchone()
            if gps and now()-gps['recorded']<6: return Response(status_code=204)
            db.execute('INSERT OR REPLACE INTO sos_gps VALUES(?,?,?)',
                       (a['vehicle_id'],now(),store.encrypt(body.model_dump())))
            event(db,user['id'],a['request_id'],'driver.location')
            return Response(status_code=204)
