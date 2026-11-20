"""Private profile details and attachments, kept out of assistant retrieval."""
from datetime import date
import io
import ipaddress
from pathlib import PurePosixPath
import re
from typing import Literal
from urllib.parse import quote
from PIL import Image
from fastapi import Depends, File, Form, HTTPException, UploadFile, Response, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from .core import now, uid


class Details(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    birth_date: date | None = None
    blood_group: Literal['','A+','A-','B+','B-','AB+','AB-','O+','O-'] = ''
    address: str = Field(default='', max_length=240)
    emergency_contact_name: str = Field(default='', max_length=120)
    emergency_contact_phone: str = Field(default='', pattern=r'^$|^\+?[0-9][0-9 -]{5,22}$')
    medical_notes: str = Field(default='', max_length=1000)


MAX_FILE = 8 * 1024 * 1024


def document_type(content):
    if re.match(rb'^%PDF-[12]\.[0-9]', content) and b'%%EOF' in content[-2048:]:
        return 'application/pdf', '.pdf'
    try:
        with Image.open(io.BytesIO(content)) as image:
            if image.width * image.height > 24000000 or image.format not in ('JPEG', 'PNG'):
                return None
            image.verify()
            return ('image/jpeg', '.jpg') if image.format == 'JPEG' else ('image/png', '.png')
    except (OSError, ValueError, Image.DecompressionBombError, SyntaxError):
        return None


def register_private_profile(app, store, auth):
    @app.middleware('http')
    async def protect_profile(request: Request, next_):
        if request.url.path.startswith('/api/private-profile') and request.url.scheme != 'https':
            # Allow desktop localhost and the phone's USB reverse connection.
            try:
                peer = request.client.host if request.client else ''
                local_peer = ipaddress.ip_address(peer).is_loopback
            except ValueError:
                local_peer = False
            if not local_peer or request.url.hostname not in ('127.0.0.1','localhost','::1'):
                return JSONResponse({'detail':'Use HTTPS or the local USB connection for private profile data.'},
                                    status_code=403,headers={'Cache-Control':'no-store'})
        return await next_(request)

    with store.db() as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS private_profile(
                user_id TEXT PRIMARY KEY REFERENCES users(id), payload BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS private_profile_files(
                id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
                meta BLOB NOT NULL, content BLOB NOT NULL, created INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS private_profile_files_owner ON private_profile_files(user_id,created);
        """)

    @app.get('/api/private-profile')
    def get(user=Depends(auth)):
        with store.db() as db:
            row = db.execute('SELECT payload FROM private_profile WHERE user_id=?',(user['id'],)).fetchone()
            files = db.execute('SELECT id,meta,created FROM private_profile_files WHERE user_id=? ORDER BY created DESC,rowid DESC',
                               (user['id'],)).fetchall()
        return {'details': store.decrypt(row['payload']) if row else Details().model_dump(mode='json'),
                'files': [dict(id=f['id'], created=f['created'], **store.decrypt(f['meta'])) for f in files]}

    @app.put('/api/private-profile')
    def save(body: Details, user=Depends(auth)):
        if body.birth_date and not date(1900,1,1) <= body.birth_date <= date.today():
            raise HTTPException(422, 'Enter a valid birth date.')
        data = body.model_dump(mode='json')
        with store.db() as db:
            db.execute('INSERT OR REPLACE INTO private_profile VALUES(?,?)',(user['id'],store.encrypt(data)))
            store.audit(db,user['id'],'profile.details.saved',user['id'])
        return data

    @app.post('/api/private-profile/files', status_code=201)
    def upload(file: UploadFile = File(...), category: Literal['medical','identity','insurance','other'] = Form(...),
               user=Depends(auth)):
        content = file.file.read(MAX_FILE + 1)
        if len(content) > MAX_FILE:
            raise HTTPException(413, 'Choose a document up to 8 MB.')
        detected = document_type(content)
        if not detected:
            raise HTTPException(422, 'Choose a readable PDF, JPEG or PNG.')
        media, extension = detected
        raw_name = PurePosixPath((file.filename or 'Document').replace('\\','/')).stem
        name = (re.sub(r'[\x00-\x1f\x7f]', '', raw_name).strip()[:120] or 'Document') + extension
        meta = dict(name=name, media_type=media, category=category, size=len(content))
        key = uid()
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            count = db.execute('SELECT count(*) FROM private_profile_files WHERE user_id=?',(user['id'],)).fetchone()[0]
            if count >= 12:
                raise HTTPException(409, 'Remove a document before adding another (limit: 12).')
            db.execute('INSERT INTO private_profile_files VALUES(?,?,?,?,?)',
                       (key,user['id'],store.encrypt(meta),store.cipher.encrypt(content),now()))
            store.audit(db,user['id'],'profile.file.uploaded',key)
        return dict(id=key, **meta)

    @app.get('/api/private-profile/files/{identifier}')
    def download(identifier: str, user=Depends(auth)):
        with store.db() as db:
            row = db.execute('SELECT * FROM private_profile_files WHERE id=? AND user_id=?',
                             (identifier,user['id'])).fetchone()
        if row is None:
            raise HTTPException(404, 'Document not found.')
        meta = store.decrypt(row['meta'])
        return Response(store.cipher.decrypt(row['content']), media_type=meta['media_type'],
                        headers={'Content-Disposition':"attachment; filename*=UTF-8''"+quote(meta['name'], safe='')})

    @app.delete('/api/private-profile/files/{identifier}', status_code=204)
    def delete(identifier: str, user=Depends(auth)):
        with store.db() as db:
            changed = db.execute('DELETE FROM private_profile_files WHERE id=? AND user_id=?',
                                 (identifier,user['id'])).rowcount
            if not changed:
                raise HTTPException(404,'Document not found.')
            store.audit(db,user['id'],'profile.file.deleted',identifier)
        return Response(status_code=204)
