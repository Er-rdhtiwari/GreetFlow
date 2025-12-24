import logging
import uuid
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.settings import Settings
from app.greet import GreetRequest, GreetResponse, generate_greeting

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("greetflow")

settings = Settings()

app = FastAPI(title="GreetFlow API")

# PoC-friendly CORS; tighten later (allow only your domains)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_id_mw(request: Request, call_next):
    rid = request.headers.get("x-request-id") or str(uuid.uuid4())
    request.state.request_id = rid
    response = await call_next(request)
    response.headers["x-request-id"] = rid
    return response


@app.get("/healthz")
def healthz():
    return {"ok": True, "env": settings.app_env}


@app.post("/api/greet", response_model=GreetResponse)
def greet(payload: GreetRequest, request: Request):
    msg, source = generate_greeting(payload, settings)
    rid = getattr(request.state, "request_id", "-")
    log.info("greet req_id=%s env=%s source=%s name=%s occasion=%s",
             rid, settings.app_env, source, payload.name, payload.occasion)
    return GreetResponse(message=msg, source=source, env=settings.app_env)  # type: ignore
