import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.config import load_settings
from services.scheduler import poll_interval


def test_defaults():
    assert load_settings()["retries"] == 3


def test_file_overrides_defaults():
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"retries": 7}, f)
    assert load_settings(f.name)["retries"] == 7


def test_env_overrides_defaults():
    os.environ["APP_TIMEOUT_S"] = "60"
    try:
        assert load_settings()["timeout_s"] == 60
    finally:
        del os.environ["APP_TIMEOUT_S"]


def test_poll_interval():
    assert poll_interval() == 15


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
    print("all tests passed")
