from core.money import fmt


def money_field(cents):
    return {"cents": cents, "display": fmt(cents)}
