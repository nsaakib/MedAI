import base64
import io
import json
import pytest
import httpx
from PIL import Image
from fastapi.testclient import TestClient
from cryptography.fernet import Fernet
from app.main import create_app
from app import report_rag, report_chat
from app.core import token_hash, now

@pytest.fixture
def setup(tmp_path,monkeypatch):
 monkeypatch.setenv('MEDAI_REPORT_PROVIDER','groq');monkeypatch.setenv('GROQ_API_KEY','test-only-not-a-real-key')
 monkeypatch.setenv('MEDAI_AI_PROVIDER','groq');monkeypatch.setenv('MEDAI_SOS_ENABLED','0')
 app=create_app(str(tmp_path),Fernet.generate_key().decode())
 with TestClient(app) as c:
  def user(email):
   r=c.post('/api/auth/register',json={'email':email,'name':'Synthetic test','password':'Synthetic-password-2026'})
   assert r.status_code==201,r.text
   return r.json()['user_id'],{'Authorization':'Bearer '+r.json()['token']}
  a,ha=user('report-a@example.test');b,hb=user('report-b@example.test')
  yield c,app.state.store,a,ha,b,hb

def report(store,owner,id,text,*,image=False,date='2026-11-01'):
 meta={'id':id,'kind':'Lab Report','report_title':'Synthetic CBC','report_type':'cbc','report_date':date,'created':now(),'ocr_text':text,'language':'eng'}
 with store.db() as db:db.execute('INSERT INTO documents VALUES(?,?,?,?)',(id,owner,store.encrypt(meta),now()))
 if image:
  f=io.BytesIO();Image.new('RGB',(300,200),'white').save(f,format='JPEG')
  (store.files/id).write_bytes(store.cipher.encrypt(f.getvalue()))
 return meta

def response(content,**kwargs):
 return httpx.Response(200,json={'choices':[{'message':{'content':content}}]},request=httpx.Request('POST',report_rag.GROQ_URL))

def ask(c,h,ids,question='Explain my CBC report in detail',route='/api/report-chat',**kw):
 body={'question':question,'document_ids':ids,'consent':True,'language':'auto','request_id':'synthetic-rag-0001',**kw}
 return c.post(route,headers=h,json=body)


def test_actual_report_details_reach_model_and_ui(setup,monkeypatch):
 c,s,a,h,b,hb=setup
 text='Complete blood count\n'+('Report observation line\n'*35)+'Hemoglobin 10.2 g/dL Reference 12.0-16.0\nWBC 7000 cells/uL Reference 4000-11000'
 report(s,a,'own',text);report(s,b,'private','OTHER_ACCOUNT_PRIVATE_SENTINEL')
 calls=[]
 def post(url,**kwargs):
  calls.append(kwargs['json']);assert url==report_rag.GROQ_URL
  serialized=json.dumps(kwargs['json'])
  assert '10.2' in serialized and '12.0-16.0' in serialized
  assert 'OTHER_ACCOUNT_PRIVATE_SENTINEL' not in serialized
  return response('Hemoglobin is 10.2 g/dL; printed reference 12.0-16.0 [R1]. Discuss the result with your clinician.')
 monkeypatch.setattr(report_rag.httpx,'post',post)
 r=ask(c,h,['own']);assert r.status_code==200,r.text
 data=r.json();assert calls and '[R1]' in data['answer']
 assert any('WBC 7000' in x['excerpt'] for x in data['report_details'])
 assert len(data['report_details'][0]['excerpt'])>550
 assert c.get('/api/report-chat',headers=hb).json()['turns']==[]


