"""Local, conservative report metadata detection; no patient data leaves Med.ai."""

import re
from datetime import date
from pydantic import Field
from .schemas import Strict

REPORT_TYPES = {
    "cbc": ("Blood count", "Complete blood count (CBC)"),
    "hba1c": ("Blood sugar over time", "HbA1c"),
    "glucose": ("Blood sugar test", "Blood glucose"),
    "thyroid": ("Thyroid function", "Thyroid function tests"),
    "tsh": ("Thyroid blood test", "Thyroid-stimulating hormone (TSH)"),
    "lipid": ("Cholesterol and fats", "Lipid profile"),
    "kidney": ("Kidney function", "Renal function tests"),
    "creatinine": ("Kidney blood test", "Serum creatinine"),
    "electrolytes": ("Blood salts", "Serum electrolytes"),
    "liver": ("Liver function", "Liver function tests"),
    "urine": ("Urine test", "Urinalysis"),
    "stool": ("Stool test", "Stool examination"),
    "dengue": ("Dengue test", "Dengue antigen / antibody test"),
    "crp": ("Inflammation blood test", "C-reactive protein (CRP)"),
    "esr": ("Inflammation blood test", "Erythrocyte sedimentation rate (ESR)"),
    "ecg": ("Heart electrical test", "Electrocardiogram (ECG)"),
    "echo": ("Heart ultrasound", "Echocardiogram"),
    "xray": ("X-ray report", "X-ray"),
    "ultrasound": ("Ultrasound report", "Ultrasonography (USG)"),
    "ct": ("CT scan report", "Computed tomography (CT)"),
    "mri": ("MRI scan report", "Magnetic resonance imaging (MRI)"),
    "histopathology": ("Tissue examination", "Histopathology / biopsy report"),
    "multiple": ("Multiple tests", "Combined medical tests"),
    "other": ("Other report", "Other medical report"),
}
_PATTERNS = {
    "cbc": r"complete blood (?:count|picture)|full blood count|c\.?b\.?c\.?|কমপ্লিট ব্লাড কাউন্ট|পূর্ণাঙ্গ রক্ত পরীক্ষা",
    "hba1c": r"hb\s*a1c|glycated h(?:ae|e)moglobin|এইচবিএ১সি",
    "glucose": r"(?:fasting|random|post[ -]?prandial|blood|plasma) (?:blood )?(?:glucose|sugar)|fbs|rbs|ogtt|রক্তের শর্করা",
    "thyroid": r"thyroid (?:function|profile|panel)|tft|থাইরয়েড ফাংশন",
    "tsh": r"tsh|thyroid[ -]stimulating hormone",
    "lipid": r"lipid (?:profile|panel)|লিপিড প্রোফাইল",
    "kidney": r"(?:renal|kidney) (?:function|profile|panel)|rft|kft|কিডনি ফাংশন|রেনাল ফাংশন",
    "creatinine": r"(?:serum )?creatinine",
    "electrolytes": r"(?:serum )?electrolytes?",
    "liver": r"liver (?:function|profile|panel)|lft|hepatic (?:function|panel)|লিভার ফাংশন",
    "urine": r"urinalysis|urine (?:routine|r\s*/\s*e|analysis|examination|routine and microscopic)|প্রস্রাব পরীক্ষা|মূত্র পরীক্ষা",
    "stool": r"stool (?:routine|r\s*/\s*e|examination|analysis)",
    "dengue": r"dengue(?:[ -](?:ns1|antigen|antibody|igm|igg))?",
    "crp": r"(?:hs[ -]?)?crp|c[ -]reactive protein",
    "esr": r"esr|erythrocyte sedimentation rate",
    "ecg": r"ecg|ekg|electrocardiogram|electrocardiography|ইসিজি",
    "echo": r"echocardiogram|echocardiography|echo(?:cardiographic)? report|2d echo|ইকোকার্ডিওগ্রাম",
    "xray": r"x[ -]?ray(?: of)?|skiagram|এক্স[ -]?রে",
    "ultrasound": r"ultrasonography|ultrasound|usg(?: of)?|আল্ট্রাসনোগ্রাম",
    "ct": r"(?:contrast[ -]enhanced |non[ -]contrast )?ct(?: scan| of| brain| chest| abdomen)?|computed tomography|সিটি স্ক্যান",
    "mri": r"mri|magnetic resonance imaging|এমআরআই",
    "histopathology": r"histopatholog(?:y|ical)|biopsy (?:report|examination)",
}
DETECTION_VERSION = 1


