from intervals import (contains_point, intersect, invert, merge_intervals,
                       normalize, total_coverage)


def test_merge_overlapping():
    assert merge_intervals([(1, 3), (2, 5), (7, 8)]) == [(1, 5), (7, 8)]


def test_merge_shared_endpoint():
    assert merge_intervals([(1, 2), (2, 3)]) == [(1, 3)]


def test_merge_chain():
    assert merge_intervals([(1, 2), (2, 4), (4, 9)]) == [(1, 9)]


def test_merge_disjoint_unsorted():
    assert merge_intervals([(5, 6), (1, 2)]) == [(1, 2), (5, 6)]


def test_merge_empty_and_single():
    assert merge_intervals([]) == []
    assert merge_intervals([(4, 4)]) == [(4, 4)]


def test_normalize_rejects_backwards():
    try:
        normalize([(3, 1)])
        assert False, "should have raised"
    except ValueError:
        pass


def test_intersect():
    assert intersect((1, 5), (3, 9)) == (3, 5)
    assert intersect((1, 2), (4, 5)) is None


def test_total_coverage():
    assert total_coverage([(1, 3), (2, 5)]) == 5


def test_invert():
    assert invert([(2, 3), (6, 7)], 1, 9) == [(1, 1), (4, 5), (8, 9)]


def test_contains_point():
    assert contains_point([(1, 3), (7, 9)], 8)
    assert not contains_point([(1, 3), (7, 9)], 5)


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
    print("all tests passed")
