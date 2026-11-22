#!/usr/bin/env python3
"""Check the translated catalogs in lib/l10n against app_en.arb.

Every app_<locale>.arb must name its locale, hold no message the template
lacks, and use in each message exactly the placeholders of the English one,
with the same plural and select arguments. A translation may also put a
number the English only shows into a plural, where its grammar needs one.
A plural names every category its language has (CLDR), so that no number
falls to a wrong form.

Missing messages fall back to English at run time; they are counted, and
fail the check for the locales named with --complete.

Usage: tool/check_l10n.py [--complete LOCALE]...
"""
import argparse
import json
import re
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / 'lib/l10n'
# CLDR cardinal categories of the languages that have a catalog.
PLURAL_CATEGORIES = {
    'en': {'one', 'other'},
    'ru': {'one', 'few', 'many', 'other'},
    'zh': {'other'},
}
# A category one exact number makes up, which may stand for it.
EXACT = {'en': {'one': '=1'}}
OPTION = re.compile(r'\s*([^\s{}]+)\s*\{')


def load(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'{path.name}: duplicate key {key}')
            result[key] = value
        return result
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique)


def unquoted(message):
    """The message without what its apostrophes quote (use-escaping)."""
    return re.sub("'[^']*'", '', message.replace("''", ''))


def closing(text, start):
    """The index after the brace that closes the one before `start`."""
    depth = 1
    while depth:
        if start == len(text):
            raise ValueError('unbalanced {')
        depth += {'{': 1, '}': -1}.get(text[start], 0)
        start += 1
    return start


def arguments(message):
    """The (name, kind) of every argument and the selectors of each plural."""
    found, plurals = set(), []

    def walk(text):
        index = 0
        while index < len(text):
            if text[index] == '}':
                raise ValueError('unbalanced }')
            if text[index] != '{':
                index += 1
                continue
            end = closing(text, index + 1)
            inner = text[index + 1:end - 1]
            index = end
            parts = inner.split(',', 2)
            name = parts[0].strip()
            if not re.fullmatch(r'\w+', name):
                raise ValueError(f'not an argument: {{{inner}}}')
            if len(parts) == 1:
                found.add((name, 'value'))
                continue
            kind = parts[1].strip()
            if kind not in ('plural', 'select') or len(parts) != 3:
                raise ValueError(f'unsupported argument: {{{inner}}}')
            found.add((name, kind))
            selectors, options, position = set(), parts[2], 0
            while position < len(options):
                match = OPTION.match(options, position)
                if not match:
                    if options[position:].strip():
                        raise ValueError(f'bad options: {options}')
                    break
                position = closing(options, match.end())
                selectors.add(match.group(1))
                walk(options[match.end():position - 1])
            if 'other' not in selectors:
                raise ValueError(f'{name}: no "other"')
            if kind == 'plural':
                plurals.append((name, selectors))

    walk(unquoted(message))
    return found, plurals


def check(locale, template, catalog, complete):
    errors = []
    if catalog.get('@@locale') != locale:
        errors.append(f'@@locale is {catalog.get("@@locale")!r}')
    messages = [key for key in template if not key.startswith('@')]
    errors += [f'{key}: not in app_en.arb'
               for key in catalog if not key.startswith('@') and key not in template]
    missing = [key for key in messages if key not in catalog]
    if complete:
        errors += [f'{key}: not translated' for key in missing]
    for key in messages:
        if key not in catalog:
            continue
        value = catalog[key]
        if not isinstance(value, str) or not value.strip():
            errors.append(f'{key}: empty')
            continue
        try:
            expected, _ = arguments(template[key])
            used, plurals = arguments(value)
        except ValueError as error:
            errors.append(f'{key}: {error}')
            continue
        declared = template.get('@' + key, {}).get('placeholders', {})
        for name, kind in sorted(used ^ expected):
            numeric = declared.get(name, {}).get('type') in ('int', 'num')
            both = {(name, 'value'), (name, 'plural')} <= used | expected
            if not (numeric and both):
                errors.append(f'{key}: {{{name}}} ({kind}) differs from English')
        for name, selectors in plurals:
            categories = PLURAL_CATEGORIES[locale]
            lacking = {
                category for category in categories - selectors
                if EXACT.get(locale, {}).get(category) not in selectors
            }
            unknown = {s for s in selectors if not s.startswith('=')} - categories
            if lacking or unknown:
                errors.append(f'{key}: plural {name} lacks {sorted(lacking)}, '
                              f'has unknown {sorted(unknown)}')
        if value != value.strip() and template[key] == template[key].strip():
            errors.append(f'{key}: stray spaces at an end')
        if value.count('\n') != template[key].count('\n'):
            errors.append(f'{key}: line breaks differ from English')
    return len(messages) - len(missing), len(missing), errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--complete', action='append', default=[], metavar='LOCALE')
    options = parser.parse_args()
    template = load(CATALOG / 'app_en.arb')
    failed = False
    seen = set()
    for path in sorted(CATALOG.glob('app_*.arb')):
        locale = path.stem.removeprefix('app_')
        seen.add(locale)
        catalog = template if locale == 'en' else load(path)
        translated, missing, errors = check(
            locale, template, catalog, locale == 'en' or locale in options.complete)
        for error in errors:
            print(f'{path.name}: {error}', file=sys.stderr)
        failed = failed or bool(errors)
        print(f'{"FAIL" if errors else "PASS"} {path.name}: {translated} messages'
              + (f', {missing} left in English' if missing else ''))
    for locale in sorted(set(options.complete) - seen):
        print(f'FAIL app_{locale}.arb: no such catalog', file=sys.stderr)
        failed = True
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
