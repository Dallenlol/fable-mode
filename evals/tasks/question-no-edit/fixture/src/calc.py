def parse_amount(s):
    """Parse a money string like '$1,200.50' into a float."""
    return float(s.replace("$", "").replace(",", ""))


def invoice_total(rows):
    return sum(parse_amount(r["amount"]) for r in rows)


def refund_total(rows):
    return sum(parse_amount(r["amount"]) for r in rows if r.get("refunded"))
