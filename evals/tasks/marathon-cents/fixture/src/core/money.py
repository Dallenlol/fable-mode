"""Money primitives. All internal amounts are integer cents."""


def to_cents(dollars):
    """Convert a float dollar amount to integer cents."""
    return int(dollars * 100)


def from_cents(cents):
    """Format integer cents as a dollar float."""
    return cents / 100


def fmt(cents):
    return f"${cents // 100}.{cents % 100:02d}"
