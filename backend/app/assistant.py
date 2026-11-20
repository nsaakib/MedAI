"""Account-scoped AI conversations and retrieval over Med.ai records."""
import json
import os
from pathlib import Path
import re
import threading
from uuid import uuid4

from fastapi import Depends, HTTPException
from pydantic import Field

from . import report_chat
from . import grok_education
from .health_statistics import snapshot as statistics_snapshot
from .core import now
from .care_navigation import navigation
# Med.ai directory lookup for explicit specialty requests
from .doctor_directory_lookup import INTENT, department_labels, direct_specialty, find_doctors, primary_label
from .clinical_navigation import CONTRACT, emergency, parse, plain_headache_route, present, rank_doctors, scan, screening

DIVISIONS = ('Dhaka', 'Rajshahi', 'Barishal')
# Med.ai Connected Care: clinical navigation directory
_medai_directory_path = Path(__file__).with_name('assistant_current_directory.json')
if not _medai_directory_path.is_file():
    _medai_directory_path = Path(__file__).with_name('assistant_doctors.json')
DATA = json.loads(_medai_directory_path.read_text(encoding='utf-8'))

SYSTEM = report_chat.SYSTEM + """
You are Med.ai's health information and navigation assistant.
Treat measurements as patient-entered; cite supplied measurements as [H1], etc.
Do not infer blood pressure pairs. Keep answers concise and uncertainty visible.
"""


class Ask(report_chat.ChatRequest):
    summarize_statistics: bool = False
    use_records: bool = False
    division: str = Field(default='', max_length=20)


def vitals(store, uid, question):
    with store.db() as db:
        row = db.execute('SELECT payload FROM states WHERE user_id=?', (uid,)).fetchone()
    data = store.decrypt(row['payload']).get('vitals', []) if row else []
    q = question.lower()
    groups = [
        (('pressure', 'bp', 'রক্তচাপ', 'প্রেশার'), {'systolic_bp', 'diastolic_bp'}),
        (('glucose', 'diabet', 'sugar', 'ডায়াবেটিস', 'সুগার', 'গ্লুকোজ'), {'glucose'}),
        (('pulse', 'heart rate', 'হৃদস্পন্দন'), {'heart_rate'}),
        (('weight', 'ওজন'), {'weight'}),
    ]
    wanted = set().union(*(keys for terms, keys in groups if any(t in q for t in terms)))
    ordered = sorted((v for v in data if isinstance(v, dict) and isinstance(v.get('value'), (int, float))),
                     key=lambda v: str(v.get('measured_at', '')), reverse=True)
    result, counts = [], {}
    for v in ordered:
        k = v.get('kind')
        if (wanted and k not in wanted) or counts.get(k, 0) >= 4:
            continue
        counts[k] = counts.get(k, 0) + 1
        result.append({'label': f'H{len(result)+1}', **{f: v.get(f) for f in ('kind','value','unit','measured_at')}})
        if len(result) == 12:
            break
    return result


def findings(sources):
    # Exact OCR lines only. Never infer reference ranges or clinical status.
    pattern = re.compile(
        r'^\s*(hemoglobin|haemoglobin|hb|wbc|platelets?|hba1c|glucose|creatinine)'
        r'\s*[:=]?\s*(\d+(?:[.,]\d+)*(?:\s*(?:g/dL|mg/dL|mmol/L|cells/[µμu]L|%))?)'
        r'(?=\s|$)', re.M | re.I)
    results = []
    for source in sources:
        for match in pattern.finditer(source['excerpt']):
            item = {'name': match[1], 'value': match[2].strip(),
                    'source': source['label'], 'date': source.get('date')}
            if item not in results:
                results.append(item)
            if len(results) >= 12:
                return results
    return results


