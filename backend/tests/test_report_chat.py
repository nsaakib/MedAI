import pytest
import httpx
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from app.main import create_app
from app import report_chat
from test_api import register


def seed(store, owner, identifier, text):
    report = {'id':identifier, 'kind':'Lab Report', 'created':100,
              'ocr_text':text, 'report_type':'cbc', 'report_title':'Blood count',
              'report_date':'2026-11-12'}
    with store.db() as db:
        db.execute('INSERT INTO documents VALUES(?,?,?,?)',
                   (identifier, owner, store.encrypt(report), 100))


def body(**extra):
    return {'question':'Explain my blood count', 'request_id':'request-0001', 'consent':True, **extra}


def test_scope_persistence_consent_and_idempotency(tmp_path, monkeypatch):
    key = Fernet.generate_key()
    calls = []
    def generate(messages):
        calls.append(messages)
        assert 'SECRET-OTHER-PATIENT' not in str(messages)
        assert 'Hemoglobin 12' in str(messages)
        return 'Your report lists hemoglobin 12 [R1]. Verify OCR against the original.'
    monkeypatch.setattr(report_chat, 'generate', generate)
    with TestClient(create_app(tmp_path, key, False)) as c:
        headers, user = register(c)
        stranger, other = register(c, 'other@example.com')
        store = c.app.state.store
        # Authentication response exposes state user_id; resolve directly from DB.
        with store.db() as db:
            owners = [r['id'] for r in db.execute('SELECT id FROM users ORDER BY rowid')]
        seed(store, owners[0], 'own-report', 'CBC\nHemoglobin 12 g/dL')
        seed(store, owners[1], 'other-report', 'SECRET-OTHER-PATIENT')
        assert c.post('/api/report-chat', json=body()).status_code == 401
        assert c.post('/api/report-chat', headers=headers, json=body(consent=False)).status_code == 422
        assert c.post('/api/report-chat', headers=headers, json=body(document_ids=['other-report'])).status_code == 404
        first = c.post('/api/report-chat', headers=headers, json=body())
        assert first.status_code == 200, first.text
        assert first.json()['sources'][0]['document_id'] == 'own-report'
        assert c.post('/api/report-chat', headers=headers, json=body()).json() == first.json()
        assert len(calls) == 1
        assert c.post('/api/report-chat', headers=headers, json=body(question='Different')).status_code == 409
        assert c.get('/api/report-chat', headers=stranger).json()['turns'] == []
        with store.db() as db:
            raw = db.execute('SELECT payload FROM report_chats').fetchone()['payload']
            assert b'hemoglobin' not in raw
    with TestClient(create_app(tmp_path, key, False)) as c:
        assert len(c.get('/api/report-chat', headers=headers).json()['turns']) == 1
        assert c.delete('/api/report-chat', headers=stranger).status_code == 200
        assert len(c.get('/api/report-chat', headers=headers).json()['turns']) == 1
        assert c.delete('/api/report-chat', headers=headers).status_code == 200
        assert c.get('/api/report-chat', headers=headers).json()['turns'] == []
        assert len(c.get('/api/documents', headers=headers).json()) == 1


def test_missing_configuration_and_no_fake_reply(tmp_path, monkeypatch):
    monkeypatch.delenv('GROQ_API_KEY', raising=False)
    with TestClient(create_app(tmp_path, Fernet.generate_key(), False)) as c:
        h, _ = register(c)
        assert not c.get('/api/report-chat', headers=h).json()['configured']
        assert c.post('/api/report-chat', headers=h, json=body()).status_code == 503
        assert c.get('/api/report-chat', headers=h).json()['turns'] == []


@pytest.mark.parametrize('status,expected', [(429,429),(401,503),(500,502)])
def test_provider_error_does_not_expose_payload(monkeypatch, status, expected):
    monkeypatch.setenv('GROQ_API_KEY', 'secret-test-key')
    monkeypatch.setattr(httpx, 'post', lambda *a, **kw: httpx.Response(status, text='secret-test-key'))
    with pytest.raises(report_chat.HTTPException) as error:
        report_chat.generate([])
    assert error.value.status_code == expected
    assert 'secret-test-key' not in error.value.detail


def test_provider_timeout_and_malformed(monkeypatch):
    monkeypatch.setenv('GROQ_API_KEY', 'test-key')
    def timeout(*a, **kw):
        raise httpx.ReadTimeout('private')
    monkeypatch.setattr(httpx, 'post', timeout)
    with pytest.raises(report_chat.HTTPException) as e:
        report_chat.generate([])
    assert e.value.status_code == 504
    monkeypatch.setattr(httpx, 'post', lambda *a, **kw: httpx.Response(200, json={'choices':[]}))
    with pytest.raises(report_chat.HTTPException) as e:
        report_chat.generate([])
    assert e.value.status_code == 502


def test_provider_success_request_contract(monkeypatch):
    monkeypatch.setenv('GROQ_API_KEY', 'test-key')
    def provider(url, **kw):
        assert url == 'https://api.groq.com/openai/v1/chat/completions'
        assert kw['headers']['Authorization'] == 'Bearer test-key'
        assert kw['timeout'] == 20
        return httpx.Response(200, json={'choices':[{'message':{'content':'Explanation'}}]})
    monkeypatch.setattr(httpx, 'post', provider)
    assert report_chat.generate([{'role':'user','content':'Hi'}]) == 'Explanation'


@pytest.mark.parametrize('question,expected', [
    ('আমার রিপোর্ট বুঝিয়ে বলুন', 'bn'),
    ('আমার CBC ও HbA1c report বুঝিয়ে বলুন', 'bn'),
    ('amar report ta bujhiye bolun', 'bn'),
    ('Explain my report in Bengali', 'bn'),
    ('What does CBC mean?', 'en'),
    ('আমার রিপোর্ট explain in English', 'en'),
])
def test_current_message_language(question, expected):
    assert report_chat.reply_language(question) == expected


def test_explicit_language_override():
    assert report_chat.reply_language('Explain CBC', 'bn') == 'bn'
    assert report_chat.reply_language('আমার রিপোর্ট', 'en') == 'en'


def test_bangla_retry_and_failure(monkeypatch):
    replies = iter(['This is English.', 'আপনার রিপোর্টে রক্তের পরীক্ষার ফল আছে [R1]।'])
    calls = []
    def fake(messages):
        calls.append(messages)
        return next(replies)
    monkeypatch.setattr(report_chat, 'generate', fake)
    result = report_chat.answer_in_language([{'role':'system','content':'Medical report assistant'}], 'bn')
    assert 'রিপোর্টে' in result
    assert len(calls) == 2
    assert 'Bengali script' in calls[0][0]['content']
    monkeypatch.setattr(report_chat, 'generate', lambda messages: 'Only English returned')
    with pytest.raises(report_chat.HTTPException) as e:
        report_chat.answer_in_language([{'role':'system','content':'Assistant'}], 'bn')
    assert e.value.status_code == 502
