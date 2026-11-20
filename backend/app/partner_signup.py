"""Partner enrollment never confers production dispatch access."""
import secrets
from typing import Literal
from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field
from .core import now, uid, token_hash, password_hash
from .sos_dispatch import Point, PHONE, event


class Enrollment(Point):
    name: str = Field(min_length=2, max_length=120)
    organization: str = Field(min_length=2, max_length=120)
    address: str = Field(min_length=4, max_length=220)
    phone: str = Field(max_length=20)


class TestFleet(BaseModel):
    vehicle_id: str = Field(min_length=1,max_length=80)
    category: Literal['basic','advanced']


def register_partner_signup(app, store, auth):
    @app.get('/api/sos/partner/enrollment')
    def enrollment_status(user=Depends(auth)):
        with store.db() as db:
            rows = db.execute("""SELECT m.org_id,m.verified,o.verified AS org_verified
                FROM sos_members m JOIN sos_orgs o ON m.org_id=o.id
                WHERE m.user_id=? AND m.role='operator'""", (user['id'],)).fetchall()
        return [{'organization_id': r['org_id'],
                 'status': 'approved' if r['verified'] and r['org_verified'] else 'pending'} for r in rows]

    @app.post('/api/sos/partner/enrollment', status_code=201)
    def enroll(body: Enrollment, user=Depends(auth)):
        sandbox = app.state.sos_sandbox
        phone = body.phone.replace(' ', '')
        if not sandbox and not PHONE.fullmatch(phone):
            raise HTTPException(422, 'Enter a valid Bangladesh mobile number.')
        if sandbox and phone != '01700000000':
            raise HTTPException(422, 'Use the test number 01700000000 in the sandbox.')
        if not all(v.strip() for v in (body.name, body.organization, body.address)):
            raise HTTPException(422, 'Enter a name, organization and address.')
        owner = user['id']
        driver_password = secrets.token_urlsafe(24) if sandbox else None
        encoded = password_hash(driver_password) if sandbox else None
        org = 'partner-' + uid()
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute("SELECT 1 FROM sos_members WHERE user_id=? AND role='operator'", (owner,)).fetchone():
                raise HTTPException(409, 'This account already has a partner enrollment. Use Staff and driver sign-in.')
            db.execute('INSERT INTO sos_orgs VALUES(?,?,?)',
                       (org, int(sandbox), store.encrypt(dict(name=('TEST · ' if sandbox else '') + body.organization.strip(),
                         address=body.address.strip(), lat=body.lat, lng=body.lng, phone='' if sandbox else phone))))
            db.execute('INSERT INTO sos_members VALUES(?,?,?,?,?,?)',
                       (owner, org, 'operator', int(sandbox), 0, store.encrypt(dict(name=body.name.strip(), phone='' if sandbox else phone))))
            event(db, owner, org, 'sandbox_enrolled' if sandbox else 'verification_requested')
            result = {'organization_id': org, 'status': 'approved' if sandbox else 'pending'}
            if sandbox:
                driver_id = uid()
                email = f'driver-{org}@example.test'
                db.execute('INSERT INTO users VALUES(?,?,?,?,?)',
                           (driver_id, token_hash(email), encoded, 'patient', now()))
                db.execute('INSERT INTO states VALUES(?,?,?)',
                           (driver_id, 0, store.encrypt(dict(name='Test Driver', email=email))))
                db.execute('INSERT INTO sos_members VALUES(?,?,?,?,?,?)',
                           (driver_id, org, 'driver', 1, 0, store.encrypt(dict(name='Test Driver', phone=''))))
                db.execute('INSERT INTO sos_vehicles VALUES(?,?,?,?,?,?)',
                           ('TEST-'+uid(), org, driver_id, 'available', token_hash(org),
                            store.encrypt(dict(registration='SANDBOX', category='basic',
                                               equipment=['oxygen','stretcher'], notes='Test vehicle only'))))
                result.update(driver_email=email, driver_password=driver_password)
        return result

    @app.post('/api/sos/partner/{org}/test-fleet')
    def test_fleet(org: str, body: TestFleet, user=Depends(auth)):
        if not app.state.sos_sandbox:
            raise HTTPException(404,'Not found.')
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            allowed=db.execute("""SELECT 1 FROM sos_members m JOIN sos_orgs o ON o.id=m.org_id
                WHERE m.org_id=? AND m.user_id=? AND m.role='operator' AND m.verified=1 AND o.verified=1""",
                (org,user['id'])).fetchone()
            if not allowed:
                raise HTTPException(404,'No authorized dispatch record.')
            row=db.execute("SELECT * FROM sos_vehicles WHERE id=? AND org_id=?",(body.vehicle_id,org)).fetchone()
            if not row or not row['id'].startswith('TEST-'):
                raise HTTPException(404,'Sandbox vehicle not found.')
            active=db.execute("SELECT 1 FROM sos_assignments WHERE vehicle_id=? AND active=1",(row['id'],)).fetchone()
            queued=db.execute("SELECT 1 FROM sos_requests WHERE org_id=? AND status='queued' AND deadline>?",
                              (org,now())).fetchone()
            if active or queued:
                raise HTTPException(409,'Finish or cancel the waiting or active test request before changing the vehicle.')
            vehicle=store.decrypt(row['payload'])
            vehicle['category']=body.category
            vehicle['equipment']=(['oxygen','stretcher','monitor','ventilator'] if body.category=='advanced'
                                  else ['oxygen','stretcher'])
            db.execute("UPDATE sos_vehicles SET status='available',payload=? WHERE id=?",
                       (store.encrypt(vehicle),row['id']))
            event(db,user['id'],row['id'],'test_fleet.profile_changed')
        return {'category':body.category,'equipment':vehicle['equipment']}