def test_foreign_report_rejected_before_provider_or_image_read(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 12 g/dL');report(s,b,'foreign','PRIVATE')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *args,**kw:pytest.fail('No provider request allowed'))
 r=ask(c,h,['own','foreign']);assert r.status_code==404


def test_image_only_report_is_read_cached_then_analyzed(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'image','',image=True)
 monkeypatch.setattr(report_rag,'tesseract_text',lambda *args:'')
 calls=[]
 def post(url,**kw):
  body=kw['json'];calls.append(body)
  if isinstance(body['messages'][0]['content'],list):
   assert body['model']=='qwen/qwen3.8-27b'
   assert body['messages'][0]['content'][1]['image_url']['url'].startswith('data:image/jpeg;base64,')
   return response(json.dumps({'text':'Complete blood count\nHemoglobin 10.2 g/dL Reference 12-16\nWBC 7000 cells/uL'}))
  assert '10.2' in json.dumps(body)
  return response('Hemoglobin 10.2 g/dL [R1]. Verify this value against the report.')
 monkeypatch.setattr(report_rag.httpx,'post',post)
 r=ask(c,h,['image']);assert r.status_code==200,r.text
 assert len(calls)==2 and '10.2' in r.json()['report_details'][0]['excerpt']
 with s.db() as db:
  meta=s.decrypt(db.execute('SELECT payload FROM documents WHERE id=?',('image',)).fetchone()['payload'])
  assert '10.2' in meta['ocr_text'] and meta['ocr_engine']=='groq-vision-report'
 r=ask(c,h,['image'],request_id='synthetic-rag-0002');assert r.status_code==200
 assert len(calls)==3  # The saved report image is not resent for every question.


def test_provider_failure_still_displays_actual_details(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL Reference 12-16\nPlatelets 210000 cells/uL')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *args,**kw:httpx.Response(429,request=httpx.Request('POST',report_rag.GROQ_URL)))
 r=ask(c,h,['own']);assert r.status_code==200,r.text
 assert '10.2' in r.json()['answer'] and 'quota' in r.json()['answer']
 assert r.json()['report_details']


def test_missing_text_is_not_fabricated(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'missing','')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *a,**kw:pytest.fail('Missing image cannot produce a model result'))
 r=ask(c,h,['missing']);assert r.status_code==200,r.text
 assert 'No readable' in r.json()['answer']
 assert r.json()['report_details'][0]['missing_text'] is True


def test_report_intent_not_intercepted_by_tiredness_doctor_route(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL Reference 12-16')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *a,**kw:response('The report lists hemoglobin 10.2 g/dL [R1].'))
 r=ask(c,h,['own'],'Explain my report; I feel tired',route='/api/assistant/threads/new',use_records=True)
 assert r.status_code==200,r.text
 turn=r.json()['turns'][-1]
 assert '10.2' in turn['answer'] and turn['report_details']
 assert turn['triage'] is None


def test_selected_comparison_includes_each_report(setup,monkeypatch):
 c,s,a,h,b,hb=setup
 report(s,a,'old','Hemoglobin 10.2 g/dL\n'+'CBC details\n'*300,date='2026-10-01')
 report(s,a,'new','Hemoglobin 11.2 g/dL',date='2026-11-01')
 rows=report_chat.retrieve(s,a,'compare hemoglobin CBC',['old','new'])
 assert {x['document_id'] for x in rows}=={'old','new'}
 assert len(rows)<=6


def test_local_ollama_generation_uses_no_groq(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL')
 monkeypatch.setenv('MEDAI_REPORT_PROVIDER','ollama')
 def post(url,**kw):
  assert url=='http://127.0.0.1:11434/api/chat'
  assert kw['trust_env'] is False
  return httpx.Response(200,json={'message':{'content':'Hemoglobin is 10.2 g/dL [R1].'}},request=httpx.Request('POST',url))
 monkeypatch.setattr(report_rag.httpx,'post',post)
 assert '10.2' in ask(c,h,['own']).json()['answer']


def test_bengali_report_keeps_values_and_full_sources(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL Reference 12-16')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *a,**kw:response('আপনার রিপোর্টে Hemoglobin 10.2 g/dL লেখা আছে [R1]। মূল রিপোর্টের সঙ্গে মিলিয়ে চিকিৎসকের সঙ্গে আলোচনা করুন।'))
 r=ask(c,h,['own'],'আমার রিপোর্টটি বিস্তারিত বুঝিয়ে বলুন')
 assert r.status_code==200 and r.json()['language']=='bn'
 assert '10.2' in r.json()['answer'] and r.json()['report_details']


def test_no_disclosure_without_existing_consent(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *a,**kw:pytest.fail('No processing without request authorization'))
 assert ask(c,h,['own'],consent=False).status_code==422


def test_late_report_value_not_cut_to_first_550_characters(setup,monkeypatch):
 c,s,a,h,b,hb=setup
 report(s,a,'long','Report header\n'+('Earlier unrelated observation\n'*250)+'\nCreatinine 1.1 mg/dL Reference 0.7-1.3')
 rows=report_chat.retrieve(s,a,'Explain creatinine',['long'])
 assert any('Creatinine 1.1' in row['excerpt'] for row in rows)
 assert all(len(row['excerpt'])<2500 for row in rows)


def test_provider_config_does_not_expose_key(setup):
 c,s,a,h,b,hb=setup
 health=c.get('/health').json()
 assert health['care_revision']=='live-docs-7'
 assert health['report_rag']['generation_configured'] is True
 assert 'test-only-not-a-real-key' not in json.dumps(health)


def test_generated_citations_cannot_reference_other_report(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *a,**kw:response('Result is 10.2 g/dL [R1]. See [R99].'))
 r=ask(c,h,['own']);assert r.status_code==200
 assert '[R99]' not in r.json()['answer'] and '[R1]' in r.json()['answer']


def test_bangla_fallback_does_not_hide_english_test_values(setup,monkeypatch):
 c,s,a,h,b,hb=setup
 monkeypatch.setenv('MEDAI_REPORT_PROVIDER','off');monkeypatch.delenv('GROQ_API_KEY')
 report(s,a,'own','Hemoglobin 10.2 g/dL\n'+('CBC result detail\n'*50))
 r=ask(c,h,['own'],'আমার রিপোর্টটি বুঝিয়ে বলুন')
 assert r.status_code==200,r.text
 assert '10.2' in r.json()['answer'] and r.json()['report_details']


def test_report_analysis_and_explicit_doctor_request_can_coexist(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL Reference 12-16')
 monkeypatch.setattr(report_rag.httpx,'post',lambda *args,**kwargs:response('Hemoglobin is 10.2 g/dL [R1]. Discuss this result at consultation.'))
 r=ask(c,h,['own'],'Explain my report and suggest a doctor',route='/api/assistant/threads/new',use_records=True)
 assert r.status_code==200,r.text
 turn=r.json()['turns'][-1]
 assert '10.2' in turn['answer'] and turn['doctors'] and turn['report_details']


def test_standalone_glossary_remains_available(monkeypatch):
 from app import grok_education
 monkeypatch.setattr(grok_education,'note',lambda topic,language:'Public glossary definition: '+topic)
 value=report_chat.answer_in_language([{'role':'system','content':''},{'role':'user','content':json.dumps({'question':'What is hemoglobin?','report_excerpts_untrusted':[]})}],'en')
 assert 'Public glossary definition' in value


def test_followup_uses_questions_but_not_old_ai_answers_as_evidence(setup,monkeypatch):
 c,s,a,h,b,hb=setup;report(s,a,'own','Hemoglobin 10.2 g/dL Reference 12-16')
 calls=[]
 def post(url,**kw):
  body=kw['json'];calls.append(body)
  if len(calls)==1:return response('OLD_ANSWER_ONLY_PLACEHOLDER [R1]')
  data=json.loads(body['messages'][-1]['content'])
  assert 'What is hemoglobin in my report?' in data['previous_questions_for_followup_only']
  assert 'OLD_ANSWER_ONLY_PLACEHOLDER' not in json.dumps(body)
  return response('The current report value remains 10.2 g/dL [R1].')
 monkeypatch.setattr(report_rag.httpx,'post',post)
 assert ask(c,h,['own'],'What is hemoglobin in my report?').status_code==200
 r=ask(c,h,['own'],'Explain this more',request_id='synthetic-followup-0002')
 assert r.status_code==200 and len(calls)==2
