"""Authenticated health statistics and report recovery."""
from collections import defaultdict
from datetime import date
import math
import os
import re

from fastapi import Depends, HTTPException
from pydantic import Field

import subprocess
import tempfile
from pathlib import Path

from .reports import detect_report
from .reports import with_report_details
from .schemas import Strict

MEASURES = {
    'hemoglobin': ('Hemoglobin', {'g/dl'}),
    'wbc': ('White blood cells', {'cells/ul', '/ul', '10^3/ul', '10^9/l'}),
    'platelets': ('Platelets', {'cells/ul', '/ul', '10^3/ul', '10^9/l'}),
    'rbc': ('Red blood cells', {'10^6/ul', '10^12/l', 'million/ul'}),
    'hematocrit': ('Hematocrit', {'%'}),
    'mcv': ('MCV', {'fl'}),
    'hba1c': ('HbA1c', {'%', 'mmol/mol'}),
    'glucose': ('Report glucose', {'mg/dl', 'mmol/l'}),
    'creatinine': ('Creatinine', {'mg/dl', 'umol/l'}),
}
ALIASES = {
    'hemoglobin': r'hemoglobin|haemoglobin|hb', 'wbc': r'wbc(?: count)?|white blood cell count',
    'platelets': r'platelets?(?: count)?', 'rbc': r'rbc(?: count)?|red blood cell count',
    'hematocrit': r'hematocrit|haematocrit|hct|pcv', 'mcv': r'mcv',
    'hba1c': r'hba1c', 'glucose': r'glucose', 'creatinine': r'creatinine',
}
TEST_LINES = {
    key: re.compile(r'^[ \t]*(?:' + alias + r')[ \t]*[:=|]?[ \t]*'
                    r'(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)'
                    r'[ \t]*(?:[HL*][ \t]+)?(?:\|[ \t]*)?(' + '|'.join(re.escape(unit) for unit in sorted(MEASURES[key][1], key=len, reverse=True))
                    + r')(?=\s|$)', re.I | re.M)
    for key, alias in ALIASES.items()
}


def extract(ocr):
    text = ocr.replace('µ','u').replace('μ','u').replace('×','x')
    for superscript, exponent in [('³','^3'), ('⁶','^6'), ('⁹','^9'), ('¹²','^12')]:
        text = text.replace(superscript, exponent)
    text = re.sub(r'10[ \t]*\^[ \t]*(\d+)[ \t]*/[ \t]*', r'10^\1/', text)
    text = re.sub(r'(?im)^([ \t]*[^\n]*?)[ \t]+(gm/dl|gms/dl|cu\.? ?mm|/cumm)(?=\s|$)',
                  lambda m: m[1] + ' ' + ('g/dL' if m[2].lower().startswith('g') else 'cells/ul'), text)
    text = re.sub(r'g[ \t]*/[ \t]*dl', 'g/dL', text, flags=re.I)
    text = re.sub(r'[xX][ \t]*(10\^\d+)', r'\1', text, flags=re.I)
    for key, pattern in TEST_LINES.items():
        hits = {(float(m[1].replace(',', '')), m[2].lower()) for m in pattern.finditer(text)}
        if len(hits) == 1:
            value, unit = hits.pop()
            if math.isfinite(value):
                yield {'metric': key, 'name': MEASURES[key][0], 'value': value, 'unit': unit}


def snapshot(store, uid, analysis=False):
    with store.db() as db:
        reports = db.execute('SELECT id,payload FROM documents WHERE user_id=? ORDER BY created', (uid,)).fetchall()
        row = db.execute('SELECT payload FROM states WHERE user_id=?', (uid,)).fetchone()
    manual = store.decrypt(row['payload']).get('vitals', []) if row else []
    groups = defaultdict(list)
    for v in sorted(manual, key=lambda r: str(r.get('measured_at', ''))):
        if (isinstance(v.get('value'), (int,float)) and math.isfinite(v['value'])
                and v.get('unit') and v.get('kind')):
            groups[(v['kind'],v['unit'])].append({k:v.get(k) for k in ('value','measured_at')})
    readings = []
    for (kind, unit), points in groups.items():
        readings.append(dict(kind=kind, unit=unit, count=len(points),
                             minimum=min(p['value'] for p in points), maximum=max(p['value'] for p in points),
                             recent=points[-8:]))
    series = defaultdict(list)
    context = []
    for row in reports:
        item = with_report_details(store.decrypt(row['payload']))
        if item.get('kind') != 'Lab Report':
            continue
        label = f'R{len(context)+1}'
        text = item.get('ocr_text') or ''
        entered = item.get('statistics_verified_values', {})
        points = [dict(p, origin='OCR') for p in extract(item.get('statistics_ocr_text') or text) if p['metric'] not in entered]
        points += [dict(metric=k, name=MEASURES[k][0], value=v['value'], unit=v['unit'], origin='Entered from report')
                   for k,v in entered.items() if k in MEASURES]
        day = item.get('report_date')
        try:
            day = date.fromisoformat(day).isoformat()
        except (TypeError, ValueError):
            day = None
        title = item.get('report_title') or 'Lab report'
        for point in points:
            series[(point['name'],point['unit'])].append(
                dict(value=point['value'], date=day, document_id=row['id'], title=title, origin=point['origin']))
        context.append(dict(label=label, title=title, date=day, has_text=bool(text.strip()),
                            extracted=points, document_id=row['id'], can_retry=True,
                            **({'ocr_excerpt': text[:750], 'excerpt_truncated': len(text)>750} if analysis else {})))
    return dict(readings=readings, reports=context,
                series=[dict(name=k[0],unit=k[1],points=v) for k,v in sorted(series.items())])


