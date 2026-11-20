"""Trusted server-admin utility. Never expose this module as a web endpoint."""
import argparse
import json
import os
import re
import sys

from pydantic import Field
from typing import Literal
from .core import Store, token_hash
from .manage import load_env
from .sos_dispatch import ACTIVE, Point, Strict, PHONE, EQUIPMENT, init, event


class Organization(Point):
    id: str = Field(pattern=r'^[a-zA-Z0-9_-]{2,64}$')
    name: str = Field(min_length=2,max_length=120)
    address: str = Field(min_length=4,max_length=220)
    phone: str = Field(min_length=5,max_length=35)
    verified: Literal[True]


class Member(Strict):
    org_id: str
    user_id: str
    role: Literal['operator','driver']
    name: str = Field(min_length=2,max_length=120)
    phone: str = Field(max_length=20)
    verified: Literal[True]


class Vehicle(Strict):
    id: str = Field(pattern=r'^[a-zA-Z0-9_-]{2,80}$')
    org_id: str
    driver_id: str
    registration: str = Field(min_length=3,max_length=45)
    category: Literal['basic','advanced','neonatal']
    equipment: list[str] = Field(default_factory=list,max_length=15)
    notes: str = Field(default='',max_length=250)


class Revoke(Strict):
    org_id: str
    user_id: str | None = None
    role: Literal['operator','driver'] | None = None


def revoke(store, raw):
    row=Revoke.model_validate(raw)
    if bool(row.user_id)!=bool(row.role):
        raise ValueError('Specify both user_id and role, or omit both to revoke the organization.')
    with store.db() as db:
        db.execute('BEGIN IMMEDIATE')
        # Close or hand over active work before disabling access to it.
        if db.execute(f'SELECT 1 FROM sos_requests WHERE org_id=? AND status IN {ACTIVE}',(row.org_id,)).fetchone():
            raise ValueError('Resolve active dispatches before revoking access.')
        if row.user_id:
            changed=db.execute("UPDATE sos_members SET verified=0,last_seen=0 WHERE org_id=? AND user_id=? AND role=? AND verified=1",
                               (row.org_id,row.user_id,row.role))
            if row.role=='driver':
                db.execute("UPDATE sos_vehicles SET status='offline' WHERE org_id=? AND driver_id=?",(row.org_id,row.user_id))
        else:
            changed=db.execute('UPDATE sos_orgs SET verified=0 WHERE id=? AND verified=1',(row.org_id,))
            db.execute("UPDATE sos_vehicles SET status='offline' WHERE org_id=?",(row.org_id,))
        if not changed.rowcount: raise ValueError('No verified record matched.')
        event(db,'server-admin',row.org_id,'verification.revoked')
    return row.org_id


def enroll(store, kind, raw):
    with store.db() as db:
        db.execute('BEGIN IMMEDIATE')
        if kind=='organization':
            row=Organization.model_validate(raw)
            db.execute('INSERT INTO sos_orgs VALUES(?,?,?)',
                       (row.id,1,store.encrypt(row.model_dump(exclude={'id','verified'}))))
            target=row.id
        elif kind=='member':
            row=Member.model_validate(raw)
            if not PHONE.fullmatch(row.phone): raise ValueError('A valid Bangladesh mobile number is required.')
            if not db.execute('SELECT 1 FROM sos_orgs WHERE id=? AND verified=1',(row.org_id,)).fetchone():
                raise ValueError('Verify the organization first.')
            db.execute('INSERT INTO sos_members VALUES(?,?,?,?,?,?)',
                       (row.user_id,row.org_id,row.role,1,0,store.encrypt({'name':row.name,'phone':row.phone})))
            target=row.org_id
        elif kind=='vehicle':
            row=Vehicle.model_validate(raw)
            if not db.execute("SELECT 1 FROM sos_members WHERE org_id=? AND user_id=? AND role='driver' AND verified=1",
                              (row.org_id,row.driver_id)).fetchone():
                raise ValueError('Verify the driver account in the same organization first.')
            if not set(row.equipment) <= EQUIPMENT:
                raise ValueError('Unknown equipment; use: '+', '.join(sorted(EQUIPMENT)))
            plate=token_hash(re.sub(r'[\s-]','',row.registration.casefold()))
            db.execute('INSERT INTO sos_vehicles VALUES(?,?,?,?,?,?)',
                (row.id,row.org_id,row.driver_id,'offline',plate,
                 store.encrypt(row.model_dump(exclude={'id','org_id','driver_id'}))))
            target=row.id
        else:
            raise ValueError('Unknown record type')
        event(db,'server-admin',target,'verified_enrollment.'+kind)
    return target


def approve_pending(store, raw):
    org = str(raw.get('organization_id', ''))
    if not re.fullmatch(r'partner-[0-9a-f]{32}', org):
        raise ValueError('Enter the organization ID shown at registration.')
    with store.db() as db:
        db.execute('BEGIN IMMEDIATE')
        if not db.execute("SELECT 1 FROM sos_events WHERE target=? AND action='verification_requested'", (org,)).fetchone():
            raise ValueError('No matching enrollment.')
        if db.execute("SELECT 1 FROM sos_events WHERE target=? AND action='verification.revoked'", (org,)).fetchone():
            raise ValueError('Revoked accounts require separate review.')
        db.execute('UPDATE sos_orgs SET verified=1 WHERE id=?', (org,))
        db.execute("UPDATE sos_members SET verified=1 WHERE org_id=? AND role='operator'", (org,))
        event(db, 'server-admin', org, 'verification.approved')
    return org


def open_store():
    load_env()
    return Store(os.environ.get('MEDAI_DATA_DIR','./data'),os.environ['MEDAI_ENCRYPTION_KEY'])


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('kind',choices=['organization','member','vehicle','revoke','approve-pending'])
    args=p.parse_args()
    store=open_store()
    init(store)
    # Pipe a local private JSON file over stdin. Do not log its contents.
    try:
        raw=json.load(sys.stdin)
        target=approve_pending(store,raw) if args.kind=='approve-pending' else revoke(store,raw) if args.kind=='revoke' else enroll(store,args.kind,raw)
    except Exception as exc:
        print(f'Enrollment rejected ({type(exc).__name__}); validate fields, existing IDs and uniqueness.',file=sys.stderr)
        return 1
    print('Updated:',target)
    return 0


if __name__=='__main__':
    raise SystemExit(main())
