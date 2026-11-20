"""Directory queries for the existing clinical navigation flow."""
import re
import unicodedata

INTENT = re.compile(
    r'\b(?:doctor\w*|specialist\w*|cardiologist\w*|dermatologist\w*|'
    r'neurologist\w*|pulmonologist\w*|ophthalmologist\w*|endocrinologist\w*|gastroenterologist\w*|gynaecologist\w*|gynecologist\w*|urologist\w*|nephrologist\w*)\b|'
    r'ডাক্তার|চিকিৎসক|বিশেষজ্ঞ|ডক্টর', re.I)
RISK = re.compile(
    r'chest (?:pain|pressure|tightness)|shortness of breath|can.t breathe|'
    r'heart attack|stroke symptoms|বুকে\s*(?:ব্যথা|চাপ)|শ্বাসকষ্ট|স্ট্রোকের লক্ষণ', re.I)
SPECIALTIES = {
    'Gastroenterology': ('gastroenterology','gastroenterologist','gastrointestinal & liver diseases','গ্যাস্ট্রোএন্টারোলজি'),
    'Endocrinology': ('endocrinology','endocrinologist','ডায়াবেটিস বিশেষজ্ঞ','এন্ডোক্রাইনোলজি'),
    'Urology': ('urology','urologist','ইউরোলজি'),
    'Nephrology': ('nephrology','nephrologist','kidney diseases','কিডনি বিশেষজ্ঞ'),
    'Gynecology': ('gynecology','gynaecology','gynaecologist','gynecologist','gynaecology & obstetrics','obstetrics & gynecology','স্ত্রীরোগ','গাইনি'),
    'Cardiology': ('cardiology', 'cardiologist', 'heart disease', 'heart specialist', 'interventional cardiology', 'হৃদরোগ', 'হৃদ রোগ', 'কার্ডিওলজি'),
    'Neurology': ('neurology', 'neurologist', 'neuro medicine', 'স্নায়ুরোগ', 'স্নায়ুরোগ', 'নিউরোলজি'),
    'Dermatology': ('dermatology', 'dermatologist', 'dermatology venereology', 'skin specialist', 'চর্মরোগ', 'ডার্মাটোলজি'),
    'ENT': ('ent', 'otolaryngology', 'ear nose and throat', 'নাক কান গলা'),
    'Orthopedics': ('orthopedics', 'orthopaedics', 'orthopedic surgery', 'orthopaedic surgery', 'orthopedist', 'অর্থোপেডিক'),
    'Internal Medicine': ('internal medicine', 'medicine', 'general medicine', 'internist', 'মেডিসিন বিশেষজ্ঞ', 'ইন্টারনাল মেডিসিন'),
    'Respiratory Medicine': ('respiratory medicine', 'pulmonology', 'pulmonologist', 'চেস্ট বিশেষজ্ঞ', 'বক্ষব্যাধি'),
    'Ophthalmology': ('ophthalmology', 'ophthalmologist', 'eye specialist', 'চক্ষু', 'চোখের ডাক্তার'),
    'Pediatrics': ('pediatrics', 'paediatrics', 'pediatrician', 'শিশু বিশেষজ্ঞ'),
}
EXCLUDED = re.compile(r'emergency|accident|casualty', re.I)


def normalized(s):
    return ' '.join(re.sub(r'[^\w\u0980-\u09ff]+', ' ', unicodedata.normalize('NFKC', s).casefold()).split())


def direct_specialty(question):
    if not INTENT.search(question) or RISK.search(question):
        return ''
    text = normalized(question)
    found = []
    for specialty, aliases in SPECIALTIES.items():
        if any((alias in text if re.search(r'[\u0980-\u09ff]', alias)
                else f' {alias} ' in f' {text} ') for alias in aliases):
            found.append(specialty)
    return found[0] if len(found) == 1 else ''


def department_labels(departments):
    if not isinstance(departments, (list, tuple)):
        return []
    result = []
    for item in departments:
        if isinstance(item, str):
            result.append(item)
        elif isinstance(item, dict):
            for k in ('specialty', 'department', 'name', 'label', 'canonical',
                      'specialty_id', 'department_id', 'key', 'slug', 'id'):
                if isinstance(item.get(k), str):
                    result.append(item[k])
    return result


def _specialty_key(value):
    n = normalized(value.replace('_', ' '))
    for name, aliases in SPECIALTIES.items():
        if n == normalized(name) or n in aliases:
            return normalized(name)
    return n


def find_doctors(rows, specialties, division, limit=5):
    allowed = {_specialty_key(x) for x in specialties if x and not EXCLUDED.search(x)}
    found, seen = [], set()
    for row in sorted(rows, key=lambda r: (not r.get('is_verified'), str(r.get('full_name', '')).casefold())):
        if not row.get('doctor_id') or not row.get('full_name'):
            continue
        if division and normalized(str(row.get('division') or '')) != normalized(division):
            continue
        labels = str(row.get('specialties') or '').split('|')
        if not any(not EXCLUDED.search(s) and _specialty_key(s) in allowed for s in labels):
            continue
        identity = row['doctor_id']
        if identity in seen:
            continue
        seen.add(identity)
        found.append(dict(row))
        if len(found) >= limit:
            break
    return found


def primary_label(rows, departments, explicit=''):
    if explicit:
        return explicit
    options = department_labels(departments)
    for label in options:
        if label and not EXCLUDED.search(label):
            target = _specialty_key(label)
            for canonical in SPECIALTIES:
                if _specialty_key(canonical) == target:
                    return canonical
    for row in rows:
        specialty = row.get('specialties')
        if isinstance(specialty, str):
            for label in specialty.split('|'):
                if label.strip() and not EXCLUDED.search(label):
                    return label.strip()
    return ''
