import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
from app.main import create_app

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('MEDAI_SOS_ENABLED','0')
    with TestClient(create_app(str(tmp_path),Fernet.generate_key().decode())) as c:
        yield c

def headers(c):
    r=c.post('/api/auth/register',json={'email':'followup@example.test','password':'Test-password-2026','name':'Test user'})
    assert r.status_code==201,r.text
    return {'Authorization':'Bearer '+r.json()['token']}

@pytest.mark.parametrize('question,level,language',[
 ('আমার বুকে ব্যথার জন্য কোন ডাক্তার দেখালে ভালো হবে','clarify','bn'),
 ('Which doctor should I consult for chest pain?','clarify','en'),
 ('amar buke beytha','clarify','bn'),
 ('amar buke betha','clarify','bn'),
 ('amar buke byatha','clarify','bn'),
 ('ধর আমার বুকে ব্যথা হইতেছে তো এখন কোন ডাক্তার দেখালে ভালো হবে','clarify','bn'),
 ('amar buke beytha and shortness of breath','emergency','bn'),
 ('amar buke beytha and sweating','emergency','bn'),
 ('I have chest pain and shortness of breath','emergency','en'),
 ('আমার তীব্র শ্বাসকষ্ট হচ্ছে','emergency','bn'),
])
def test_directory_and_safety(client,question,level,language):
    r=client.post('/api/assistant/threads/new',headers=headers(client),json={
        'question':question,'consent':True,'language':'auto','request_id':'followup-directory-0001'})
    assert r.status_code==200,r.text
    turn=r.json()['turns'][-1]
    assert turn['triage']['level']==level
    assert turn['language']==language
    if level=='clarify':
        assert turn['triage']['phone'] is None
        assert turn['triage']['follow_up'] and turn['triage']['directory_context']
        assert turn['doctors'] and all(d['doctor_id'] for d in turn['doctors'])
    else:
        assert turn['triage']['phone']=='999' and not turn['doctors']


def test_trusted_proxy_only(tmp_path,monkeypatch):
    monkeypatch.setenv('MEDAI_SOS_PUBLIC_BASE_URL','https://sakib.taile6993e.ts.net')
    app=create_app(str(tmp_path),Fernet.generate_key().decode())
    wrapped=ProxyHeadersMiddleware(app,trusted_hosts=['127.0.0.1'])
    with TestClient(wrapped,client=('127.0.0.1',50000)) as c:
        assert c.get('/api/sos/config',headers={'X-Forwarded-Proto':'https'}).status_code==200
        assert c.get('/api/sos/config').status_code==403
    with TestClient(wrapped,client=('198.51.100.20',50000)) as c:
        assert c.get('/api/sos/config',headers={'X-Forwarded-Proto':'https'}).status_code==403


def test_sandbox_https_origin(tmp_path,monkeypatch):
    monkeypatch.setenv('MEDAI_SOS_PUBLIC_BASE_URL','https://sakib.taile6993e.ts.net')
    app=create_app(str(tmp_path),Fernet.generate_key().decode(),sos_sandbox=True)
    wrapped=ProxyHeadersMiddleware(app,trusted_hosts=['127.0.0.1'])
    with TestClient(wrapped,base_url='http://sakib.taile6993e.ts.net',client=('127.0.0.1',50000)) as c:
        assert c.get('/api/sos/config').status_code==403
        good=c.get('/api/sos/config',headers={'X-Forwarded-Proto':'https'})
        assert good.status_code==200 and good.json()['mode']=='sandbox'
        assert c.get('/api/sos/config',headers={'X-Forwarded-Proto':'https','Host':'untrusted.example'}).status_code==403


def test_dispatch_assignment_tracking_through_https_proxy(tmp_path,monkeypatch):
    from test_dispatch_regression import partner,account,request,reserve
    monkeypatch.setenv('MEDAI_SOS_PUBLIC_BASE_URL','https://sakib.taile6993e.ts.net')
    app=create_app(str(tmp_path),Fernet.generate_key().decode(),sos_sandbox=True)
    wrapped=ProxyHeadersMiddleware(app,trusted_hosts=['127.0.0.1'])
    with TestClient(wrapped,base_url='http://sakib.taile6993e.ts.net',client=('127.0.0.1',50000),headers={'X-Forwarded-Proto':'https'}) as c:
        p=partner(c,'proxy-partner')
        patient=account(c,'proxy-patient')
        pending=request(c,patient,'https-full-flow-0001')
        assert pending['status']=='queued'
        held=reserve(c,p,pending).json()
        assert held['status']=='awaiting_driver'
        job=p[3]+'/'+held['assignment']['id']
        assert c.post(job,headers=p[1],json={'action':'accept'}).json()['status']=='dispatched'
        location={'lat':23.781,'lng':90.401,'accuracy':10}
        assert c.post(job+'/location',headers=p[1],json=location).status_code==204
        visible=c.get('/api/sos/requests',headers=patient).json()[0]
        assert visible['assignment']['location']['lat']==location['lat']
        assert c.post(job,headers=p[1],json={'action':'en_route'}).json()['status']=='en_route'
        assert c.post(job,headers=p[1],json={'action':'arrived'}).json()['status']=='arrived'
        assert c.post(job,headers=p[1],json={'action':'complete'}).json()['status']=='completed'
        assert c.get('/api/sos/requests',headers=patient).json()[0]['status']=='completed'


def test_prescription_extraction_and_failure_preserve_photo(client):
    import io
    from PIL import Image
    auth=headers(client)
    photo=io.BytesIO();Image.new('RGB',(100,100),'white').save(photo,format='JPEG')
    upload=client.post('/api/documents',headers=auth,data={
        'client_id':'followup-prescription','kind':'Prescription','language':'eng'},
        files={'file':('test.jpg',photo.getvalue(),'image/jpeg')})
    assert upload.status_code==201,upload.text
    document_id=upload.json()['id']
    # A deterministic adapter contract test; not a recognition-accuracy test.
    client.app.state.scan_prescription_page=lambda _: {'fields':[
        {'field':'medicine','status':'draft','text':'Test medicine'},
        {'field':'frequency','status':'draft','text':'1+1+1'}]}
    result=client.post(f'/api/documents/{document_id}/extract',headers=auth)
    assert result.status_code==200,result.text
    assert result.json()['review_required'] is True
    assert result.json()['candidates'][0]['name']=='Test medicine'
    assert result.json()['candidates'][0]['frequency']==''  # No guessed box association.
    def failed(_):raise RuntimeError('test model failure')
    client.app.state.scan_prescription_page=failed
    result=client.post(f'/api/documents/{document_id}/extract',headers=auth)
    assert result.status_code==503 and 'CHECK_OCR' in result.json()['detail']
    assert client.get(f'/api/documents/{document_id}',headers=auth).status_code==200


def test_no_stuck_chest_directory_on_followup(client):
    auth=headers(client)
    r=client.post('/api/assistant/threads/new',headers=auth,json={
        'question':'Which doctor for chest pain?','consent':True,'language':'en','request_id':'chest-start-002'})
    thread=r.json()['id']
    for i,question in enumerate(['Please suggest a doctor','I have itchy skin']):
        r=client.post('/api/assistant/threads/'+thread,headers=auth,json={
            'question':question,'consent':True,'language':'en','request_id':'chest-followup-'+str(i)})
        assert r.status_code==200,r.text
        turn=r.json()['turns'][-1]
        assert turn['doctors']
        if i==1:assert turn['triage']['level']=='routine'
