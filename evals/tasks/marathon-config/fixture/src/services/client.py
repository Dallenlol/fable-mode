from core.config import load_settings


class ApiClient:
    def __init__(self, config_path=None):
        self.settings = load_settings(config_path)

    def request_plan(self):
        s = self.settings
        return {"url": s["endpoint"], "timeout": s["timeout_s"], "retries": s["retries"]}
