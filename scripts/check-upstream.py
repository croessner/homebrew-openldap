#!/usr/bin/env python3
"""Check the official OpenLDAP feature release; update only a newer source pin."""
import hashlib
import os
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://www.openldap.org/software/download/OpenLDAP/openldap-release/'

def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()

def main():
    formula = ROOT / 'openldap.rb'
    old = formula.read_text()
    current = re.search(r'openldap-(\d+\.\d+\.\d+)\.tgz', old).group(1)
    current_sha = re.search(r'^  sha256 "([a-f0-9]{64})"$', old, re.M).group(1)
    page = re.sub('<[^>]+>', '', fetch('https://www.openldap.org/software/download/').decode())
    match = re.search(r'Feature Release\s*,\s*OpenLDAP-(\d+\.\d+\.\d+)', page)
    if not match:
        raise RuntimeError('Cannot identify official Feature Release')
    latest = match.group(1)
    if tuple(map(int, latest.split('.'))) < tuple(map(int, current.split('.'))):
        raise RuntimeError('Upstream release would downgrade the formula')
    tarball = fetch(BASE + 'openldap-' + latest + '.tgz')
    sha3_text = fetch(BASE + 'openldap-' + latest + '.sha3-512').decode()
    expected = re.findall(r'\b[a-fA-F0-9]{128}\b', sha3_text)
    if len(expected) != 1 or hashlib.sha3_512(tarball).hexdigest() != expected[0].lower():
        raise RuntimeError('Official SHA3-512 checksum mismatch')
    checksum = hashlib.sha256(tarball).hexdigest()
    if latest == current and checksum != current_sha:
        raise RuntimeError('Pinned release changed checksum; manual investigation required')
    changed = latest != current
    if changed:
        updated = old.replace('openldap-' + current + '.tgz', 'openldap-' + latest + '.tgz')
        updated = updated.replace(current_sha, checksum)
        updated = re.sub(r'^  revision \d+\n', '', updated, flags=re.M)
        formula.write_text(updated)
    print(f'Current: {current}; upstream: {latest}; update: {changed}; official SHA3-512 verified')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'changed={str(changed).lower()}\nversion={latest}\nsha256={checksum}\n')

if __name__ == '__main__':
    main()
