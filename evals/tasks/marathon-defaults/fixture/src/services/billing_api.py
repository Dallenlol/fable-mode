from core.auth import bearer
from core.http import build_request


def charge_request(token, amount_cents):
    return build_request("https://billing/charge", "POST",
                         headers=bearer(token), body={"amount": amount_cents})
