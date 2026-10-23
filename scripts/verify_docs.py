"""Check maintained local Markdown links and headings without a build or network.

Scope is deliberately small: inline/reference links, images, ATX/Setext headings
and quoted HTML anchors. Fenced, indented and inline code are excluded. This is
not a Markdown renderer or a check of external URLs and executable examples.
"""
from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import string
import subprocess
import unicodedata
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
TITLE = r'''(?:"[^"\n]*"|'[^'\n]*'|\([^()\n]*\))'''
ESCAPE = re.compile(r'\\([' + re.escape(string.punctuation) + r'])')


def blank(text: str) -> str:
    return ''.join('\n' if char == '\n' else ' ' for char in text)


def escaped(text: str, index: int) -> bool:
    start = index
    while start and text[start - 1] == '\\':
        start -= 1
    return (index - start) % 2 == 1


def code_mask(text: str) -> tuple[str, str, list[dict], list[tuple[int, str]]]:
    """Preserve positions; headings retain inline-code text for their slug."""
    lines = text.splitlines(keepends=True)
    visible = lines.copy()
    blocks, issues = [], []
    start = 0
    if lines and lines[0].strip() == '---':
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None)
        if end is not None:
            for i in range(end + 1):
                visible[i] = blank(lines[i])
            start = end + 1
    fence = None
    for i in range(start, len(lines)):
        line = lines[i].rstrip('\r\n')
        if fence:
            char, size, language, opening = fence
            visible[i] = blank(lines[i])
            if re.fullmatch(r' {0,3}' + re.escape(char) + '{' + str(size) + r',}[ \t]*', line):
                if language in ('powershell', 'ps1'):
                    blocks.append({'line': opening + 2, 'code': ''.join(lines[opening + 1:i])})
                fence = None
        else:
            match = re.match(r' {0,3}(`{3,}|~{3,})([^\r\n]*)$', line)
            if match:
                marker, info = match.groups()
                language = info.strip().split(maxsplit=1)[0].lower() if info.strip() else ''
                fence = (marker[0], len(marker), language, i)
                visible[i] = blank(lines[i])
            elif line.startswith(('    ', '\t')):
                visible[i] = blank(lines[i])
    if fence:
        issues.append((fence[3] + 1, 'Unclosed code fence.'))
    headings = ''.join(visible)
    masked = list(headings)
    for match in re.finditer(r'`+', headings):
        if masked[match.start()] == ' ' or escaped(headings, match.start()):
            continue
        closing = re.search(r'(?<!`)' + match.group() + r'(?!`)', headings[match.end():])
        if closing:
            end = match.end() + closing.end()
            masked[match.start():end] = blank(headings[match.start():end])
    return headings, ''.join(masked), blocks, issues


def destination(body: str) -> str:
    body = body.strip()
    if not body:
        return ''
    pattern = (r'<([^<>\n]*)>' if body.startswith('<') else r'((?:\\.|[^\s])+)')
    match = re.fullmatch(pattern + r'(?:\s+' + TITLE + r')?', body)
    if not match:
        raise ValueError('Invalid link destination; use <...> or percent encoding for spaces.')
    return html.unescape(ESCAPE.sub(r'\1', match[1]))


def closing(text: str, start: int, opening: str, ending: str) -> int | None:
    depth = 0
    for i in range(start, len(text)):
        if escaped(text, i):
            continue
        if text[i] == opening:
            depth += 1
        elif text[i] == ending:
            depth -= 1
            if depth == 0:
                return i
    return None


def label_key(label: str) -> str:
    return ' '.join(label.split()).casefold()


