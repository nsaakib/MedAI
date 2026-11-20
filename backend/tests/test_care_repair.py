import json
import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from app.main import create_app
from app import brand_options
from app.care_navigation import navigation
from app.clinical_navigation import scan

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('MEDAI_SOS_ENABLED','0')
    with TestClient(create_app(str(tmp_path),Fernet.generate_key().decode(),ocr_enabled=False)) as c:
        yield c

def register(c, email):
    r=c.post('/api/auth/register',json={'email':email,'password':'Test-password-2026','name':'Test user'})
    assert r.status_code in (200,201),r.text
    return {'Authorization':'Bearer '+r.json()['token']}

@pytest.mark.parametrize('question,specialty',[
 ('I have a headache. Which doctor should I see?','Internal Medicine'),
 ('আমার মাথা ব্যথা কোন ডাক্তার দেখাবো','Internal Medicine'),
 ('I have itchy skin, suggest a doctor','Dermatology'),
 ('আমার চুলকানি হচ্ছে ডাক্তার সাজেস্ট করো','Dermatology'),
 ('I need a cardiologist','Cardiology'),
 ('হৃদরোগের জন্য ভালো ডাক্তার কারা আছে','Cardiology'),
 ('I have knee pain','Orthopedics'),
 ('I have a rash','Dermatology'),
 ('I have a stomach ache','Gastroenterology'),
 ('আমার পেটে ব্যথা','Gastroenterology'),
 ('I feel unwell','Internal Medicine'),
 ('I have mild nasal allergies','ENT'),
])
def test_routine_referral(question,specialty):
    result= navigation(question,False,{'level':'emergency','symptoms':[]})
    assert result and result[0]['level']=='routine'
    assert result[0]['phone'] is None
    assert result[1]==specialty

@pytest.mark.parametrize('text',[
 'I have chest pain and shortness of breath',
 'আমার তীব্র শ্বাসকষ্ট হচ্ছে',
 'I have sudden severe headache',
 'She is unconscious',
 'I have heavy bleeding',
 'Sudden one-sided weakness and slurred speech',
])
def test_positive_emergencies_preserved(text):
    assert navigation(text,False)[0]['level']=='emergency'
    assert navigation(text,False)[0]['phone']=='999'

def test_ambiguous_chest_is_not_automatic_emergency():
    result=navigation('Which doctor for chest pain?',False)
    assert result[0]['level']=='clarify'
    assert result[0]['phone'] is None

def test_same_episode_emergency_not_cleared():
    prior=navigation('I cannot breathe',False)[0]
    assert navigation('still the same, which doctor?',False,prior)[0]['level']=='emergency'

@pytest.mark.parametrize('name,strength,form',[
 ('Zopride 50mg','50 mg','Tab'),('Zopride 50','50mg','tablet'),
 ('Tab. Dizmo 50 mg','','tablet'),('Itopid','50 mg','tablet'),
 ('Telma','40 mg','tablet'),('Telmipres 80','80mg','Tab.'),
 ('Exium 40','40 mg','Cap'),('Nexum','20 mg','capsule'),
 ('Napa 500','500 mg','Tablet'),('Ace','500 mg','tablet'),
])
def test_all_supported_products(name,strength,form):
    original,choices=brand_options.options({'name':name,'strength':strength,'form':form,'verified':True},brand_options.load_catalog())
    assert original and len(choices)==4
    assert all(brand_options.formulation(x)==brand_options.formulation(original) for x in choices)

def test_entire_catalog_has_formulation_safe_alternatives():
    rows=brand_options.load_catalog()
    assert len(rows)>=50 and len({r['id'] for r in rows})==len(rows)
    for r in rows:
        original,choices=brand_options.options({**r,'verified':True},rows)
        assert original==r and len(choices)==4,r
        assert all(x['id']!=r['id'] and brand_options.formulation(x)==brand_options.formulation(r) for x in choices)

@pytest.mark.parametrize('changed',[
 {'verified':False},{'name':'Napa XR'},{'strength':'250 mg'},
 {'form':'syrup'},{'name':'Telmato'},{'instruction':'extended release'},
 {'route':'injection'},{'name':'Napa Extra'},{'name':'Napa 250mg'},
])
def test_unsupported_or_conflicting_product_never_guessed(changed):
    row={'name':'Napa','strength':'500 mg','form':'tablet','verified':True,**changed}
    assert brand_options.options(row,brand_options.load_catalog())==(None,[])

