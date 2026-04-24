#!/usr/bin/env python3
"""
Add a `content_languages` field to every curated list YAML.

The language of a list is inferred from the ISBN-13 registration group
(978-2 = French, 978-3 = German, 978-84 = Spanish, 978-0/1 = English,
978-4 = Japanese, ...). A language is kept when at least 20% of the list's
ISBNs belong to it, so mixed-language lists such as programming-python
become [fr, en] rather than collapsing to a single locale.

Run:
    python add_content_languages.py              # dry-run, prints the plan
    python add_content_languages.py --write      # apply in place
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

# Longest prefix wins. Keys are the digits that follow the 978 GS1 prefix.
# Reference: List of ISBN registration groups (Wikipedia).
ISBN_PREFIX_TO_LANG: dict[str, str] = {
    "0": "en",    # English (US/UK/Canada/Australia)
    "1": "en",    # English (US/UK/Canada/Australia)
    "2": "fr",    # French
    "3": "de",    # German
    "4": "ja",    # Japanese
    "5": "ru",    # Russian
    "7": "zh",    # Chinese
    "84": "es",   # Spanish (Spain)
    "85": "pt",   # Portuguese (Brazil)
    "88": "it",   # Italian
    "89": "ko",   # Korean
    "90": "nl",   # Dutch
    "91": "sv",   # Swedish
    "950": "es",  # Spanish (Argentina)
    "956": "es",  # Spanish (Chile)
    "958": "es",  # Spanish (Colombia)
    "968": "es",  # Spanish (Mexico)
    "970": "es",  # Spanish (Mexico)
    "972": "pt",  # Portuguese (Portugal)
    "987": "es",  # Spanish (Argentina)
}

# Minimum share of a list's ISBNs for a language to be kept.
MIN_SHARE = 0.20


def isbn_to_lang(isbn: str) -> str | None:
    digits = re.sub(r"\D", "", isbn)
    if len(digits) != 13 or not digits.startswith("978"):
        return None
    rest = digits[3:]
    for length in (3, 2, 1):
        prefix = rest[:length]
        if prefix in ISBN_PREFIX_TO_LANG:
            return ISBN_PREFIX_TO_LANG[prefix]
    return None


ISBN_LINE = re.compile(
    r"""^\s*-?\s*isbn\s*:\s*['"]?([\d\-]+)['"]?""",
    re.MULTILINE,
)


def extract_isbns(text: str) -> list[str]:
    return ISBN_LINE.findall(text)


def infer_languages(isbns: list[str]) -> tuple[list[str], Counter]:
    counts: Counter = Counter()
    for isbn in isbns:
        lang = isbn_to_lang(isbn)
        if lang is not None:
            counts[lang] += 1

    total = sum(counts.values())
    if total == 0:
        return [], counts

    kept = [lang for lang, n in counts.most_common() if n / total >= MIN_SHARE]
    if not kept:
        kept = [counts.most_common(1)[0][0]]
    return kept, counts


CONTENT_LANG_LINE = re.compile(r"^content_languages\s*:.*$", re.MULTILINE)
# Inline tags live on a single line; `tags: [a, b, c]` is a safe insertion
# point. For block-form tags (`tags:\n- a\n- b\n`) we must insert AFTER the
# whole block, not between the `tags:` key and its first item — otherwise
# the following items become orphan YAML tokens.
INLINE_TAGS_LINE = re.compile(r"^(tags\s*:\s*\[.*\]\s*\n)", re.MULTILINE)
BLOCK_TAGS_BLOCK = re.compile(
    r"^(tags\s*:\s*\n(?:[ \t]+-\s.*\n|[ \t]*\n)+)",
    re.MULTILINE,
)
BOOKS_LINE = re.compile(r"^(books\s*:)", re.MULTILINE)


def format_list(languages: list[str]) -> str:
    return "[" + ", ".join(languages) + "]"


def upsert_field(text: str, languages: list[str], force: bool = False) -> str:
    new_line = f"content_languages: {format_list(languages)}"

    if CONTENT_LANG_LINE.search(text):
        if not force:
            # Preserve the existing value; it may have been hand-curated
            # (e.g. universal lists that use `alt_editions` for extra locales).
            return text
        return CONTENT_LANG_LINE.sub(new_line, text, count=1)

    replacement_after_tags = r"\1" + new_line + "\n"

    updated, n = INLINE_TAGS_LINE.subn(replacement_after_tags, text, count=1)
    if n:
        return updated

    updated, n = BLOCK_TAGS_BLOCK.subn(replacement_after_tags, text, count=1)
    if n:
        return updated

    replacement_before_books = new_line + "\n\n" + r"\1"
    updated, n = BOOKS_LINE.subn(replacement_before_books, text, count=1)
    if n:
        return updated

    # Last resort: append to end.
    return text.rstrip() + "\n\n" + new_line + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="Apply changes in place")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite content_languages even when already set (default: preserve)",
    )
    default_root = Path(__file__).resolve().parent.parent / "assets" / "curated_lists"
    parser.add_argument("--root", default=str(default_root))
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        print(f"Root directory not found: {root}", file=sys.stderr)
        return 1

    files = sorted(p for p in root.glob("*/*.yml") if p.name != "index.yml")
    print(f"Scanning {len(files)} list files under {root}\n")

    to_review: list[tuple[Path, str, Counter]] = []
    changed = 0

    for f in files:
        text = f.read_text()
        isbns = extract_isbns(text)
        languages, counts = infer_languages(isbns)
        total = sum(counts.values())

        reasons = []
        if not languages:
            reasons.append("no ISBN detected")
        if total > 0 and len(languages) >= 3:
            reasons.append("3+ languages")
        if 0 < total < 3:
            reasons.append("fewer than 3 ISBNs")

        rel = f.relative_to(root)
        counts_repr = ", ".join(f"{k}={v}" for k, v in sorted(counts.items())) or "-"
        flag = "REVIEW" if reasons else "ok    "
        print(f"  [{flag}] {str(rel):48s} -> {languages}  ({counts_repr})")

        if reasons:
            to_review.append((rel, "; ".join(reasons), counts))

        if args.write and languages:
            new_text = upsert_field(text, languages, force=args.force)
            if new_text != text:
                f.write_text(new_text)
                changed += 1

    if to_review:
        print(f"\nReview queue ({len(to_review)} lists):")
        for rel, reason, counts in to_review:
            print(f"  - {rel}: {reason} (counts={dict(counts)})")

    if args.write:
        print(f"\nUpdated {changed} files.")
    else:
        print("\nDry run. Re-run with --write to apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
