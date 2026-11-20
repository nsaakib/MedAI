"""Exact catalog matches and per-account purchase preferences, never prescriptions."""
import json
from pathlib import Path
import re
import unicodedata

from fastapi import Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, StrictBool

CATALOG = Path(__file__).with_name('brand_catalog.json')
FORMS = {'tab':'tablet','tab.':'tablet','tablets':'tablet',
         'cap':'capsule','cap.':'capsule','capsules':'capsule',
         'ec capsule':'capsule',
         'enteric coated capsule':'capsule','delayed release capsule':'capsule','capsule (enteric coated)':'capsule'}
RELEASE = re.compile(r'\b(xr|er|sr|cr|mr|dr|ec|mups|extended[- ]release|delayed[- ]release|enteric[- ]coated|chewable|dispersible|sublingual)\b', re.I)



def key(value):
    return ' '.join(unicodedata.normalize('NFKC', str(value or '')).casefold().split())


def strength_key(value):
    text = re.sub(r'\s+', '', key(value))
    # A slash between two mass doses is a combination, not a concentration.
    # Never normalize mg/ml, ratios, or numbers with no explicit final unit.
    if re.fullmatch(r'\d+(?:\.\d+)?(?:mg)?(?:[+/]\d+(?:\.\d+)?(?:mg)?)*[+/]\d+(?:\.\d+)?mg', text):
        return '+'.join(x if x.endswith('mg') else x+'mg' for x in re.split(r'[+/]', text))
    return text


def identity(row):
    form=key(row.get('form')).replace('-', ' ')
    form=FORMS.get(form,form)
    strength=strength_key(row.get('strength'))
    name=key(row.get('name'))
    name=re.sub(r'^(?:tab\.?|cap\.?)\s+', '', name)
    # Normalize only explicit units, never guess from a bare brand number.
    embedded=re.search(r'(?<![\d./+])\s*(\d+(?:\.\d+)?(?:\s*mg)?(?:\s*[+/]\s*\d+(?:\.\d+)?(?:\s*mg)?)*\s*(?:mg|mcg|g))\s*$',name)
    if embedded:
        stated=strength_key(embedded[1])
        if strength and stated!=strength:
            return name,strength,form
        strength=strength or stated
        name=name[:embedded.start()].strip()
    elif strength:
        number=re.fullmatch(r'(\d+(?:\.\d+)?)(?:mg|mcg|g)',strength)
        if number:
            name=re.sub(r'\s+'+re.escape(number[1])+r'$', '',name)
    return name,strength,form


def formulation(row):
    return (key(row['ingredients']), strength_key(row['strength']), *(key(row[k]) for k in ('form','route','release')))


def load_catalog():
    rows=json.loads(CATALOG.read_text(encoding='utf-8'))
    return rows


def options(medicine, rows):
    original=[x for x in rows if identity(x)==identity(medicine)]
    if len(original)!=1 or not medicine.get('verified'):
        return None,[]
    original=original[0]
    instruction=key(medicine.get('instruction'))
    flags={x.group().lower() for x in RELEASE.finditer(instruction+' '+key(medicine.get('form')))}
    allowed={'ec','dr','delayed-release','delayed release','enteric-coated','enteric coated'} if original['release']=='delayed' else set()
    if flags - allowed:
        return None,[]
    if key(medicine.get('route')) not in ('',key(original['route']),'po','by mouth'):
        return None,[]
    return original,[x for x in rows if formulation(x)==formulation(original) and key(x['name'])!=key(original['name'])][:4]


class Choice(BaseModel):
    model_config=ConfigDict(extra='forbid')
    alternative_id: str | None=Field(default=None,max_length=80)
    confirmed: StrictBool=False


def register_brand_options(app, store, auth):
    with store.db() as db:
        db.execute("""CREATE TABLE IF NOT EXISTS medicine_brand_preference(
           user_id TEXT NOT NULL REFERENCES users(id), medicine_id TEXT NOT NULL,
           payload BLOB NOT NULL, PRIMARY KEY(user_id,medicine_id))""")
    rows=load_catalog()

    def medicine(db,user,item):
        state=db.execute('SELECT payload FROM states WHERE user_id=?',(user,)).fetchone()
        decoded=store.decrypt(state['payload']) if state else {}
        for row in decoded.get('medicines',[]):
            if row['id']==item:
                return row
        raise HTTPException(404,'Medicine not found. Save and sync the prescription first.')

    @app.get('/api/medicine-brands/{item}')
    def lookup(item: str,user=Depends(auth)):
        owner=user['id']
        with store.db() as db:
            saved=medicine(db,owner,item)
            source,candidates=options(saved,rows)
            choice=db.execute('SELECT payload FROM medicine_brand_preference WHERE user_id=? AND medicine_id=?',(owner,item)).fetchone()
        preferred=store.decrypt(choice['payload']) if choice else {}
        selected=next((row['id'] for row in candidates if row['id']==preferred.get('id') and
                       list(identity(saved))==preferred.get('identity')),None)
        return {'supported_products': len(rows), 'reason': ('review_required' if not saved.get('verified') else 'exact_match' if source else 'not_catalogued'), 'prescribed':{k:saved.get(k) for k in ('name','strength','form')},
                'catalog_match':source,'candidates':candidates,'preferred_id':selected}

    @app.put('/api/medicine-brands/{item}')
    def save(item: str, body: Choice,user=Depends(auth)):
        owner=user['id']
        if not body.confirmed:
            raise HTTPException(422,'Explicit confirmation is required.')
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            saved=medicine(db,owner,item)
            _,candidates=options(saved,rows)
            if body.alternative_id is not None:
                if body.alternative_id not in {row['id'] for row in candidates}:
                    raise HTTPException(422,'No exact catalog match for the saved prescription.')
                db.execute('INSERT OR REPLACE INTO medicine_brand_preference VALUES(?,?,?)',
                           (owner,item,store.encrypt({'id':body.alternative_id,'identity':list(identity(saved))})))
            else:
                db.execute('DELETE FROM medicine_brand_preference WHERE user_id=? AND medicine_id=?',(owner,item))
            store.audit(db,owner,'medicine.brand_preference_changed',item)
        return {'preferred_id':body.alternative_id}
