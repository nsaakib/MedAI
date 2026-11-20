"""Optional AI providers format a fixed, public glossary. Patient input stays inside Med.ai."""
import json
import os
import re
from threading import Lock, Thread
from time import monotonic

import httpx


FACTS = {
    'hb': ('Hemoglobin is the oxygen-carrying protein in red blood cells.',
           'হিমোগ্লোবিন লোহিত রক্তকণিকার অক্সিজেন বহনকারী প্রোটিন।'),
    'wbc': ('A white blood cell count measures the number of white blood cells in a blood sample.',
            'শ্বেত রক্তকণিকার গণনা রক্তের নমুনায় এই কোষগুলোর সংখ্যা মাপে।'),
    'platelet': ('A platelet count measures the number of platelets, which help blood clot.',
                 'প্লেটলেটের গণনা রক্ত জমাট বাঁধতে সাহায্য করে এমন অণুচক্রিকার সংখ্যা মাপে।'),
    'hba1c': ('Hemoglobin A1c reflects average blood sugar over roughly the past two to three months.',
              'হিমোগ্লোবিন এওয়ানসি গত প্রায় দুই থেকে তিন মাসের গড় রক্তে শর্করার ধারণা দেয়।'),
    'creatinine': ('Creatinine is a waste product from muscles that is measured in blood or urine.',
                   'ক্রিয়েটিনিন পেশি থেকে উৎপন্ন একটি বর্জ্য পদার্থ, যা রক্ত বা প্রস্রাবে পরিমাপ করা হয়।'),
    'glucose': ('A glucose test measures sugar in a sample such as blood.',
                'গ্লুকোজ পরীক্ষা রক্তের মতো নমুনায় শর্করার পরিমাণ মাপে।'),
    'range': ('A reference interval is the comparison range printed by the reporting laboratory.',
              'রেফারেন্স ইন্টারভ্যাল হলো রিপোর্টে পরীক্ষাগারের দেওয়া তুলনার সীমা।'),
    'Cardiology': ('Cardiology is the specialty concerned with the heart and circulation.',
                   'কার্ডিওলজি হৃদযন্ত্র ও রক্ত সঞ্চালন নিয়ে কাজ করে।'),
    'Neurology': ('Neurology is the specialty concerned with the brain, spinal cord and nerves.',
                  'নিউরোলজি মস্তিষ্ক, মেরুরজ্জু ও স্নায়ু নিয়ে কাজ করে।'),
    'Dermatology': ('Dermatology is the specialty concerned with skin, hair and nails.',
                    'ডার্মাটোলজি ত্বক, চুল ও নখ নিয়ে কাজ করে।'),
    'ENT': ('ENT is the specialty concerned with the ear, nose and throat.',
            'ইএনটি কান, নাক ও গলা নিয়ে কাজ করে।'),
    'Orthopedics': ('Orthopedics is the specialty concerned with bones, joints and related structures.',
                    'অর্থোপেডিকস হাড়, জয়েন্ট ও সংশ্লিষ্ট অঙ্গ নিয়ে কাজ করে।'),
    'Internal Medicine': ('Internal medicine focuses on medical care for adults.',
                          'ইন্টারনাল মেডিসিন প্রাপ্তবয়স্কদের চিকিৎসা নিয়ে কাজ করে।'),
    'Respiratory Medicine': ('Respiratory medicine is the specialty concerned with the lungs and airways.',
                             'রেসপিরেটরি মেডিসিন ফুসফুস ও শ্বাসনালি নিয়ে কাজ করে।'),
    'Ophthalmology': ('Ophthalmology is the specialty concerned with the eyes and vision.',
                      'অফথ্যালমোলজি চোখ ও দৃষ্টিশক্তি নিয়ে কাজ করে।'),
    'Pediatrics': ('Pediatrics is the specialty focused on the medical care of children.',
                   'পেডিয়াট্রিকস শিশুদের চিকিৎসা নিয়ে কাজ করে।'),
}

TERMS = {
    'hb': r'\b(?:hemoglobin|haemoglobin|hb)\b|হিমোগ্লোবিন',
    'wbc': r'\b(?:wbc|white blood cells?)\b|শ্বেত রক্তকণিকা',
    'platelet': r'\bplatelets?\b|প্লেটলেট',
    'hba1c': r'\b(?:hba1c|a1c)\b|এওয়ানসি',
    'creatinine': r'\bcreatinine\b|ক্রিয়েটিনিন',
    'glucose': r'\b(?:glucose|blood sugar)\b|গ্লুকোজ',
    'range': r'\breference (?:range|interval)\b|রেফারেন্স',
}
EDUCATION = re.compile(r'\b(?:what is|what does|meaning|define|explain|report|lab result)\b|মানে|কী|কি|রিপোর্ট', re.I)
UNSAFE = re.compile(r'\b(?:you|your|diagnos\w*|prescrib\w*|dose|dosage|should|must|take|stop|urgent|normal|abnormal|high|low|consult)\b|আপনার|তোমার|খান|নিন|উচিত|জরুরি|স্বাভাবিক|বেশি|কম', re.I)
LOCK = Lock()
_cache = {}
_until = 0
_cached_provider = None
_ollama_warmup = Lock()
LABELS = {'xai': 'Grok', 'groq': 'Groq', 'ollama': 'Ollama'}


