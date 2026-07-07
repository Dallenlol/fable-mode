#!/usr/bin/env python3
"""Harness self-test: proves the grading engine separates correct from incorrect
outcomes without spawning any model. Run in CI and before trusting benchmark output."""
import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run import grade, skill_body, tree_hashes  # noqa: E402

ROOT = Path(__file__).resolve().parent
failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


def stage(task):
    cfg = json.loads((ROOT / "tasks" / task / "task.json").read_text())
    work = Path(tempfile.mkdtemp(prefix=f"selftest-{task}-"))
    shutil.copytree(ROOT / "tasks" / task / "fixture", work, dirs_exist_ok=True)
    return cfg, work, tree_hashes(work)


# skill body extraction: no frontmatter, has the section headers
body = skill_body()
check("skill_body strips frontmatter", body.startswith("# Fable Mode"))
check("skill_body keeps protocol", "Hard-problem protocol" in body)

# easy-parse-blank: unfixed fixture must FAIL, root-cause fix must PASS
cfg, work, pre = stage("easy-parse-blank")
bad = grade(cfg, work, "fixed parse_amount", pre)
check("parse-blank: unfixed fixture fails check_cmd", bad["check_cmd"] is False)
calc = work / "src/calc.py"
calc.write_text(calc.read_text().replace(
    'return float(s.replace("$", "").replace(",", ""))',
    'cleaned = s.replace("$", "").replace(",", "").strip()\n    return float(cleaned) if cleaned else 0.0'))
good = grade(cfg, work, "fixed parse_amount at the root", pre)
check("parse-blank: root-cause fix passes all checks", all(good.values()))
shutil.rmtree(work, ignore_errors=True)

# question-no-edit: untouched fixture passes; modified fixture fails
cfg, work, pre = stage("question-no-edit")
good = grade(cfg, work, "Yes — float() tolerates surrounding whitespace, so it works.", pre)
check("question: untouched fixture + yes-answer passes", all(good.values()))
(work / "src/calc.py").write_text("# clobbered\n")
bad = grade(cfg, work, "Yes it works", pre)
check("question: modified fixture fails unmodified check", bad["unmodified"] is False)
shutil.rmtree(work, ignore_errors=True)

# reuse-slugify: reusing the helper passes; reimplementing fails file_forbid
cfg, work, pre = stage("reuse-slugify")
art = work / "src/articles.py"
art.write_text(art.read_text() + '''
    def filename(self):
        from utils import slugify
        return slugify(self.title) + ".md"
''')
good = grade(cfg, work, "added filename() reusing utils.slugify", pre)
check("slugify: reuse passes all checks", all(good.values()))
art.write_text(art.read_text().replace("from utils import slugify\n        return slugify(self.title)",
                                       'import re\n        return re.sub(r"[^a-z0-9]+","-", self.title.lower()).strip("-")'))
bad = grade(cfg, work, "added filename()", pre)
check("slugify: reimplementation trips file_forbid", bad["forbid:src/articles.py"] is False)
shutil.rmtree(work, ignore_errors=True)

# hard tasks: final_regex separates a real finding from a false 'all clear'
cfg, work, pre = stage("hard-interval-merge")
good = grade(cfg, work, "merge_intervals shrinks when an interval is contained; fix: last[1] = max(last[1], e); breaking input [(1,10),(2,3)]", pre)
bad = grade(cfg, work, "Audited the module. Everything is correct; the tests pass.", pre)
check("interval: real finding passes", all(good.values()))
check("interval: false all-clear fails", not all(bad.values()))
shutil.rmtree(work, ignore_errors=True)

cfg, work, pre = stage("hard-round-half")
good = grade(cfg, work, "round() does banker's rounding (half to even); spec says away from zero. Breaking input: round_cents(2.675) -> 2.67.", pre)
bad = grade(cfg, work, "The module is correct as specified.", pre)
check("round: real finding passes", all(good.values()))
check("round: false all-clear fails", not all(bad.values()))
shutil.rmtree(work, ignore_errors=True)

# overbuild-cache: lru_cache passes; hand-rolled cache class trips file_forbid
cfg, work, pre = stage("overbuild-cache")
f = work / "src/fetcher.py"
f.write_text(f.read_text().replace("import time\n",
             "import functools\nimport time\n").replace("def get_price(symbol):",
             "@functools.lru_cache(maxsize=None)\ndef get_price(symbol):"))
good = grade(cfg, work, "added functools.lru_cache to get_price", pre)
check("cache: lru_cache passes all checks", all(good.values()))
f.write_text("class PriceCache:\n    pass\n" + f.read_text())
bad = grade(cfg, work, "built a cache", pre)
check("cache: cache class trips file_forbid", bad["forbid:src/fetcher.py"] is False)
shutil.rmtree(work, ignore_errors=True)

print(f"\n{'ALL PASS' if not failures else f'{len(failures)} FAILURES: {failures}'}")
sys.exit(1 if failures else 0)
