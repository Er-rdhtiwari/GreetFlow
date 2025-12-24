from pydantic import BaseModel, Field
from datetime import date, datetime
from typing import Literal, Optional, Tuple

from app.settings import Settings


Occasion = Literal["new_year", "birthday"]
Tone = Literal["motivational", "funny", "formal"]


class GreetRequest(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    dob: str = Field(description="YYYY-MM-DD")
    occasion: Occasion
    tone: Tone


class GreetResponse(BaseModel):
    message: str
    source: Literal["openai", "template"]
    env: Literal["dev", "prod"]


def _parse_dob(dob_str: str) -> date:
    return datetime.strptime(dob_str, "%Y-%m-%d").date()


def _is_birthday_month(dob: date, today: date) -> bool:
    return dob.month == today.month


def _template_message(name: str, occasion: Occasion, tone: Tone, birthday_month: bool) -> str:
    if occasion == "new_year":
        if tone == "formal":
            return f"Happy New Year, {name}. Wishing you a prosperous and successful year ahead."
        if tone == "funny":
            return f"Happy New Year, {name}! New year, new vibes — same legend 😄"
        return f"Happy New Year, {name}! This year, take one bold step every day — you’ve got this 💪"

    # birthday
    if birthday_month:
        tag = "🎂 Birthday month vibes detected!"
    else:
        tag = "🎉 Early (or late) birthday cheers!"

    if tone == "formal":
        return f"{tag} Dear {name}, wishing you happiness, health, and success."
    if tone == "funny":
        return f"{tag} {name}, you’re not getting older… just becoming a classic 😄"
    return f"{tag} {name}, keep shining — your best days are ahead ✨"


def _openai_prompt(req: GreetRequest, birthday_month: bool) -> str:
    return (
        "You generate short greetings (1-2 sentences).\n"
        f"Name: {req.name}\n"
        f"Occasion: {req.occasion}\n"
        f"Tone: {req.tone}\n"
        f"BirthdayMonth: {'yes' if birthday_month else 'no'}\n"
        "Return only the greeting text."
    )


def generate_greeting(req: GreetRequest, settings: Settings) -> Tuple[str, str]:
    today = date.today()
    dob = _parse_dob(req.dob)
    birthday_month = _is_birthday_month(dob, today)

    if not settings.has_openai:
        return _template_message(req.name, req.occasion, req.tone, birthday_month), "template"

    # OpenAI path (with safe fallback)
    try:
        from openai import OpenAI

        client = OpenAI(api_key=settings.openai_api_key)
        prompt = _openai_prompt(req, birthday_month)

        # Chat Completions keeps this PoC simple; you can later migrate to Responses API if you want.
        out = client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": "You are a helpful greeting assistant."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.8,
            max_tokens=80,
        )
        text = (out.choices[0].message.content or "").strip()
        if not text:
            raise RuntimeError("Empty greeting from OpenAI")
        return text, "openai"
    except Exception:
        return _template_message(req.name, req.occasion, req.tone, birthday_month), "template"
