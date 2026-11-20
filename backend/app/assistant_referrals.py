"""Resolve model referrals against Med.ai's own read-only doctor directory."""
import re
import unicodedata

ALIASES = {
    'Internal Medicine': ('Medicine', 'general medicine', 'primary care', 'general physician',
                          'internist', 'মেডিসিন বিশেষজ্ঞ', 'ইন্টারনাল মেডিসিন'),
    'Cardiology': ('cardiologist', 'Interventional Cardiology', 'কার্ডিওলজি', 'হৃদরোগ বিশেষজ্ঞ'),
    'Dermatology': ('Dermatology & Venereology', 'dermatologist', 'skin specialist', 'চর্মরোগ বিশেষজ্ঞ', 'ডার্মাটোলজি'),
    'Neurology': ('Neuro Medicine', 'neurologist', 'নিউরোলজি', 'স্নায়ুরোগ বিশেষজ্ঞ'),
    'ENT': ('otolaryngology', 'ent specialist', 'ear nose and throat', 'নাক কান গলা'),
    'Orthopedics': ('orthopaedics', 'Orthopedic Surgery', 'Orthopaedic Surgery', 'orthopedist', 'orthopaedic specialist', 'অর্থোপেডিক'),
    'Gastroenterology': ('gastroenterologist', 'গ্যাস্ট্রোএন্টারোলজি'),
    'Respiratory Medicine': ('Pulmonology', 'Chest Diseases', 'pulmonologist', 'respiratory specialist'),
}
EXCLUDED = re.compile(r'accident|emergency|casualty')
TAG = re.compile(r'\[\[\s*special(?:ty|ity|ties)\s*[:：]\s*([^\]\r\n]{1,180})\]\]', re.I)
URGENCY = re.compile(r'\[\[\s*urgency\s*[:：]\s*(emergency|urgent|routine|unclear|none)\s*\]\]', re.I)
REFERRAL = re.compile(
    r'(?im)(?:^\s*[#* _-]*\s*(?:recommended\s+(?:department|specialty)|directory specialty|'
    r'প্রস্তাবিত বিশেষজ্ঞ|বিভাগ)\s*[:：]\s*|\b(?:see|consult|visit|start with|make an appointment with)'
    r'\s+(?:(?:a|an|your|the)\s+)?)([^.\n:!?;।]{1,90})'
)
# Conservative stop signs, independently of any directory metadata or model tag.
RED_FLAGS = re.compile(
    r'\b(?:chest\s*(?:pain|pressure|tightness)|coug(?:hing|h)\s+up\s+blood|'
    r'(?:can.t|cannot|struggling to|unable to)\s+breathe|(?:severe|sudden)\s+shortness of breath|'
    r'unconscious|not waking up|unresponsive|face droop(?:ing)?|slurred speech|'
    r'(?:sudden|worst ever)\s+(?:severe\s+)?headache|'
    r'(?:severe|uncontrolled|heavy)\s+bleeding|suicid(?:e|al)|kill myself)\b|'
    r'বুকে\s*(?:ব্যথা|চাপ)|শ্বাস\s*নিতে\s*(?:পারছি না|পারছে না)|'
    r'অজ্ঞান|মুখ বেঁকে|কথা জড়িয়ে|হঠাৎ\s+(?:তীব্র\s+)?মাথাব্যথা|'
    r'প্রচুর রক্তপাত|আত্মহত্যা', re.I
)
IMMEDIATE_CARE = re.compile(
    r'(?im)^\s*(?:[#>*_\s-]*)\s*(?:'
    r'(?:please\s+)?(?:go to|seek|call|contact|get)\b[^\n]{0,100}(?:emergency|ambulance)'
    r'[^\n]{0,40}(?:\bnow\b|\bimmediately\b)|'
    r'(?:medical emergency|emergency warning|urgent medical assessment)\b|'
    r'এখনই[^\n]{0,65}(?:জরুরি বিভাগ|অ্যাম্বুলেন্স|জরুরি সেবা))'
)


def key(value):
    return ' '.join(re.sub(r'[^\w\u0980-\u09ff]+', ' ',
                           unicodedata.normalize('NFKC', value).casefold()).split())


def categories(rows):
    return sorted({s.strip() for row in rows
                   for s in str(row.get('specialties', '')).split('|')
                   if s.strip() and not EXCLUDED.search(key(s))} | {'Internal Medicine'})


def name_map(allowed):
    names = {key(name): name for name in allowed}
    for canonical, aliases in ALIASES.items():
        # Use the real directory label where it differs (e.g. Medicine).
        label = names.get(key(canonical)) or next((names[key(a)] for a in aliases if key(a) in names), None)
        if label:
            for alias in (canonical, *aliases):
                names[key(alias)] = label
    return names


