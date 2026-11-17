#!/usr/bin/env python3
"""ffnx_offset_fix.py - the offset build's FFNx casts, from the compiler's own list.

An arm64 build (FF7_ARCH=arm64, guest memory at g_mem_base) compiled with
-Wint-to-pointer-cast -Wpointer-to-int-cast warns at every C-style cast between a 32-bit game
address and a pointer. Each data one is wrapped:
    (T *)expr          -> (T *)GPTR(expr)      a game address used as memory
    (uint32_t)pointer  -> (uint32_t)GVA(pointer)   a pointer into game memory handed back
Casts to or from function pointers are left alone (code addresses are not memory).

The changes are written as whole-line edits to tools/ffnx_offset_edits.json, which
tools/ffnx_edit_mac.py applies after its own edits, so a fresh setup reproduces them.

    python3 tools/ffnx_offset_fix.py build-arm64.log
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FFNX = os.path.join(ROOT, 'external', 'FFNx', 'src')
OUT = os.path.join(ROOT, 'tools', 'ffnx_offset_edits.json')

W = re.compile(r"(/[^ :]+/external/FFNx/src/[^:]+):(\d+):(\d+): warning: cast (to|from) (smaller integer type )?'([^']*)' from (smaller integer type )?'([^']*)'")
W2 = re.compile(r"(/[^ :]+/external/FFNx/src/[^:]+):(\d+):(\d+): warning: cast to smaller integer type '([^']*)' from '([^']*)'")


def skip_ws(s, i):
    while i < len(s) and s[i] in ' \t': i += 1
    return i


def match_group(s, i, open_c, close_c):
    depth = 0
    while i < len(s):
        if s[i] == open_c: depth += 1
        elif s[i] == close_c:
            depth -= 1
            if depth == 0: return i + 1
        elif s[i] in '"\'':
            q = s[i]; i += 1
            while i < len(s) and s[i] != q:
                if s[i] == '\\': i += 1
                i += 1
        i += 1
    return -1


def cast_end(s, i):
    """s[i] is the '(' of a C-style cast: the index just past its ')'."""
    return match_group(s, i, '(', ')')


def operand_end(s, i):
    """A unary operand starting at i: prefix ops, a primary, then postfix ops."""
    i = skip_ws(s, i)
    while i < len(s) and s[i] in '&*!~-+' and not s.startswith('->', i): i = skip_ws(s, i + 1)
    if i >= len(s): return -1
    if s[i] == '(':
        j = match_group(s, i, '(', ')')
        # a nested cast: (A)(B)x
        k = skip_ws(s, j)
        inner = s[i + 1:j - 1].strip()
        if k < len(s) and (s[k].isalnum() or s[k] in '_(&*') and re.fullmatch(r'(const\s+)?[\w:<> ]+\s*\**', inner):
            return operand_end(s, k)
        i = j
    else:
        m = re.match(r'[A-Za-z_]\w*(::\w+)*|0[xX][0-9A-Fa-f]+[uUlL]*|\d+[uUlL]*', s[i:])
        if not m: return -1
        i += m.end()
    while i < len(s):
        if s.startswith('->', i):
            m = re.match(r'->\s*[A-Za-z_]\w*', s[i:]); i += m.end()
        elif s[i] == '.' and i + 1 < len(s) and (s[i + 1].isalpha() or s[i + 1] == '_'):
            m = re.match(r'\.\s*[A-Za-z_]\w*', s[i:]); i += m.end()
        elif s[i] == '[': i = match_group(s, i, '[', ']')
        elif s[i] == '(': i = match_group(s, i, '(', ')')
        elif s[i] == '<' and re.match(r'<[\w:, *]+>\s*\(', s[i:]):   # a template call
            j = s.index('>', i) + 1; i = j
        else: break
        if i < 0: return -1
    return i


def main():
    log = open(sys.argv[1], encoding='utf-8', errors='replace').read().split('\n')
    sites = {}   # file -> {line: set((col, kind))}
    for l in log:
        m = re.search(r"(/[^ :]+/external/FFNx/src/[^:]+):(\d+):(\d+): warning: cast to '([^']*)' from smaller integer type", l)
        if m and '(*)(' not in m.group(4):
            sites.setdefault(m.group(1), {}).setdefault(int(m.group(2)), set()).add((int(m.group(3)), 'GPTR'))
            continue
        m = re.search(r"(/[^ :]+/external/FFNx/src/[^:]+):(\d+):(\d+): warning: cast to smaller integer type '[^']*' from '([^']*)'", l)
        if m and '(*)(' not in m.group(4) and '(*)' not in m.group(4).replace('(*)[', ''):
            sites.setdefault(m.group(1), {}).setdefault(int(m.group(2)), set()).add((int(m.group(3)), 'GVA'))
            continue
        m = re.search(r"(/[^ :]+/external/FFNx/src/[^:]+):(\d+):(\d+): warning: cast to '([^']*)' from smaller integer type", l)
    edits = json.load(open(OUT)) if os.path.exists(OUT) else []
    known = {(e[0], e[1]) for e in edits}
    done = failed = 0
    for path, lines in sites.items():
        rel = os.path.relpath(path, FFNX)
        text = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
        for ln, cols in lines.items():
            old = text[ln - 1]
            new = old
            for col, kind in sorted(cols, reverse=True):   # right to left: earlier columns stay valid
                i = col - 1
                if i >= len(new) or new[i] != '(':
                    print(f'  ? {rel}:{ln}:{col} not a cast: {new.strip()[:90]}'); failed += 1; continue
                ce = cast_end(new, i)
                k = skip_ws(new, ce)
                if new.startswith('GPTR(', k) or new.startswith('GVA(', k): continue
                oe = operand_end(new, k)
                if oe < 0:
                    print(f'  ? {rel}:{ln}:{col} operand: {new.strip()[:90]}'); failed += 1; continue
                new = new[:k] + kind + '(' + new[k:oe] + ')' + new[oe:]
                done += 1
            if new != old:
                text[ln - 1] = new
                if (rel, old) not in known:
                    edits.append([rel, old, new]); known.add((rel, old))
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(text))
    json.dump(edits, open(OUT, 'w'), indent=0, ensure_ascii=False)
    print(f'ffnx_offset_fix: {done} casts wrapped, {failed} left for a look; {len(edits)} line edits in {os.path.relpath(OUT, ROOT)}')


if __name__ == '__main__':
    main()
