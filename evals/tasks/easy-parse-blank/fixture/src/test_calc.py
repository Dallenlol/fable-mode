from calc import invoice_total, refund_total


def test_invoice_total():
    assert invoice_total([{"amount": "$1,200.50"}, {"amount": "$99.50"}]) == 1300.0


def test_invoice_total_blank_amount():
    assert invoice_total([{"amount": ""}, {"amount": "$10.00"}]) == 10.0


def test_refund_total_blank_amount():
    assert refund_total([{"amount": "", "refunded": True}, {"amount": "$5.00", "refunded": True}]) == 5.0


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
    print("all tests passed")
