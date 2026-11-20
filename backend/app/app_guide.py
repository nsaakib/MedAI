"""Gemini writes only public app navigation guidance. No user text or data is sent."""
from functools import lru_cache
import os
import re
from typing import Literal

from fastapi import Depends, HTTPException
import httpx

TOPICS = {
    'navigation': 'The Medicine List shows the saved prescription. From a medicine card, Brand alternatives shows exact known catalog matches. A preferred brand is a separate note; it does not change the prescription or automatically order anything.',
    'sync': 'Sign in to the same Med.ai account on your other device. Keep the app online while changes sync. If Med.ai reports that two devices edited the same record, review the changes on each device before resolving the conflict.',
    'privacy': 'Your Med.ai account protects access to your synced records. App Guide does not send your questions, prescriptions, documents, location, or account information to Gemini.',
}


def configured():
    return bool(os.environ.get('GEMINI_API_KEY','').strip())


@lru_cache(maxsize=6)
def public_guide(topic, language):
    content=TOPICS[topic]
    key=os.environ.get('GEMINI_API_KEY','').strip()
    if not key:
        return {'text':content,'mode':'built_in'}
    model=os.environ.get('GEMINI_MODEL','gemini-2.5-flash')
    if not re.fullmatch(r'gemini-[a-zA-Z0-9.-]+',model):
        raise HTTPException(503,'Invalid App Guide model configuration.')
    prompt=('Rewrite these public software instructions as two short sentences in '
            + ('Bengali' if language=='bn' else 'English')
            + '. Only explain the given software steps. No health or treatment advice.\n'+content)
    try:
        response=httpx.post(f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent',
            json={'contents':[{'parts':[{'text':prompt}]}],
                  'generationConfig':{'maxOutputTokens':768,'temperature':0.1}},
            headers={'x-goog-api-key':key},timeout=15,follow_redirects=False)
        response.raise_for_status()
        parts=response.json()['candidates'][0]['content']['parts']
        answer=' '.join(p['text'] for p in parts if p.get('text') and not p.get('thought')).strip()
        if not answer or len(answer)>2000:
            raise ValueError('Invalid response')
        return {'text':answer,'mode':'gemini'}
    except (httpx.HTTPError,ValueError,KeyError,TypeError,IndexError):
        raise HTTPException(502,'App Guide is temporarily unavailable.') from None


def register_app_guide(app, auth):
    @app.get('/api/app-guide/{topic}')
    def help_topic(topic: Literal['navigation','sync','privacy'],lang: Literal['en','bn']='en',user=Depends(auth)):
        return public_guide(topic,lang)
