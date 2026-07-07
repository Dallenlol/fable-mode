from core.money import fmt
from core.tax import tax_for
from services.pricing import line_subtotal_cents


def invoice_total_cents(order):
    """Grand total for an order: lines + tax."""
    subtotal = sum(line_subtotal_cents(i) for i in order.items)
    return subtotal + tax_for(subtotal)


def invoice_summary(order):
    total = invoice_total_cents(order)
    return f"Order {order.order_id}: {fmt(total)} ({len(order.items)} lines)"
