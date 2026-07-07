from core.money import from_cents
from services.invoicing import invoice_total_cents


def daily_revenue(orders):
    return from_cents(sum(invoice_total_cents(o) for o in orders))
