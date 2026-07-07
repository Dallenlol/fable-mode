from core.config import load_settings


def poll_interval(config_path=None):
    return max(5, load_settings(config_path)["timeout_s"] // 2)
