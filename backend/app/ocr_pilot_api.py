import base64
import binascii
import io
import logging
import os
import threading
from pathlib import Path
from time import perf_counter
from typing import Literal

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

log = logging.getLogger(__name__)


class ScanRequest(BaseModel):
    image_base64: str = Field(min_length=4, max_length=8_000_000)
    mode: Literal['page', 'crop'] = 'crop'
    field: Literal['medicine', 'strength', 'dosage_form', 'frequency', 'meal',
                   'duration', 'route', 'special_instruction'] = 'frequency'


def register_ocr_pilot(app, auth):
    lock = threading.Lock()
    memo = {}
    root = Path(__file__).resolve().parents[1] / 'models'
    bn = root / 'medai_03s.pt'
    latin = root / 'trocr_03c'
    detector = root / 'detector_final.pt'

    def has_trocr():
        return (latin / 'config.json').is_file() and any(
            (latin / name).is_file() for name in ('model.safetensors', 'pytorch_model.bin',
                                                 'model.safetensors.index.json', 'pytorch_model.bin.index.json'))

    def model_status():
        return {'03s_present': bn.is_file(), '03c_present': has_trocr(),
                'detector_present': detector.is_file()}

    app.state.prescription_model_status = model_status

    @app.get('/api/ocr-pilot/status')
    def status(user=Depends(auth)):
        return model_status()

    @app.post('/api/ocr-pilot/scan')
    def scan(req: ScanRequest, user=Depends(auth)):
        return run_scan(req)

    def run_scan(req, names_only=False):
        start = perf_counter()
        if req.mode == 'page' and not detector.is_file():
            raise HTTPException(503, 'Full prescription mode needs the 03P expanded62 detector. Try a cropped field.')
        try:
            from PIL import Image, ImageOps
            from . import ocr_pilot_runtime as rt
        except ImportError:
            raise HTTPException(503, 'Install the OCR backend dependencies.') from None

        try:
            raw = base64.b64decode(req.image_base64, validate=True)
            with Image.open(io.BytesIO(raw)) as image:
                if image.format not in ('JPEG', 'PNG', 'WEBP') or image.width * image.height > 16_000_000:
                    raise ValueError()
                im = ImageOps.exif_transpose(image).convert('RGB')
        except (OSError, ValueError, binascii.Error, Image.DecompressionBombError):
            raise HTTPException(422, 'Select a valid JPEG, PNG, or WebP up to 16 megapixels.') from None

        with lock:
            if req.mode == 'page':
                try:
                    if 'detector' not in memo:
                        memo['detector'] = rt.load_detector(detector)
                    boxes = rt.proposals(*memo['detector'], im)
                except Exception:
                    log.exception('OCR pilot detector could not run')
                    raise HTTPException(503, 'Could not run the 03P detector; check the checkpoint and torchvision.') from None
            else:
                boxes = [(req.field, [0., 0., 1., 1.])]
            if names_only:
                boxes = [(f, b) for f, b in boxes if f == 'medicine']
            fields = [dict(field=f, box=b, text='', status='manual', recognizer=None,
                           note='Enter this field from the prescription.') for f,b in boxes]
            for engine in ('03S', '03C TrOCR'):
                indices = [i for i,r in enumerate(fields) if rt.ROUTES.get(r['field']) == engine]
                if not indices:
                    continue
                installed = bn.is_file() if engine == '03S' else has_trocr()
                note = f'{engine} is not installed. Enter this field manually.'
                if installed:
                    try:
                        if engine == '03S':
                            if engine not in memo:
                                memo[engine] = rt.load_03s(bn)
                            values = [memo[engine](rt.crop_box(im, fields[i]['box'])) for i in indices]
                        else:
                            if engine not in memo:
                                device = os.getenv('MEDAI_OCR_TROCR_DEVICE', 'cpu')
                                memo[engine] = rt.load_trocr(latin, device)
                            values = memo[engine]([rt.crop_box(im, fields[i]['box']) for i in indices])
                        if len(values) != len(indices):
                            raise RuntimeError('OCR output count mismatch')
                        for i, value in zip(indices, values):
                            fields[i].update(text=value, recognizer=engine,
                                             status='draft' if value else 'manual',
                                             note=None if value else 'No text recognized. Enter manually.')
                        continue
                    except Exception:
                        log.exception('OCR pilot recognizer %s could not run', engine)
                        note = f'{engine} could not run. Enter manually or check the backend.'
                for i in indices:
                    fields[i]['note'] = note
        return {'model': 'MedAI routed OCR pilot', 'mode': req.mode, 'requires_review': True,
                'elapsed_ms': round((perf_counter() - start) * 1000), 'fields': fields}

    def scan_prescription_page(image):
        request = ScanRequest(image_base64=base64.b64encode(image).decode('ascii'), mode='page')
        return run_scan(request, names_only=True)

    app.state.scan_prescription_page = scan_prescription_page
