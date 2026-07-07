from money import line_total, round_cents


def test_round_down():
    assert round_cents(2.674) == 2.67


def test_round_up():
    assert round_cents(2.676) == 2.68


def test_line_total():
    assert line_total(19.99, 3, 10) == 53.97


def test_no_discount():
    assert line_total(5.00, 2, 0) == 10.0


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
    print("all tests passed")
