from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_healthz():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["ok"] is True


def test_greet_template_fallback():
    payload = {"name": "Radhe", "dob": "1995-01-10", "occasion": "new_year", "tone": "motivational"}
    r = client.post("/api/greet", json=payload)
    assert r.status_code == 200
    data = r.json()
    assert "message" in data
    assert data["source"] in ["openai", "template"]