def test_doctor_api_real_directory_and_account_isolation(client):
    a=register(client,'first@example.test');b=register(client,'second@example.test')
    r=client.post('/api/assistant/threads/new',headers=a,json={'question':'হৃদরোগের জন্য ভালো ডাক্তার কারা আছে','consent':True,'language':'bn','request_id':'doctor-test-0001'})
    assert r.status_code in (200,201),r.text
    turn=r.json()['turns'][-1]
    assert turn['triage']['level']=='routine' and turn['doctors']
    assert all(d['doctor_id'] and d['hospital_name'] for d in turn['doctors'])
    assert client.get('/api/assistant/threads/'+r.json()['id'],headers=b).status_code==404

def test_preference_confirmation_account_scope_and_prescription_unchanged(client):
    a=register(client,'brand@example.test');b=register(client,'other@example.test')
    with client.app.state.store.db() as db:
        # Seed an encrypted test record through the same store used by sync.
        from app.core import token_hash
        uid=db.execute('SELECT id FROM users WHERE email_hash=?',(token_hash('brand@example.test'),)).fetchone()['id']
        medicine={'id':'med-1','name':'Zopride 50','strength':'50mg','form':'Tab','verified':True}
        state={'medicines':[medicine]}
        db.execute('UPDATE states SET payload=? WHERE user_id=?',(client.app.state.store.encrypt(state),uid))
    r=client.get('/api/medicine-brands/med-1',headers=a)
    assert r.status_code in (200,201),r.text
    chosen=r.json()['candidates'][0]['id']
    assert client.put('/api/medicine-brands/med-1',headers=a,json={'alternative_id':chosen}).status_code==422
    assert client.put('/api/medicine-brands/med-1',headers=a,json={'alternative_id':chosen,'confirmed':True}).status_code==200
    assert client.get('/api/medicine-brands/med-1',headers=b).status_code==404
    with client.app.state.store.db() as db:
        payload=db.execute('SELECT payload FROM states WHERE user_id=?',(uid,)).fetchone()['payload']
        assert client.app.state.store.decrypt(payload)['medicines'][0]==medicine

def test_disabled_dispatch_is_truthfully_refreshable(client):
    a=register(client,'sos@example.test')
    config=client.get('/api/sos/config').json()
    assert config['enabled'] is False
    assert config['mode']=='disabled'
    for _ in range(2):
        r=client.get('/api/sos/requests',headers=a)
        assert r.status_code==200 and r.json()==[]

def test_old_model_emergency_does_not_lock_ordinary_directory_request(client):
    a=register(client,'old-thread@example.test')
    first=client.post('/api/assistant/threads/new',headers=a,json={
        'question':'I have a headache. Which doctor should I see?',
        'consent':True,'language':'en','request_id':'old-thread-start'}).json()
    store=client.app.state.store
    with store.db() as db:
        row=db.execute('SELECT user_id,payload FROM assistant_threads WHERE id=?',(first['id'],)).fetchone()
        data=store.decrypt(row['payload'])
        data['turns'][-1]['triage']={'level':'emergency','reason':'old model output','phone':'999'}
        db.execute('UPDATE assistant_threads SET payload=? WHERE id=?',(store.encrypt(data),first['id']))
    reply=client.post('/api/assistant/threads/'+first['id'],headers=a,json={
        'question':'Please suggest a doctor','consent':True,'language':'en','request_id':'old-thread-followup'})
    assert reply.status_code==200,reply.text
    turn=reply.json()['turns'][-1]
    assert turn['triage']['level']=='routine' and turn['doctors']
    assert turn['triage']['phone'] is None


def test_chest_followup_reaches_directory_when_stable_history_is_explicit():
    prior=navigation('Which doctor for chest pain?',False)[0]
    result=navigation('Stable, comes and goes for months',False,prior)
    assert result[0]['level']=='routine' and result[1]=='Cardiology'
    assert result[0]['phone'] is None
