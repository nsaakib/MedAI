# Connect your prescription OCR model without changing the app

Camera/gallery capture, encrypted source-image storage, manual medicine entry and a review UI are implemented now. The app deliberately returns no structured candidates until a local model adapter is configured. Optional Tesseract remains a raw-text helper, not a handwritten-medicine extraction model.

## Adapter interface

Create a trusted server-side Python module such as `backend/app/my_ocr.py` with:

```python
# Load your actual detector/recognizer checkpoints once at module import or lazily.
# Map your trained labels: dosage_form -> form, special_instruction -> instruction.
def extract(image_bytes: bytes, language: str) -> dict:
    # image_bytes is an EXIF-normalized JPEG; language is eng, ben or eng+ben.
    # Run your actual model here. Do not fill unreadable fields from guesses.
    prediction = your_model_inference(image_bytes, language)
    return {
        "status": "ready" if prediction["candidates"] else "no_readable_medicines",
        "model_version": prediction["checkpoint_version"],
        "raw_text": prediction.get("raw_text", ""),
        "candidates": prediction["candidates"],
    }
```

This is an interface example, not a runnable model or a supplied checkpoint. Implement `your_model_inference` with your actual trained model and install its dependencies in the backend venv.

Each candidate may contain these strings: `name`, `strength`, `form`, `frequency`, `meal`, `duration`, `route`, `instruction`, `evidence`. Missing values remain empty strings. Optional `confidence` must be a finite number in [0,1], and `box` is a four-coordinate list in original image pixel coordinates. The app shows model output as unverified. Keep the total prescribed purchase quantity for manual review; it is not inferred from frequency/duration by this adapter contract.

In the existing `backend/.env`, add:

```dotenv
MEDAI_OCR_ADAPTER=app.my_ocr:extract
```

Restart the backend. The environment value names trusted local Python code, never an arbitrary patient-supplied URL. The native app calls `POST /api/documents/{id}/extract`; only the image owner can invoke it. Responses are validated and cached encrypted with the document. No candidate automatically changes the medicine list, reminder times, purchase selection or prescription. The patient opens each candidate, edits it and explicitly saves/reviews it.

`GET /api/extraction/capabilities` reports whether the adapter is connected. Invalid predictions/model failures return a clear error while retaining the image and manual-entry path. Keep local inference within the mobile request timeout (60 seconds); deploy a job worker before using models requiring long-running inference. GPU/offline mobile model execution is a separate deployment step, not included here.

No images are sent to a third-party AI provider by this adapter. Clinical evaluation, field-level extraction accuracy and handwriting performance depend on your supplied checkpoints and validation data.