def register_assistant(app, store, auth):
    with store.db() as db:
        db.execute('CREATE TABLE IF NOT EXISTS assistant_threads(user_id TEXT NOT NULL REFERENCES users(id), id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(user_id,id))')
        db.execute('CREATE TABLE IF NOT EXISTS assistant_migrations(user_id TEXT PRIMARY KEY REFERENCES users(id))')
    # Fixed lock pool avoids unbounded memory and prevents lost writes to SQLite.
    locks = [threading.Lock() for _ in range(64)]

    def read(uid, thread):
        with store.db() as db:
            row = db.execute('SELECT payload FROM assistant_threads WHERE user_id=? AND id=?', (uid, thread)).fetchone()
        if not row:
            raise HTTPException(404, 'Conversation not found.')
        return store.decrypt(row['payload'])

    def write(uid, thread):
        with store.db() as db:
            db.execute('INSERT OR REPLACE INTO assistant_threads VALUES (?,?,?)',
                       (uid, thread['id'], store.encrypt(thread)))

    @app.get('/api/assistant/threads')
    def list_threads(user=Depends(auth)):
        uid = user['id']
        with store.db() as db:
            if db.execute('INSERT OR IGNORE INTO assistant_migrations VALUES (?)', (uid,)).rowcount:
                if db.execute("SELECT 1 FROM sqlite_master WHERE name='report_chats'").fetchone():
                    legacy = db.execute('SELECT payload FROM report_chats WHERE user_id=?', (uid,)).fetchone()
                    if legacy and (turns := store.decrypt(legacy['payload'])):
                        thread = dict(id=uuid4().hex, title='Previous report chat', turns=turns, updated=now())
                        db.execute('INSERT INTO assistant_threads VALUES (?,?,?)', (uid, thread['id'], store.encrypt(thread)))
                        db.execute('DELETE FROM report_chats WHERE user_id=?', (uid,))
            rows = db.execute('SELECT payload FROM assistant_threads WHERE user_id=?', (uid,)).fetchall()
        threads = [store.decrypt(r['payload']) for r in rows]
        threads.sort(key=lambda t: t['updated'], reverse=True)
        return {'threads': [{k: t[k] for k in ('id','title','updated')} for t in threads],
                'configured': True}

    @app.get('/api/assistant/threads/{thread}')
    def detail(thread: str, user=Depends(auth)):
        return read(user['id'], thread)

    @app.delete('/api/assistant/threads/{thread}')
    def delete(thread: str, user=Depends(auth)):
        uid = user['id']
        lock = locks[hash(uid) % len(locks)]
        if not lock.acquire(False):
            raise HTTPException(409, 'Wait for the current reply before deleting.')
        try:
            with store.db() as db:
                if not db.execute('DELETE FROM assistant_threads WHERE user_id=? AND id=?', (uid, thread)).rowcount:
                    raise HTTPException(404, 'Conversation not found.')
            return {'deleted': True}
        finally:
            lock.release()

    @app.post('/api/assistant/threads/{thread}')
    def ask(thread: str, body: Ask, user=Depends(auth)):
        if not body.consent or not body.question.strip():
            raise HTTPException(422, 'Enter a message and allow AI processing first.')
        if body.division not in ('', *DIVISIONS):
            raise HTTPException(422, 'Unknown division.')
        uid = user['id']
        lock = locks[hash(uid) % len(locks)]
        if not lock.acquire(False):
            raise HTTPException(429, 'A reply is already in progress. Try again shortly.')
        try:
            if thread == 'new':
                # Derive an id from the first request so retries cannot create duplicate threads.
                from hashlib import sha256
                thread = sha256(f'{uid}:{body.request_id}'.encode()).hexdigest()[:32]
                try:
                    data = read(uid, thread)
                except HTTPException as exc:
                    if exc.status_code != 404:
                        raise
                    data = dict(id=thread, title=body.question.strip()[:60], turns=[])
            else:
                data = read(uid, thread)
            turns = data['turns']
            signature = body.model_dump()
            prior = next((t for t in turns if t['request_id'] == body.request_id), None)
            if prior:
                if {**(prior.get('request') or {}), 'summarize_statistics': (prior.get('request') or {}).get('summarize_statistics', False)} != signature:
                    raise HTTPException(409, 'Request ID already used.')
                return data
            language = report_chat.reply_language(body.question, body.language)
            bn = language == 'bn'

            def finish(answer, triage=None, sources=None, health=None, directory_specialty=""):
                sources, health = sources or [], health or []
                doctors = []
                if triage and (triage['level'] == 'routine' or (triage['level'] == 'clarify' and directory_specialty)):
                    if directory_specialty:
                        doctors = find_doctors(DATA, [directory_specialty], body.division)
                    else:
                        doctors = rank_doctors(triage['departments'], body.division, DATA)
                        if not doctors:
                            doctors = find_doctors(DATA, department_labels(triage['departments']), body.division)
                turns.append(dict(request_id=body.request_id, question=body.question,
                                  answer=answer, sources=[{k:v for k,v in r.items() if k!='excerpt'} for r in sources],
                                  health=health, findings=findings(sources), report_details=sources, doctors=doctors, triage=triage,
                                  # Med.ai explicit doctor cards for routine triage
                                  specialty=primary_label(doctors, (triage or {}).get('departments', []), directory_specialty) if doctors else directory_specialty,
                                  referral_status=(triage or {}).get('level'),
                                  language=language, division=body.division, created=now(), request=signature))
                data['updated'] = now()
                if len(turns) == 1:
                    with store.db() as db:
                        if db.execute('SELECT count(*) FROM assistant_threads WHERE user_id=?',(uid,)).fetchone()[0] >= 200:
                            if triage and triage['level'] == 'emergency':
                                return data  # Never suppress urgent instructions on a storage limit.
                            raise HTTPException(409, 'Delete an old chat before creating another.')
                write(uid, data)
                return data

            urgent, known = scan(body.question, bn)
            previous = (turns[-1].get('triage') or {}) if turns else {}
            if previous.get('level') == 'emergency' and not previous.get('screen_confirmed'):
                # Old model-only classifications must not lock a thread into
                # emergency mode when no positive warning sign was reported.
                previous = scan(turns[-1]['question'], bn)[0] or {}
            if urgent:
                return finish('', urgent)
            if len(turns) >= 200:
                raise HTTPException(409, 'This conversation is full. Start a new chat.')
            if sum(t['created'] > now()-60 for t in turns) >= 6:
                raise HTTPException(429, 'Please wait a minute before sending more messages.')
            # Doctor navigation uses the local symptom screen and real directory;
            # glossary/record prose must never be parsed as clinical JSON.
            result = navigation(body.question, bn, previous)
            report_mode = body.use_records and (body.document_ids or body.summarize_statistics or present(r'report|lab result|blood test|cbc|hba1c|রিপোর্ট|রিপোর্ট|রিপোট|পরীক্ষার ফল', body.question))
            if result is not None and not report_mode:
                triage, specialty = result
                return finish('', triage, directory_specialty=specialty)

            if body.summarize_statistics and (not body.use_records or body.document_ids):
                raise HTTPException(422, 'Enable health context and use all reports for a statistics summary.')
            query = ' '.join([body.question, *(t['question'] for t in turns[-2:])])
            stats = None
            if body.summarize_statistics:
                report_chat.retrieve(store, uid, query, [])
                stats = statistics_snapshot(store, uid, analysis=True)
                if not stats['reports'] and not stats['readings']:
                    raise HTTPException(422, 'Add and sync a lab report or measurement first.')
                context = {k: stats[k] for k in ('reports', 'readings')}
                if len(json.dumps(context, ensure_ascii=False).encode()) > 42000:
                    raise HTTPException(413, 'Too many records for one summary. Try asking about selected reports.')
                sources = [dict(label=r['label'], title=r['title'], document_id=r['document_id'],
                                date=r['date'], excerpt=r['ocr_excerpt']) for r in stats['reports']]
                health = []
            else:
                sources = report_chat.retrieve(store, uid, query, body.document_ids) if body.use_records else []
                health = vitals(store, uid, query) if body.use_records else []
            messages = [{'role':'system','content':SYSTEM}]
            if stats is not None:
                messages[0]['content'] += (
                    '\nProduce a structured health summary with measurement trends, lab results, data gaps '
                    'and questions for a clinician. Cite the actual report labels. The measurements '
                    'include counts, range and recent samples. Report OCR may be partial, wrong or '
                    'missing. Compare only matching indicators and units. User-entered lab values '
                    'are copied from reports but not clinician-verified. Do not invent thresholds.')
            for t in turns[-3:]:
                messages.append({'role':'user','content':t['question']})
                # Replay triage questions or urgency, without record excerpts.
                earlier_triage = t.get('triage') or {}
                if earlier_triage.get('follow_up') or earlier_triage.get('level') in ('urgent','emergency'):
                    messages.append({'role':'assistant','content':json.dumps({
                        'previous_level':earlier_triage.get('level'),
                        'previous_follow_up':earlier_triage.get('follow_up') or [],
                    }, ensure_ascii=False)})
                elif body.use_records and t['answer'].strip():
                    messages.append({'role':'assistant','content':t['answer'][:2000]})
            messages.append({'role':'user','content':json.dumps({
                'question':body.question, 'untrusted_report_excerpts':sources if stats is None else [],
                'untrusted_health_measurements':health,
                'untrusted_statistics_summary': context if stats is not None else None}, ensure_ascii=False)})
            answer = report_chat.answer_in_language(messages, language)
            if report_mode and result is not None and result[0]['level'] == 'routine' and INTENT.search(body.question):
                triage, specialty = result
                return finish(answer, triage, sources=sources, health=health, directory_specialty=specialty)
            return finish(answer, sources=sources, health=health)

        finally:
            lock.release()
