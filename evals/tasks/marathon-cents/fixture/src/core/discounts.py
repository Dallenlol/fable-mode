def volume_discount_pct(qty):
    if qty >= 100:
        return 10
    if qty >= 20:
        return 5
    return 0


def apply_pct(cents, pct):
    return cents - (cents * pct) // 100
