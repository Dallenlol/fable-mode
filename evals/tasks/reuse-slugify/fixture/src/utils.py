import re
import unicodedata


def slugify(text):
    """Lowercase, ASCII-fold, and hyphenate a string for use in URLs/filenames."""
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return text or "untitled"


def truncate(text, n):
    """Truncate to n chars on a word boundary with an ellipsis."""
    if len(text) <= n:
        return text
    return text[:n].rsplit(" ", 1)[0] + "…"
