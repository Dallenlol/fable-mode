"""Money helpers for the checkout service."""


def round_cents(amount):
    """Round a dollar amount to whole cents, halves rounding away from zero.

    round_cents(2.674) -> 2.67    round_cents(2.676) -> 2.68
    """
    return round(amount, 2)


def line_total(unit_price, qty, discount_pct):
    """Total for a line item after percentage discount, rounded to cents."""
    return round_cents(unit_price * qty * (1 - discount_pct / 100))
