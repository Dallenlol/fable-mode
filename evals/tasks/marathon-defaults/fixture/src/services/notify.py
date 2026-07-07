from core.http import build_request


def notify_request(channel, text):
    return build_request(f"https://notify/{channel}", "POST", body={"text": text})
