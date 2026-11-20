"""Local doctor-directory navigation. Never a diagnosis or an availability claim.

Positive emergency signs are checked by clinical_navigation.scan before routing.
A public glossary provider is not a structured clinical triage provider.
"""
import re
from .clinical_navigation import scan, screening, present
from .doctor_directory_lookup import direct_specialty, INTENT

ROUTES = [
    ('Cardiology', r'blood pressure|hypertension|heart disease|রক্তচাপ|প্রেশার|হৃদরোগ'),
    ('Endocrinology', r'diabet|thyroid|ডায়াবেটিস|ডায়াবেটিস|থাইরয়েড|থাইরয়েড'),
    ('Urology', r'urinary|urination|প্রস্রাবের সমস্যা'),
    ('Gynecology', r'menstrual|period problem|মাসিকের সমস্যা'),
    ('Pediatrics', r'my child|my baby|আমার শিশু|আমার বাচ্চা'),
    ('Dermatology', r'eczema|acne|itch(?:y|ing)?|\brash\b|skin problem|skin rash|একজিমা|ব্রণ|চুলকানি|চর্মরোগ'),
    ('ENT', r'earache|ear pain|blocked nose|nasal allerg|sore throat|কানে ব্যথা|নাক বন্ধ|নাকের অ্যালার্জি|গলা ব্যথা'),
    ('Ophthalmology', r'eye strain|itchy eyes|চোখ চুলক|চোখের সমস্যা'),
    ('Orthopedics', r'knee pain|joint pain|back pain|leg pain|হাঁটু.*ব্যথা|কোমর.*ব্যথা|পায়ে ব্যথা|পায়ে ব্যথা'),
    ('Gastroenterology', r'stomach ?ache|stomach pain|abdominal pain|indigestion|heartburn|constipation|acid reflux|পেটে ব্যথা|পেট ব্যথা|বদহজম|কোষ্ঠকাঠিন্য|অম্বল'),
    ('Neurology', r'recurr(?:ent|ing) headache|migraine|মাইগ্রেন|বারবার মাথা.*ব্যথা'),
    ('Internal Medicine', r'headache|head hurts|fever|cough|cold|flu\b|body ache|fatigue|tired|unwell|অসুস্থ|মাথা.*ব্যথা|জ্বর|কাশি|শরীর ব্যথা|ক্লান্ত'),
]
CONCERN = r'sudden|severe|worst|unbearable|rapidly worsen|coughing blood|vomiting blood|vision loss|confus|pregnan|তীব্র|হঠাৎ|অসহ্য|প্রচণ্ড|রক্তবমি|দৃষ্টি হার|গর্ভ'
CONTINUING = r'\bstill\b|\bongoing\b|\bgetting worse\b|\bsame symptoms?\b|এখনও|এখনো|একই সমস্যা|বাড়ছে|বাড়ছে'


def navigation(question, bn, previous=None):
    previous = previous or {}
    urgent, known = scan(question, bn)
    if urgent:
        return urgent, ''
    specialty = direct_specialty(question)
    matches = [name for name, pattern in ROUTES if present(pattern, question)]
    chest = any(s.get('key') == 'chest_pain' for s in known)
    breathing = any(s.get('key') == 'breathlessness' for s in known)
    if chest:
        # Unresolved warning signs are not routine clearance. Directory browsing
        # can accompany the safety questions, but never replace urgent assessment.
        if previous.get('level') == 'emergency' and previous.get('screen_confirmed'):
            return previous, ''
        triage = screening(bn, known)
        triage['directory_context'] = (
            'Directory information only: Internal Medicine or Cardiology can assess chest concerns. Do not wait for an appointment if the warning signs above apply.',
            'শুধু ডাক্তার খোঁজার তথ্য: মেডিসিন বা হৃদরোগ বিশেষজ্ঞ বুকের সমস্যার মূল্যায়ন করতে পারেন। ওপরে বলা সতর্ক লক্ষণ থাকলে অ্যাপয়েন্টমেন্টের জন্য অপেক্ষা করবেন না।')[bn]
        return triage, 'Cardiology'
    if breathing or present(CONCERN, question):
        return screening(bn, known), ''
    # Only carry an unresolved emergency within the same episode, never into a
    # separately identified ordinary complaint or explicit directory topic.
    if previous.get('level') == 'emergency' and not matches and not specialty:
        if INTENT.search(question) or present(CONTINUING, question):
            return previous, ''
    if not specialty and not matches and previous.get('level') == 'clarify' and any(
            x.get('key') == 'chest_pain' for x in previous.get('symptoms', [])):
        if present(r'stable|comes and goes|follow.up|মাঝে মাঝে|ফলো.?আপ', question):
            specialty = 'Cardiology'
        else:
            triage = screening(bn, previous.get('symptoms', []))
            triage['directory_context'] = previous.get('directory_context') or ('Directory information only; do not delay urgent assessment for an appointment.', 'শুধু ডাক্তার খোঁজার তথ্য; জরুরি মূল্যায়নের বদলে অ্যাম্বয়েন্টমেন্টের জন্য অপেক্ষা করবেন না।')[bn]
            return triage, 'Cardiology'
    if not specialty and matches:
        specialty = matches[0] if len(set(matches)) == 1 else 'Internal Medicine'
    if not specialty and INTENT.search(question):
        old = previous.get('departments') or []
        specialty = old[0].get('name', '') if old and previous.get('level') == 'routine' else 'Internal Medicine'
    if not specialty:
        return None
    return {
        'level': 'routine', 'reason': '', 'symptoms': known,
        'guidance': ('A starting point for consultation is listed below. These are directory matches, not a diagnosis. Confirm appointments with the clinic.',
                     'পরামর্শের জন্য প্রাসঙ্গিক ডাক্তারদের তালিকা নিচে দেওয়া হলো। এটি রোগনির্ণয় নয়। ক্লিনিকের সঙ্গে অ্যাপয়েন্টমেন্ট নিশ্চিত করুন।')[bn],
        'departments': [{'name': specialty, 'reason': (
            'A clinician in this department can assess the concern you described.',
            'এই বিভাগের চিকিৎসক আপনার বলা সমস্যার মূল্যায়ন করতে পারেন।')[bn]}],
        'follow_up': [], 'phone': None,
    }, specialty


def routine_specialty(question):
    result = navigation(question, False)
    return result[1] if result and result[0]['level'] == 'routine' else ''
