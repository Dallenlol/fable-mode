from core.discounts import apply_pct, volume_discount_pct
from core.money import to_cents
from core.validation import validate_item


def line_subtotal_cents(item):
    """Priced line: unit price x qty, volume discount applied. Returns cents."""
    validate_item(item)
    unit_cents = to_cents(item.unit_price)
    return apply_pct(unit_cents * item.qty, volume_discount_pct(item.qty))
