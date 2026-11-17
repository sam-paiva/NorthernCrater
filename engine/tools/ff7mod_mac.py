#!/usr/bin/env python3
"""ff7mod_mac.py - 7th Heaven mods for FF7Recomp on macOS (the Android launcher's Mods screen,
from the command line). Mods live in ~/Library/Application Support/FF7Recomp/mods and the game
reads mods/profile.xml at start-up (src/mods/mods.h); priority is the profile's order, first wins.

  ff7mod_mac.py install <file.7z|file.iro|folder>   add a mod (enabled, lowest priority)
  ff7mod_mac.py list                                 mods in priority order
  ff7mod_mac.py enable|disable <name>                keep the mod, switch it on/off
  ff7mod_mac.py up|down <name>                       move one place in priority
  ff7mod_mac.py option <name> <OptionID> <value>     a mod.xml config option
  ff7mod_mac.py remove <name>                        delete the mod

A .7z is unpacked with build/tools/ff7mod-un7z; as on Android, the .iro inside it is kept, or
else the folder holding mod.xml, or else the whole archive.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.expanduser(os.environ.get('FF7_HOME', '~/Library/Application Support/FF7Recomp'))
MODS = os.path.join(BASE, 'mods')
PROFILE = os.path.join(MODS, 'profile.xml')
UN7Z = os.path.join(ROOT, 'build', 'tools', 'ff7mod-un7z')
VAR = os.path.join(ROOT, 'external', '7th-Heaven', 'AppUI', 'Resources', '7thHeaven.var')


def load():
    if not os.path.isfile(PROFILE):
        return ET.Element('Profile', Language='en')
    return ET.parse(PROFILE).getroot()


def save(prof):
    os.makedirs(MODS, exist_ok=True)
    ET.indent(prof)
    ET.ElementTree(prof).write(PROFILE, encoding='utf-8', xml_declaration=True)
    if os.path.isfile(VAR) and not os.path.isfile(os.path.join(MODS, '7thHeaven.var')):
        shutil.copy(VAR, MODS)


def find(prof, name):
    n = name.lower()
    hits = [m for m in prof.findall('Mod') if n in m.get('Path', '').lower()]
    if len(hits) != 1:
        sys.exit(f'{"no" if not hits else "more than one"} mod matches "{name}" (see: list)')
    return hits[0]


def first_named(top, fname):
    for d, _, files in os.walk(top):
        for f in files:
            if f.lower() == fname.lower():
                return os.path.join(d, f)
    return None


def first_iro(top):
    for d, _, files in os.walk(top):
        for f in sorted(files):
            if f.lower().endswith('.iro'):
                return os.path.join(d, f)
    return None


def install(src):
    src = os.path.abspath(src)
    name = os.path.splitext(os.path.basename(src.rstrip('/')))[0]
    os.makedirs(MODS, exist_ok=True)
    if src.lower().endswith('.7z'):
        if not os.path.isfile(UN7Z):
            sys.exit('build/tools/ff7mod-un7z is missing (see docs/MACOS.md)')
        tmp = tempfile.mkdtemp(dir=MODS, prefix='.unpack-')
        try:
            subprocess.run([UN7Z, src, tmp], check=True)
            iro = first_iro(tmp)
            mx = first_named(tmp, 'mod.xml')
            if iro:
                item, dest = iro, os.path.join(MODS, os.path.basename(iro))
            elif mx:
                item, dest = os.path.dirname(mx), os.path.join(MODS, name)
            else:
                item, dest = tmp, os.path.join(MODS, name)
            if os.path.exists(dest):
                sys.exit(f'already installed: {dest}')
            shutil.move(item, dest)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    else:
        dest = os.path.join(MODS, os.path.basename(src.rstrip('/')))
        if os.path.exists(dest):
            sys.exit(f'already installed: {dest}')
        (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, dest)
    prof = load()
    ET.SubElement(prof, 'Mod', Path=os.path.basename(dest))
    save(prof)
    print(f'installed {os.path.basename(dest)}')


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd, args = argv[1], argv[2:]
    prof = load()
    if cmd == 'install' and len(args) == 1:
        install(args[0])
    elif cmd == 'list':
        for i, m in enumerate(prof.findall('Mod'), 1):
            on = m.get('Enabled', 'true').lower() != 'false'
            opts = ' '.join(f'{o.get("ID")}={o.get("Value")}' for o in m.findall('Option'))
            print(f'{i:2}. [{"x" if on else " "}] {m.get("Path")}  {opts}')
    elif cmd in ('enable', 'disable') and len(args) == 1:
        m = find(prof, args[0])
        if cmd == 'enable':
            m.attrib.pop('Enabled', None)
        else:
            m.set('Enabled', 'false')
        save(prof)
    elif cmd in ('up', 'down') and len(args) == 1:
        m = find(prof, args[0])
        mods = prof.findall('Mod')
        i = mods.index(m)
        j = i - 1 if cmd == 'up' else i + 1
        if 0 <= j < len(mods):
            prof.remove(m)
            prof.insert(list(prof).index(mods[j]) + (0 if cmd == 'up' else 1), m)
        save(prof)
    elif cmd == 'option' and len(args) == 3:
        m = find(prof, args[0])
        o = next((o for o in m.findall('Option') if o.get('ID', '').lower() == args[1].lower()), None)
        if o is None:
            o = ET.SubElement(m, 'Option', ID=args[1])
        o.set('Value', args[2])
        save(prof)
    elif cmd == 'remove' and len(args) == 1:
        m = find(prof, args[0])
        p = os.path.join(MODS, m.get('Path'))
        prof.remove(m)
        save(prof)
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.exists(p):
            os.remove(p)
        print(f'removed {m.get("Path")}')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
