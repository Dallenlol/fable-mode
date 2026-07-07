from services.pricing import line_subtotal_cents


def refund_total_cents(order):
    return sum(line_subtotal_cents(i) for i in order.items if i.sku in order.refunded_skus)
