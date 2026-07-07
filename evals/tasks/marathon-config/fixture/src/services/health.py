from services.client import ApiClient


def health_summary(config_path=None):
    plan = ApiClient(config_path).request_plan()
    return f"target={plan['url']} timeout={plan['timeout']}s retries={plan['retries']}"
