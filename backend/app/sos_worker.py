"""Independently process driver timeouts and a private idempotent SMS gateway."""
import os
import time
from urllib.parse import urlsplit

import httpx

from .core import now, uid
from .sos_admin import open_store
from .sos_dispatch import enabled, event, expire, init


def run_once(store, send=None):
    t=now()
    with store.db() as db:
        db.execute('BEGIN IMMEDIATE')
        expire(db, store, enabled())
        db.execute("UPDATE sos_outbox SET state='failed',lease=NULL WHERE state IN ('queued','leased') AND tries>=4 AND ready<=?",(t,))
        row=db.execute("""SELECT o.* FROM sos_outbox o JOIN sos_assignments a ON a.id=o.id
                          JOIN sos_requests r ON r.id=a.request_id
                          WHERE o.state IN ('queued','leased') AND o.ready<=? AND o.tries<4
                          AND a.active=1 AND r.status='awaiting_driver' AND r.deadline>?
                          ORDER BY o.ready LIMIT 1""",(t,t)).fetchone() if enabled() else None
        if not row: return False
        lease=uid()
        db.execute("UPDATE sos_outbox SET state='leased',tries=tries+1,ready=?,lease=? WHERE id=?",(t+20,lease,row['id']))
        recipient=store.decrypt(row['payload'])['to']
    # Do not include patient details or bearer tokens in the SMS. A cancellation
    # can race an in-flight SMS; the login portal only shows active work.
    base=os.environ['MEDAI_SOS_PUBLIC_BASE_URL'].rstrip('/')
    attempt=row['id']
    try:
        (send or send_gateway)(recipient,f'Med.ai: sign in to review a dispatch assignment: {base}/sos/portal',attempt)
        ok=True
    except Exception:
        ok=False
    with store.db() as db:
        db.execute('BEGIN IMMEDIATE')
        tries=row['tries']+1
        state='submitted_to_gateway' if ok else 'failed' if tries>=4 else 'queued'
        result=db.execute("UPDATE sos_outbox SET state=?,lease=NULL,ready=? WHERE id=? AND state='leased' AND lease=?",
                          (state,now()+min(30,2**tries),attempt,lease))
        if result.rowcount:
            request=db.execute('SELECT request_id FROM sos_assignments WHERE id=?',(attempt,)).fetchone()
            event(db,'worker',request['request_id'],'sms.'+state)
    return True


def send_gateway(to,text,key):
    url=os.environ['MEDAI_SOS_SMS_URL']
    parts=urlsplit(url)
    if parts.scheme!='https' or not parts.hostname or parts.username or parts.password:
        raise ValueError('The SMS adapter must be an HTTPS endpoint.')
    response=httpx.post(url,json={'to':to,'text':text},
        headers={'Authorization':'Bearer '+os.environ['MEDAI_SOS_SMS_TOKEN'],'Idempotency-Key':key},
        timeout=8, follow_redirects=False)
    response.raise_for_status()
    if response.json().get('accepted') is not True:
        raise ValueError('Gateway did not accept the message.')


if __name__=='__main__':
    store=open_store()
    init(store)
    while True:
        run_once(store)
        time.sleep(2)
