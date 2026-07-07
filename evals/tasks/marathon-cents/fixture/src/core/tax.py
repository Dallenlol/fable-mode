from core.money import to_cents


TAX_RATE = 0.05


def tax_for(subtotal_cents):
    """GST on a subtotal, in cents, half-up."""
    return int(subtotal_cents * TAX_RATE + 0.5)