def referral(answer, current_and_recent_questions, allowed):
    """Return status, canonical specialty candidates, and clean user text."""
    flags = {m.group(1).lower() for m in URGENCY.finditer(answer)}
    choices = [m.group(1) for m in TAG.finditer(answer)]
    clean = re.sub(r'(?m)^\s*\*{2,}\s*$', '', URGENCY.sub('', TAG.sub('', answer))).strip()
    if 'emergency' in flags:
        return 'emergency', [], clean
    if RED_FLAGS.search(current_and_recent_questions) or 'urgent' in flags or IMMEDIATE_CARE.search(clean):
        return 'urgent', [], clean
    if 'unclear' in flags or 'none' in flags:
        return 'none', [], clean
    aliases = name_map(allowed)
    found = []
    for choice in choices:
        for part in re.split(r'\s*[,;|/]\s*', choice):
            name = aliases.get(key(part))
            if name and name not in found:
                found.append(name)
    # Recover a missed machine tag from an explicit clinician recommendation;
    # mentions elsewhere in the health explanation are not treated as referrals.
    if not found:
        for m in REFERRAL.finditer(clean):
            fragment = key(m.group(1))
            # E.g. "a dermatologist for the recurring rash"; do not scan past the leading provider.
            for alias in sorted(aliases, key=len, reverse=True):
                if fragment == alias or fragment.startswith(alias + ' '):
                    label = aliases[alias]
                    if label not in found:
                        found.append(label)
                    break
    return ('routine' if found else 'none'), found, clean


def match(rows, specialty, division):
    lookup = name_map(categories(rows))
    target = lookup.get(key(specialty))
    if not target:
        return []
    result, seen = [], set()
    valid = [r for r in rows if r.get('doctor_id') and r.get('full_name')
             and r.get('hospital_name') and (not division or key(str(r.get('division', ''))) == key(division))]
    for row in sorted(valid, key=lambda r: (not r.get('is_verified'), str(r['full_name']).casefold(),
                                            str(r.get('hospital_name', '')))):
        id_ = (str(row['doctor_id']), str(row.get('hospital_id') or row['hospital_name']))
        matched = any(lookup.get(key(raw)) == target for raw in str(row.get('specialties', '')).split('|'))
        if not matched or id_ in seen:
            continue
        seen.add(id_)
        result.append({k: row.get(k) for k in ('doctor_id','hospital_id','full_name','specialties',
                                              'hospital_name','division','source_url')})
        if len(result) == 5:
            break
    return result


def installed_directory():
    import json
    from pathlib import Path
    return json.loads(Path(__file__).with_name('assistant_current_directory.json').read_text(encoding='utf-8'))


def extend_prompt(prompt, rows):
    if not isinstance(prompt, str):
        return prompt
    return prompt + (
        '\nFollow the existing clinical safety and escalation instructions first. '
        'When those instructions permit a routine directory referral, include a final plain '
        '[[specialty:EXACT DIRECTORY LABEL]] line. Do not add a routine referral for urgent '
        'or emergency symptoms, and do not invent clinician names. Directory labels: '
        + ', '.join(categories(rows))
    )


def _recorded_urgency(turn):
    """Honor existing custom triage fields; never downgrade their decision."""
    severity = {'emergency': 2, 'urgent': 1}
    found = ''
    for context in (turn, turn.get('triage'), turn.get('triage_result')):
        if not isinstance(context, dict):
            continue
        for flag, status in (('is_emergency', 'emergency'), ('emergency', 'emergency'),
                             ('requires_immediate_care', 'emergency'), ('is_urgent', 'urgent'),
                             ('urgent', 'urgent')):
            if context.get(flag) is True and severity[status] > severity.get(found, 0):
                found = status
        for field in ('urgency', 'urgency_level', 'triage_level', 'triage_status', 'referral_status', 'level', 'acuity', 'disposition'):
            value = context.get(field)
            if not isinstance(value, str):
                continue
            normalized = key(value)
            status = ('emergency' if normalized in ('emergency', 'emergent', 'immediate', 'critical', 'er', 'ed')
                      else 'urgent' if normalized in ('urgent', 'very urgent', 'same day', 'high risk') else '')
            if severity.get(status, 0) > severity.get(found, 0):
                found = status
    return found


def connect_turn(turn, rows, *, raw=None):
    if not isinstance(turn, dict) or not isinstance(turn.get('answer'), str):
        return turn
    result = dict(turn)
    answer = turn['answer']
    question = str(turn.get('question') or '')
    allowed = categories(rows)
    status, choices, clean = referral(answer, question, allowed)
    raw_status, raw_choices, _ = referral(raw, question, allowed) if isinstance(raw, str) and raw != answer else ('none', [], '')
    recorded = _recorded_urgency(turn)
    ranks = {'emergency': 2, 'urgent': 1}
    urgent = max((recorded, status, raw_status), key=lambda item: ranks.get(item, 0))
    if urgent in ranks:
        result.update(doctors=[], specialty='', referral_status=urgent, answer=clean or answer)
        return result
    if (turn.get('referral_status') in ('unclear', 'none') or
        any(m.group(1).lower() in ('unclear', 'none')
            for text in (answer, raw) if isinstance(text, str) for m in URGENCY.finditer(text))):
        result.update(doctors=[], specialty='', referral_status='none', answer=clean or answer)
        return result
    current = name_map(allowed).get(key(str(turn.get('specialty') or '')))
    candidates = list(dict.fromkeys(([current] if current else []) + choices + raw_choices))
    # Keep the local answer, triage metadata, statistics, and other turn fields.
    division = str(turn.get('division') or '')
    for choice in candidates:
        matches = match(rows, choice, division)
        if matches:
            result.update(doctors=matches, specialty=choice, referral_status='routine', answer=clean or answer)
            return result
    if candidates:
        result.update(doctors=[], specialty=candidates[0], referral_status='routine', answer=clean or answer)
    elif clean and clean != answer:
        result['answer'] = clean
    return result
