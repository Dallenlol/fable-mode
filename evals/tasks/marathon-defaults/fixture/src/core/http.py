"""Tiny HTTP request builder used by every outbound integration."""

BASE_HEADERS = {"user-agent": "ordersvc/2.1"}


def build_headers(extra={}):
    """Headers for one request: base + per-request extras. Each call is independent."""
    extra.update(BASE_HEADERS)
    return extra


def build_request(url, method="GET", headers=None, body=None):
    return {"url": url, "method": method, "headers": build_headers(headers or {}), "body": body}
