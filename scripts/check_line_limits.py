import os
import sys

MAX_LINES = 800
base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
src_dir = os.path.join(base_dir, "src")

violations = []
total_files = 0
total_lines = 0

for root, _, files in os.walk(src_dir):
    for f in files:
        if not f.endswith((".luau", ".lua")):
            continue
        total_files += 1
        filepath = os.path.join(root, f)
        relpath = os.path.relpath(filepath, base_dir)
        with open(filepath, "r", encoding="utf-8") as fh:
            line_count = len(fh.readlines())
        total_lines += line_count
        print(f"[{'PASS' if line_count <= MAX_LINES else 'FAIL'}] {line_count:>4} / {MAX_LINES} satır : {relpath}")
        if line_count > MAX_LINES:
            violations.append((relpath, line_count))

print("-" * 50)
print(f"Toplam dosya: {total_files} | Toplam satir: {total_lines}")

if violations:
    print(f"[FAIL] KURAL IHLALI: {len(violations)} dosya {MAX_LINES} satir sinirini asiyor!")
    for path, count in violations:
        print(f"  - {path}: {count} satir")
    sys.exit(1)
else:
    print(f"[PASS] TUM DOSYALAR KURALA UYGUN! (En fazla {MAX_LINES} satir kurali saglandi)")
    sys.exit(0)