def _heading(line, pattern):
    # Only headings / result rows, never a history or a recommendation in prose.
    line = re.sub(r"^\s*(?:test(?: name)?|investigation(?:s)?|name of (?:test|examination)|examination|procedure|পরীক্ষার নাম)\s*[:：-]\s*", "", line, flags=re.I)
    return bool(re.match(rf"^(?:{pattern})(?=$|[\W_])", line, re.I))


class ReportEdit(Strict):
    report_type: str | None = Field(max_length=20)
    requested_by: str | None = Field(max_length=100)
    report_date: date | None


def report_fields(code, doctor, day, reviewed=False):
    title, test = REPORT_TYPES.get(code, ("Medical report", None))
    return dict(report_type=code, report_title=title, test_name=test,
                requested_by=doctor, report_date=day,
                report_reviewed=reviewed)


def detect_report(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    matches = {code for code, pattern in _PATTERNS.items()
               if any(_heading(line, pattern) for line in lines)}
    # A missing panel heading can still be identified from several actual result rows.
    panels = {
        'cbc': (3, [r'h(?:ae|e)moglobin|hb', r'wbc|white blood cell|total (?:wbc|leucocyte)',
                    r'rbc|red blood cell', r'platelets?(?: count)?', r'h(?:ae|e)matocrit|hct|pcv', r'mcv']),
        'lipid': (3, [r'(?:total )?cholesterol', r'triglycerides?', r'hdl(?:[ -]cholesterol)?', r'ldl(?:[ -]cholesterol)?']),
        'liver': (3, [r'(?:total )?bilirubin', r'alt|sgpt', r'ast|sgot', r'alkaline phosphatase|alp', r'(?:serum )?albumin']),
    }
    for code, (minimum, markers) in panels.items():
        if sum(any(_heading(line, marker) and re.search(r'\d', line) for line in lines)
               for marker in markers) >= minimum:
            matches.add(code)
    if 'thyroid' in matches:
        matches.discard('tsh')
    if 'kidney' in matches:
        matches -= {'creatinine', 'electrolytes'}
    doctor = None
    doctors = set()
    dates = set()
    for line in lines:
        match = re.fullmatch(
            r"(?:requested by|referred by|referring doctor|ordering provider)\s*[:：]\s*(.{2,100})",
            line, re.I,
        )
        if match and any(c.isalpha() for c in match[1]):
            doctors.add(match[1].strip())
        match = re.fullmatch(r"(?:report date|reported on)\s*[:：]\s*(\d{4}-\d\d-\d\d)", line, re.I)
        if match:
            try:
                dates.add(date.fromisoformat(match[1]).isoformat())
            except ValueError:
                pass
    if len(doctors) == 1:
        doctor = next(iter(doctors))
    codes = sorted(matches)
    code = codes[0] if len(codes) == 1 else 'multiple' if codes else None
    detected = report_fields(code, doctor, next(iter(dates)) if len(dates) == 1 else None)
    if len(codes) > 1:
        detected['test_name'] = '; '.join(REPORT_TYPES[c][1] for c in codes)
    detected.update(report_detected_types=codes,
                    report_detection_status='identified' if codes else 'unrecognized',
                    report_detection_version=DETECTION_VERSION if (text or "").strip() else 0)
    return detected


def with_report_details(metadata):
    if metadata.get('kind') != 'Lab Report' or metadata.get('report_reviewed') is True:
        return metadata
    detected = detect_report(metadata.get('ocr_text') or metadata.get('statistics_ocr_text') or '')
    # Do not erase existing labels when no image text has been read yet.
    if not detected['report_type'] and metadata.get('report_type'):
        return metadata
    for key in ('requested_by', 'report_date'):
        detected[key] = metadata.get(key) or detected[key]
    return {**metadata, **detected}
