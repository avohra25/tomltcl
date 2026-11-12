#!/usr/bin/env python3
"""Differential check of tomltcl against Python's tomllib (3.11+).

Generates random small documents that mix [headers], [[arrays of tables]],
dotted keys and inline tables -- the part of TOML where the rules about which
table may be extended from where are easiest to get wrong -- and checks that
tomltcl accepts exactly the documents tomllib accepts, with the same result.

    python3 tests/differential.py [--seed N] [--docs N]

Not part of tests/all.tcl, since it needs Python; run it after touching the
table-definition code.
"""
import argparse, json, os, random, subprocess, sys, tempfile, tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DRIVER = r'''
source [file join [lindex $argv 0] tomltcl.tcl]
set f [open [lindex $argv 1]]; fconfigure $f -encoding utf-8
set docs [lindex [tomltcl::json_decode [read $f]] 1]; close $f
set out {}
foreach d $docs {
    if {[catch {tomltcl::to_tagged_json [tomltcl::parse [lindex $d 1]]} r]} {
        lappend out "ERR $r"
    } else { lappend out $r }
}
fconfigure stdout -encoding utf-8
puts -nonewline [join $out \x1e]
'''

KEYS = ["a", "b", "c", '"a"', "'b'"]

def key(rng):
    return ".".join(rng.choice(KEYS) for _ in range(rng.randint(1, 3)))

def value(rng):
    r = rng.random()
    if r < 0.45: return str(rng.randint(0, 9))
    if r < 0.65: return "{ %s = %d }" % (key(rng), rng.randint(0, 9))
    if r < 0.75: return "[1, { x = 2 }]"
    if r < 0.85: return "{}"
    return '"s"'

def document(rng):
    lines = []
    for _ in range(rng.randint(1, 7)):
        r = rng.random()
        if r < 0.25: lines.append("[%s]" % key(rng))
        elif r < 0.4: lines.append("[[%s]]" % key(rng))
        else: lines.append("%s = %s" % (key(rng), value(rng)))
    return "\n".join(lines) + "\n"

def tag(v):
    if isinstance(v, dict): return {k: tag(x) for k, x in v.items()}
    if isinstance(v, list): return [tag(x) for x in v]
    if isinstance(v, str): return {"type": "string", "value": v}
    return {"type": "integer", "value": str(v)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--docs", type=int, default=2000)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    docs = [document(rng) for _ in range(args.docs)]
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(docs, f)
        path = f.name
    try:
        res = subprocess.run(["tclsh", "/dev/stdin", ROOT, path], input=DRIVER,
                             capture_output=True, text=True, encoding="utf-8")
    finally:
        os.unlink(path)
    if res.returncode != 0:
        sys.exit("tclsh failed: " + res.stderr)
    outs = res.stdout.split("\x1e")
    bad = accepted = 0
    for doc, out in zip(docs, outs):
        try:
            want = tag(tomllib.loads(doc))
        except tomllib.TOMLDecodeError:
            want = None
        got = None if out.startswith("ERR") else json.loads(out)
        accepted += got is not None
        if want != got:
            bad += 1
            if bad <= 5:
                print("MISMATCH:\n" + doc + "  tomllib: %s\n  tomltcl: %s\n" % (
                    "error" if want is None else json.dumps(want), out[:300]))
    print("%d documents, %d accepted, %d mismatches" % (len(docs), accepted, bad))
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
