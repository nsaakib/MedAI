from typing import Literal
from pydantic import BaseModel, Field, ConfigDict, field_validator, model_validator


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Login(Strict):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=10, max_length=256)

    @field_validator("email")
    @classmethod
    def email_format(cls, value):
        if "@" not in value or "." not in value.split("@")[-1]:
            raise ValueError("Enter a valid email")
        return value.lower()


class Register(Login):
    name: str = Field(min_length=1, max_length=120)


class Medicine(Strict):
    id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=160)
    strength: str = Field(default="", max_length=100)
    form: str = Field(default="", max_length=100)
    frequency: str = Field(default="", max_length=100)
    meal: str = Field(default="", max_length=160)
    duration: str = Field(default="", max_length=100)
    route: str = Field(default="", max_length=100)
    instruction: str = Field(default="", max_length=1000)
    quantity: int = Field(ge=1, le=100000)
    unit_price_minor: int = Field(ge=0, le=100000000)
    verified: bool = False
    source_document_id: str | None = Field(default=None, max_length=64)
    quantity_unit: str = Field(default="unit", min_length=1, max_length=60)
    purchased: bool = False
    price_confirmed: bool = False
    quote_id: str | None = Field(default=None, max_length=64)
    product_match_confirmed: bool = False
    price_quote: dict | None = None
    stock_units: int | None = Field(default=None, ge=0, le=100000)
    units_taken: int = Field(default=0, ge=0, le=100000)
    confirmed_dose_units: int | None = Field(default=None, ge=1, le=99)
    course_start: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    refill_threshold: int | None = Field(default=None, ge=0, le=100000)
    paracetamol_group: bool = False
    antibiotic_group: bool = False

    @field_validator("price_quote")
    @classmethod
    def quote_size(cls, value):
        import json

        if value is not None and len(json.dumps(value)) > 8000:
            raise ValueError("Price quote metadata too large")
        return value


class Vital(Strict):
    id: str = Field(min_length=1, max_length=64)
    kind: Literal["heart_rate", "systolic_bp", "diastolic_bp", "glucose", "weight"]
    value: float = Field(gt=0, le=10000, allow_inf_nan=False)
    unit: str = Field(min_length=1, max_length=20)
    measured_at: str = Field(min_length=1, max_length=40)
    source: Literal["manual"] = "manual"

    @model_validator(mode="after")
    def units_and_date(self):
        from datetime import datetime

        accepted = {
            "heart_rate": {"bpm"},
            "systolic_bp": {"mmHg"},
            "diastolic_bp": {"mmHg"},
            "glucose": {"mg/dL", "mmol/L"},
            "weight": {"kg"},
        }
        if self.unit not in accepted[self.kind]:
            raise ValueError("Unit does not match measurement")
        stamp = datetime.fromisoformat(self.measured_at.replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            raise ValueError("Measurement timestamp needs a time zone")
        return self


class Dose(Strict):
    id: str = Field(min_length=1, max_length=64)
    medicine_id: str = Field(min_length=1, max_length=64)
    logged_at: str = Field(min_length=1, max_length=40)
    units: int | None = Field(default=None, ge=1, le=100000)
    scheduled_key: str | None = Field(default=None, max_length=90)


class Reminder(Strict):
    id: str = Field(min_length=1, max_length=64)
    medicine_id: str = Field(min_length=1, max_length=64)
    hour: int = Field(ge=0, le=23)
    minute: int = Field(ge=0, le=59)
    enabled: bool = True
    automatic: bool = False
    meal_slot: int | None = Field(default=None, ge=0, le=2)
    start_date: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    end_date: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")


class PatientState(Strict):
    name: str = Field(min_length=1, max_length=120)
    email: str = Field(max_length=254)
    phone: str = Field(default="", max_length=40)
    allergies: str = Field(default="", max_length=1000)
    medicines: list[Medicine] = Field(default_factory=list, max_length=200)
    vitals: list[Vital] = Field(default_factory=list, max_length=2000)
    doses: list[Dose] = Field(default_factory=list, max_length=5000)
    reminders: list[Reminder] = Field(default_factory=list, max_length=400)
    budget_set: bool = False
    budget: int = Field(default=0, ge=0, le=100000000)
    delivery: int = Field(default=0, ge=0, le=10000000)
    selected_ids: list[str] = Field(default_factory=list, max_length=200)
    journal: str = Field(default="", max_length=10000)
    precise_reminders: bool = False
    meal_minutes: list[int] = Field(default_factory=list, max_length=3)
    before_meal_minutes: int | None = Field(default=None, ge=1, le=180)
    after_meal_minutes: int | None = Field(default=None, ge=1, le=180)
    mood: str = Field(default="", max_length=40)
    language: str = Field(default="English", max_length=40)
    timezone: Literal[
        "Asia/Dhaka", "Asia/Kolkata", "UTC", "Europe/London", "America/Los_Angeles"
    ] = "Asia/Dhaka"

    @field_validator("meal_minutes")
    @classmethod
    def three_meals(cls, value):
        if value and (len(value) != 3 or value != sorted(set(value)) or not all(0 <= x < 1440 for x in value)):
            raise ValueError("Choose breakfast, lunch and dinner in order")
        return value

    @field_validator("medicines")
    @classmethod
    def unique_ids(cls, value):
        if len({m.id for m in value}) != len(value):
            raise ValueError("Duplicate medicine IDs")
        return value


class Sync(Strict):
    event_id: str = Field(min_length=8, max_length=64)
    base_version: int = Field(ge=0)
    state: PatientState


class CaseCreate(Strict):
    reason: str = Field(min_length=5, max_length=4000)
    document_ids: list[str] = Field(default_factory=list, max_length=20)
    consent: Literal[True]


class CaseUpdate(Strict):
    expected_version: int = Field(ge=1)
    status: Literal["in_review", "needs_information", "completed"]
    note: str = Field(min_length=1, max_length=4000)