class LabValue(Strict):
    metric: str
    value: float = Field(ge=0, le=1_000_000_000, allow_inf_nan=False)
    unit: str


def register_statistics(app, store, auth):
    def lab(db, uid, identifier):
        row = db.execute('SELECT payload FROM documents WHERE id=? AND user_id=?',
                         (identifier, uid)).fetchone()
        if row is None:
            raise HTTPException(404, 'Lab report not found.')
        item = store.decrypt(row['payload'])
        if item.get('kind') != 'Lab Report':
            raise HTTPException(404, 'Lab report not found.')
        return item

    @app.get('/api/statistics')
    def statistics(user=Depends(auth)):
        result = snapshot(store, user['id'])
        result['supported'] = [dict(metric=k, name=v[0], units=sorted(v[1])) for k,v in MEASURES.items()]
        return result

    @app.post('/api/statistics/reports/{identifier}/value')
    def save_value(identifier: str, body: LabValue, user=Depends(auth)):
        if body.metric not in MEASURES or body.unit not in MEASURES[body.metric][1]:
            raise HTTPException(422, 'Choose a supported test and its original unit.')
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            item = lab(db, user['id'], identifier)
            item.setdefault('statistics_verified_values', {})[body.metric] = {
                'value': body.value, 'unit': body.unit}
            db.execute('UPDATE documents SET payload=? WHERE id=? AND user_id=?',
                       (store.encrypt(item), identifier, user['id']))
        return {'saved': True}

    @app.post('/api/statistics/reports/{identifier}/ocr')
    def retry_ocr(identifier: str, user=Depends(auth)):
        with store.db() as db:
            item = lab(db, user['id'], identifier)
        if os.getenv('MEDAI_OCR_ENABLED', 'false').lower() != 'true':
            raise HTTPException(503, 'Server OCR is disabled. Enable Tesseract OCR or enter values from the report.')
        try:
            with tempfile.TemporaryDirectory() as tmp:
                source = Path(tmp) / 'report.jpg'
                source.write_bytes(store.cipher.decrypt((store.files / identifier).read_bytes()))
                language = item.get('language', 'eng')
                if language not in ('eng','ben','eng+ben'):
                    language = 'eng'
                result = subprocess.run(['tesseract',str(source),'stdout','-l',language,'--psm','6'],
                    capture_output=True, encoding='utf-8', errors='replace', timeout=35, check=True)
                text = result.stdout[:50000]
        except (OSError, subprocess.SubprocessError):
            raise HTTPException(503, 'Could not run OCR. Check Tesseract or enter values from the original report.') from None
        if not text.strip() or not list(extract(text)):
            raise HTTPException(422, 'OCR found no chartable values. Enter values from the original report.')
        with store.db() as db:
            db.execute('BEGIN IMMEDIATE')
            latest = lab(db, user['id'], identifier)
            if latest.get('ocr_text') != item.get('ocr_text'):
                raise HTTPException(409, 'The report changed. Refresh Statistics and try again.')
            # Preserve existing readable OCR and only use retry text as the chart
            # source. This avoids overwriting text already used by Reports/chat.
            latest['statistics_ocr_text'] = text
            if not (latest.get('ocr_text') or '').strip():
                latest.update(ocr_text=text, ocr_status='text_ready', ocr_engine='tesseract')
            if not latest.get('report_date'):
                latest['report_date'] = detect_report(text)['report_date']
            db.execute('UPDATE documents SET payload=? WHERE id=? AND user_id=?',
                       (store.encrypt(latest), identifier, user['id']))
        return {'updated': True}
