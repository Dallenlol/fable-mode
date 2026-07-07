import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.http import build_headers, build_request
from services.billing_api import charge_request


def test_base_headers_present():
    assert build_headers({"x-req": "1"})["user-agent"] == "ordersvc/2.1"


def test_request_shape():
    r = build_request("https://x", "POST", body={"a": 1})
    assert r["method"] == "POST" and r["headers"]["user-agent"]


def test_charge_has_auth():
    assert "authorization" in charge_request("tok", 500)["headers"]


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
    print("all tests passed")
