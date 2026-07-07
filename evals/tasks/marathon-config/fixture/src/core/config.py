"""Layered settings: defaults < config file < environment. Env always wins."""
import json
import os

DEFAULTS = {"timeout_s": 30, "retries": 3, "endpoint": "https://api.internal", "debug": "0"}
ENV_PREFIX = "APP_"


def _env_overrides():
    out = {}
    for key in DEFAULTS:
        val = os.environ.get(ENV_PREFIX + key.upper())
        if val is not None:
            out[key] = type(DEFAULTS[key])(val) if not isinstance(DEFAULTS[key], str) else val
    return out


def load_settings(path=None):
    file_cfg = {}
    if path and os.path.exists(path):
        file_cfg = json.load(open(path))
    merged = {**DEFAULTS, **_env_overrides(), **file_cfg}
    return merged