def links(text: str, *, _definitions=None, _images_only=False) -> tuple[list[tuple[int, str]], list[tuple[int, str]]]:
    definitions, found, issues = dict(_definitions or {}), [], []
    masked = list(text)
    for match in re.finditer(r'^ {0,3}\[([^\]\n]+)\]:[ \t]*(.*)$', text, re.MULTILINE):
        line = text.count('\n', 0, match.start()) + 1
        try:
            definitions.setdefault(label_key(match[1]), destination(match[2]))
        except ValueError as error:
            issues.append((line, str(error)))
        masked[match.start():match.end()] = blank(match.group())
    text = ''.join(masked)
    i = 0
    while i < len(text):
        if text[i] != '[' or escaped(text, i):
            i += 1
            continue
        image = i > 0 and text[i - 1] == '!' and not escaped(text, i - 1)
        if _images_only and not image:
            i += 1
            continue
        end = closing(text, i, '[', ']')
        if end is None:
            i += 1
            continue
        label = text[i + 1:end]
        line = text.count('\n', 0, i) + 1
        if not image and '![' in label:
            # A linked image has its own destination inside the outer label.
            # Share document references and preserve its original source line.
            nested, nested_issues = links(label, _definitions=definitions, _images_only=True)
            found.extend((line + nested_line - 1, target) for nested_line, target in nested)
            issues.extend((line + nested_line - 1, message) for nested_line, message in nested_issues)
        following = end + 1
        if following < len(text) and text[following] == '(':
            last = closing(text, following, '(', ')')
            if last is None:
                issues.append((line, 'Unclosed link destination.'))
            else:
                try:
                    found.append((line, destination(text[following + 1:last])))
                except ValueError as error:
                    issues.append((line, str(error)))
                end = last
        elif following < len(text) and text[following] == '[':
            last = closing(text, following, '[', ']')
            if last is not None:
                reference = label_key(text[following + 1:last] or label)
                if reference not in definitions:
                    issues.append((line, f'Undefined link reference: {reference}'))
                else:
                    found.append((line, definitions[reference]))
                end = last
        elif label_key(label) in definitions:
            found.append((line, definitions[label_key(label)]))
        i = end + 1
    return found, issues


def heading_anchors(headings: str, visible: str) -> set[str]:
    anchors = set(re.findall(r'<[^>]+\b(?:id|name)=["\']([^"\']+)["\'][^>]*>', visible))
    titles = []
    lines = headings.splitlines()
    for i, line in enumerate(lines):
        match = re.match(r' {0,3}#{1,6}[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$', line)
        if match:
            titles.append(match[1])
        elif i and lines[i - 1].strip() and re.fullmatch(r' {0,3}(?:=+|-+)[ \t]*', line):
            titles.append(lines[i - 1].strip())
    for title in titles:
        title = re.sub(r'!?\[([^\]]*)\](?:\([^)]*\)|\[[^]]*\])?', r'\1', title)
        title = re.sub(r'<[^>]*>', '', html.unescape(title)).lower()
        title = re.sub(r'(?<!\w)([*_]{1,3})(.+?)\1(?!\w)', r'\2', title)
        slug = ''.join(char for char in title if char in '-_ ' or unicodedata.category(char)[0] in 'LMN')
        slug = slug.replace(' ', '-')
        candidate, number = slug, 0
        while candidate in anchors:
            number += 1
            candidate = f'{slug}-{number}'
        anchors.add(candidate)
    return anchors


def local_path(root: Path, source: Path, target: str) -> Path:
    """Check exact spelling even on Windows, and never follow a link outside root."""
    if '\\' in target or target.startswith('/') or re.match(r'^[a-zA-Z]:', target):
        raise ValueError('Use a portable repository-relative path with forward slashes.')
    parts = list(source.relative_to(root).parent.parts)
    for part in PurePosixPath(target).parts:
        if part == '..':
            if not parts:
                raise ValueError('Local link escapes the repository.')
            parts.pop()
        elif part != '.':
            parts.append(part)
    path = root
    for part in parts:
        names = {child.name for child in path.iterdir()} if path.is_dir() else set()
        if part not in names:
            actual = next((name for name in sorted(names) if name.casefold() == part.casefold()), None)
            if actual:
                raise ValueError(f'Path case mismatch: {part!r}; actual spelling is {actual!r}.')
            raise ValueError('Local target does not exist.')
        path /= part
        if not path.resolve().is_relative_to(root):
            raise ValueError('Local link escapes the repository through a symlink.')
    return path


