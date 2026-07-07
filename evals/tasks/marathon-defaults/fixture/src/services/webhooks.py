from core.http import build_headers


def webhook_headers(signature):
    h = build_headers()
    h["x-signature"] = signature
    return h
