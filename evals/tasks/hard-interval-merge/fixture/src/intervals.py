"""Interval utilities for the billing engine.

All intervals are inclusive [start, end] pairs of ints with start <= end.
"""


def normalize(intervals):
    """Return intervals as sorted (start, end) tuples, validating start <= end."""
    out = []
    for s, e in intervals:
        if s > e:
            raise ValueError(f"invalid interval: ({s}, {e})")
        out.append((s, e))
    return sorted(out)


def merge_intervals(intervals):
    """Merge overlapping intervals (including ones that share an endpoint)
    into the minimal sorted list of disjoint intervals covering exactly the
    same integer points.

    merge_intervals([(1, 3), (2, 5), (7, 8)]) -> [(1, 5), (7, 8)]
    """
    ivs = normalize(intervals)
    if not ivs:
        return []
    merged = [list(ivs[0])]
    for s, e in ivs[1:]:
        last = merged[-1]
        if s <= last[1]:
            last[1] = e
        else:
            merged.append([s, e])
    return [tuple(p) for p in merged]


def intersect(a, b):
    """Intersection of two intervals, or None if they don't overlap."""
    s, e = max(a[0], b[0]), min(a[1], b[1])
    return (s, e) if s <= e else None


def total_coverage(intervals):
    """Number of integer points covered by the union of the intervals."""
    return sum(e - s + 1 for s, e in merge_intervals(intervals))


def invert(intervals, lo, hi):
    """Gaps within [lo, hi] not covered by any interval, as a sorted list."""
    gaps, cur = [], lo
    for s, e in merge_intervals(intervals):
        if s > hi or e < lo:
            continue
        s2, e2 = max(s, lo), min(e, hi)
        if s2 > cur:
            gaps.append((cur, s2 - 1))
        cur = max(cur, e2 + 1)
    if cur <= hi:
        gaps.append((cur, hi))
    return gaps


def contains_point(intervals, x):
    """True if x lies inside any of the intervals."""
    return any(s <= x <= e for s, e in intervals)