def powershell_issues(blocks: list[dict]) -> list[dict]:
    if os.name != 'nt':
        raise ValueError('PowerShell example parsing requires Windows; omit --powershell for local links only.')
    executable = shutil.which('pwsh') or shutil.which('powershell')
    if not executable:
        raise ValueError('PowerShell parser unavailable; install PowerShell or omit --powershell.')
    # Only parse strings into syntax trees. No supplied example is invoked.
    script = r'''
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$taskExamples = [Console]::In.ReadToEnd() | ConvertFrom-Json
$taskIssues = @()
foreach ($taskExample in $taskExamples) {
    $taskTokens = $null
    $taskErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput(
        [string]$taskExample.code, [ref]$taskTokens, [ref]$taskErrors)
    foreach ($taskError in $taskErrors) {
        $taskIssues += @{file=$taskExample.file; line=([int]$taskExample.line + $taskError.Extent.StartLineNumber - 1); message=$taskError.Message}
    }
}
ConvertTo-Json -InputObject @($taskIssues) -Depth 4 -Compress
'''
    result = subprocess.run([executable, '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
                            input=json.dumps(blocks), text=True, encoding='utf-8', capture_output=True,
                            timeout=30, check=True)
    return json.loads(result.stdout.lstrip('\ufeff'))


def verify(root: Path, *, powershell=False) -> dict:
    root = root.resolve()
    paths = [root / 'AGENTS.md', root / 'README.md']
    paths += sorted(path for path in (root / 'docs').rglob('*') if path.is_file() and path.suffix.lower() == '.md')
    paths += sorted(path for path in (root / '.agents/skills').rglob('*') if path.is_file() and path.suffix.lower() == '.md')
    report = {'schema': 1, 'root': str(root), 'files': len(paths), 'local_links': 0,
              'external_links_skipped': 0, 'issues': []}
    cache, examples = {}, []

    def parse(path):
        if path not in cache:
            if not path.resolve().is_relative_to(root):
                raise ValueError('Markdown source escapes the repository.')
            headings, visible, blocks, issues = code_mask(path.read_text(encoding='utf-8-sig'))
            found, link_issues = links(visible)
            cache[path] = (heading_anchors(headings, visible), found, blocks, issues + link_issues)
        return cache[path]

    for path in paths:
        name = path.relative_to(root).as_posix()
        try:
            path = local_path(root, root / 'README.md', name)
            _, found, blocks, issues = parse(path)
            report['issues'] += [{'file': name, 'line': line, 'message': message} for line, message in issues]
            examples += [{'file': name, **block} for block in blocks]
            for line, target in found:
                try:
                    if re.match(r'^[a-zA-Z]:', target) or target.lower().startswith('file:'):
                        raise ValueError('Use a portable repository-relative path.')
                    url = urlsplit(target)
                    if url.scheme or url.netloc:
                        report['external_links_skipped'] += 1
                        continue
                    report['local_links'] += 1
                    linked = local_path(root, path, unquote(url.path)) if url.path else path
                    if url.fragment and linked.suffix.lower() == '.md' and unquote(url.fragment) not in parse(linked)[0]:
                        raise ValueError('Markdown anchor does not exist.')
                except (OSError, ValueError, UnicodeError) as error:
                    report['issues'].append({'file': name, 'line': line, 'target': target, 'message': str(error)})
        except (OSError, ValueError, UnicodeError) as error:
            report['issues'].append({'file': name, 'line': 1, 'message': str(error)})
    report['powershell'] = {'status': 'not-requested', 'blocks': len(examples)}
    if powershell:
        try:
            issues = powershell_issues(examples)
            report['issues'] += issues
            report['powershell']['status'] = 'failed' if issues else 'passed'
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            report['powershell']['status'] = 'unavailable'
            report['issues'].append({'file': '<powershell>', 'line': 0, 'message': str(error)})
    report['status'] = 'failed' if report['issues'] else 'passed'
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT, help='Repository root; defaults to this script\'s checkout.')
    parser.add_argument('--powershell', action='store_true', help='Also parse fenced PowerShell examples on Windows; never execute them.')
    parser.add_argument('--json', action='store_true', help='Print the complete local verification report as JSON.')
    args = parser.parse_args(argv)
    report = verify(args.root, powershell=args.powershell)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f'{report["status"].upper()}: {report["files"]} Markdown files, {report["local_links"]} local links; '
              f'{report["external_links_skipped"]} external links skipped.')
        print(f'PowerShell examples: {report["powershell"]["status"]} ({report["powershell"]["blocks"]} blocks).')
        for issue in report['issues']:
            print(f'{issue["file"]}:{issue["line"]}: {issue["message"]}' +
                  (f' [{issue["target"]}]' if 'target' in issue else ''))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