def provider():
    value=os.getenv('MEDAI_AI_PROVIDER','').strip().lower()
    # Preserve the original xAI configuration unless an explicit mode is set.
    return value or ('xai' if os.getenv('XAI_API_KEY','').strip() else 'off')


def settings():
    name=provider()
    if name=='ollama':
        model=os.getenv('OLLAMA_MODEL','qwen2.5:1.5b').strip()
        # Reject Cloud model tags and URL-like model names.
        if re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:-]{0,99}',model) and 'cloud' not in model.lower():
            return name,model,''
    elif name=='groq':
        model=os.getenv('GROQ_MODEL','openai/gpt-oss-20b').strip()
        key=os.getenv('GROQ_API_KEY','').strip()
        if key and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:/-]{0,99}',model):
            return name,model,key
    elif name=='xai':
        model=os.getenv('XAI_MODEL','').strip()
        key=os.getenv('XAI_API_KEY','').strip()
        if key and re.fullmatch(r'grok-[A-Za-z0-9.-]+',model):
            return name,model,key
    return None


def configured():
    return settings() is not None


def topics(question):
    return [k for k,pattern in TERMS.items() if re.search(pattern,question,re.I)][:3]


def education_question(question):
    return bool(EDUCATION.search(question) and topics(question))


def _query(config):
    name,model,key=config
    # Never forward the selected topic, language, question, or patient record.
    fixed={k:{'en':e,'bn':b} for k,(e,b) in FACTS.items()}
    messages=[{'role':'system','content':(
        'Return a JSON object using exactly the given keys and en/bn fields. '
        'Paraphrase each supplied public definition in one plain sentence in its original language. '
        'Do not add numerical thresholds, medical advice, diagnoses, examples, or facts.')},
        {'role':'user','content':json.dumps(fixed,ensure_ascii=False)}]
    if name=='ollama':
        res=httpx.post('http://127.0.0.1:11434/api/chat',trust_env=False,
            follow_redirects=False,timeout=150,
            json={'model':model,'messages':messages,'stream':False,'format':'json',
                  'options':{'num_ctx':8192,'num_predict':3600,'temperature':0}})
        res.raise_for_status()
        return json.loads(res.json()['message']['content'])
    base='https://api.groq.com/openai/v1/chat/completions' if name=='groq' else 'https://api.x.ai/v1/chat/completions'
    params={'model':model,'messages':messages,'response_format':{'type':'json_object'}}
    if name=='groq':
        params['max_completion_tokens']=3500
        if model.startswith('openai/gpt-oss-'):
            params['reasoning_effort']='low'
    else:
        params['max_tokens']=3000
    res=httpx.post(base,follow_redirects=False,timeout=12,
                   headers={'Authorization':'Bearer '+key},json=params)
    res.raise_for_status()
    return json.loads(res.json()['choices'][0]['message']['content'])


def _public_glossary():
    global _cache,_until,_cached_provider
    config=settings()
    if not config:
        return {}
    selected=config[:2]
    if _cached_provider==selected and monotonic() < _until:
        return _cache
    if not LOCK.acquire(blocking=False):
        return _cache if _cached_provider==selected else {}
    try:
        if _cached_provider==selected and monotonic() < _until:
            return _cache
        if _cached_provider!=selected:
            _cache={}
            _cached_provider=selected
        _until=monotonic()+300
        try:
            data=_query(config)
            if not isinstance(data,dict): return _cache
            safe={}
            for k in FACTS:
                pair=data.get(k)
                if not isinstance(pair,dict): continue
                for lang,txt in pair.items():
                    if lang not in ('en','bn') or not isinstance(txt,str): continue
                    if (len(txt)<=165 and len(txt)>=12 and not UNSAFE.search(txt)
                        and not re.search(r'\d|[\n<>:;!%]|https?://',txt)
                        and len(re.findall(r'[.!?।]',txt))<=1
                        and (lang=='bn')==bool(re.search(r'[\u0980-\u09ff]',txt))):
                        safe[k,lang]=txt.strip()
            _cache=safe
            _until=monotonic()+(604800 if safe else 300)
        except (httpx.HTTPError,ValueError,IndexError,KeyError,TypeError):
            pass
        return _cache
    finally:
        LOCK.release()


def _warm_ollama():
    try:
        _public_glossary()
    finally:
        _ollama_warmup.release()


def note(key, language):
    if key not in FACTS: return ''
    config=settings()
    if not config:
        return FACTS[key][language=='bn']
    if config[0]=='ollama':
        # Local CPUs can take a while. Don't block a patient-facing request.
        same=_cached_provider==config[:2]
        if (not same or monotonic() >= _until) and _ollama_warmup.acquire(blocking=False):
            Thread(target=_warm_ollama,daemon=True).start()
        glossary=_cache if same else {}
    else:
        glossary=_public_glossary()
    value=glossary.get((key,language))
    if value:
        return LABELS[config[0]] + (' glossary: ' if language=='en' else ' শব্দার্থ: ') + value
    return FACTS[key][language=='bn']


if __name__ == '__main__':
    from .manage import load_env
    load_env()
    config=settings()
    if not config:
        raise SystemExit('Select MEDAI_AI_PROVIDER and set the required model or API key on the Med.ai backend.')
    label=LABELS[config[0]]
    result=_public_glossary()
    if not result:
        raise SystemExit(f'{label} glossary check failed. Check that the model is available and the service is reachable.')
    print(f'{label} glossary verified: {len(result)} approved public definitions. No patient data was sent.')
