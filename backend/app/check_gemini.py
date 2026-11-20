"""Optional connectivity check for the Google AI Studio key. Sends synthetic text only."""
import getpass
import json
import os
import re
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError


def check(key, model):
    if not re.fullmatch(r'gemini-[a-zA-Z0-9.-]+', model):
        raise ValueError('Invalid Gemini model ID.')
    payload = {'contents':[{'parts':[{'text':'Reply with the word READY. This is a synthetic connectivity check.'}]}]}
    endpoint = f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'
    request = Request(endpoint, data=json.dumps(payload).encode(), method='POST',
                      headers={'Content-Type':'application/json','x-goog-api-key':key})
    with urlopen(request, timeout=15) as response:
        data = json.load(response)
    return any(c.get('content',{}).get('parts') for c in data.get('candidates',[]))


def main():
    key = (os.getenv('GEMINI_API_KEY') or getpass.getpass('Google AI Studio API key: ')).strip()
    if not key:
        raise SystemExit('No key supplied.')
    try:
        if not check(key, os.getenv('GEMINI_MODEL','gemini-2.5-flash')):
            raise SystemExit('Google responded without a text result.')
    except HTTPError as exc:
        raise SystemExit(f'Google returned HTTP {exc.code}. Check the key, selected model, billing and quota.') from None
    except (URLError, ValueError, OSError):
        raise SystemExit('Could not complete the Google API connectivity check.') from None
    print('Google AI Studio API check passed. No patient data was sent.')


if __name__ == '__main__':
    main()
