import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.models import LineItem, Order
from services.invoicing import invoice_total_cents
from services.refunds import refund_total_cents


def _order(*items):
    o = Order(order_id="t1")
    o.items = [LineItem(*i) for i in items]
    return o


def test_round_dollar_orders():
    # $10.00 x 2 = 2000c, tax 100c
    assert invoice_total_cents(_order(("A", 10.0, 2))) == 2100


def test_volume_discount():
    # $1.00 x 20 = 2000c, -5% = 1900c, tax 95c
    assert invoice_total_cents(_order(("B", 1.0, 20))) == 1995


def test_refunds():
    o = _order(("A", 10.0, 1), ("B", 2.0, 3))
    o.refunded_skus = {"B"}
    assert refund_total_cents(o) == 600


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
    print("all tests passed")
