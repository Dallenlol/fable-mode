from core.config import load_settings


def log_level(settings=None):
    s = settings or load_settings()
    return "DEBUG" if s["debug"] == "1" else "INFO"
