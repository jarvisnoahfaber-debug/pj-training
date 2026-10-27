#!/bin/bash
# PJ-Training-App → Formular-Tabelle → Server (beide Teilnehmer) → Schiri-Abgleich + Check-in-Übersicht. Mit Sicherung.
export PATH=$HOME/.npm-global/bin:$PATH
export XDG_RUNTIME_DIR=/run/user/$(id -u)
WSS=~/.openclaw/workspace-schiri
B=~/.openclaw/backups-pj-training-$(date +%F_%H%M); mkdir -p "$B"
cp -p ~/bin/pj-daten ~/bin/pj-checkin-vorbereitung "$WSS/AGENTS.md" "$B/" && echo "Sicherung: $B" || { echo "Sicherung fehlgeschlagen"; exit 1; }

cat > ~/bin/pj-training-holen <<'PY'
#!/usr/bin/env python3
"""Holt Einheiten aus der PJ-Training-App (Google-Formular-Tabelle im Jarvis-Drive, nur lesend)
und legt sie je Teilnehmer ab: workspace-schiri/daten/<t>/training/<datum>_<HHMM>.json (+ Protokoll mit Quittung).
Still (NO_REPLY), außer bei Fehlern."""
import importlib.machinery, importlib.util, json, os, re, subprocess, sys
SHEET = "1VB6XxYnVIwe1Nz5JFWWOKDhJgC2MhRr8G27dW7ZEL8Y"
GOG = os.path.expanduser("~/.local/bin/gog")
l = importlib.machinery.SourceFileLoader("pj", "/home/jarvis/bin/pj-daten"); s = importlib.util.spec_from_loader("pj", l)
pj = importlib.util.module_from_spec(s); l.exec_module(pj)
def env():
    p = os.path.expanduser("~/.openclaw/.env")
    if "GOG_KEYRING_PASSWORD" not in os.environ and os.path.exists(p):
        for z in open(p):
            if z.startswith("GOG_KEYRING_PASSWORD="):
                os.environ["GOG_KEYRING_PASSWORD"] = z.split("=", 1)[1].strip().strip('"')
def werte(o):
    if isinstance(o, dict):
        if "values" in o: return o["values"]
        for v in o.values():
            r = werte(v)
            if r is not None: return r
    return None
def main():
    env()
    r = subprocess.run([GOG, "--account", "jarvis.noah.faber@gmail.com", "--readonly", "-j", "sheets", "get", SHEET, "A1:G5000", "--no-input"],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        print("⚠️ pj-training-holen: " + r.stderr.strip()[:200]); return
    rows = werte(json.loads(r.stdout)) or []
    neu = 0
    for z in rows[1:]:
        z = (z + [""] * 7)[:7]
        t = z[1].strip().lower()
        if t not in ("noah", "clemens"):
            continue
        try:
            d = json.loads(z[6])
        except Exception:
            d = {"text": z[5], "datum": z[2], "art": z[3], "dauer": z[4]}
        d["_eingang"] = z[0]
        datum = str(d.get("datum") or z[2])[:10]
        if not re.fullmatch(r"\d{4}-\d\d-\d\d", datum):
            continue
        hhmm = str(d.get("start", ""))[11:16].replace(":", "") or "0000"
        ziel = os.path.join(pj.DATEN, t, "training"); os.makedirs(ziel, exist_ok=True)
        p = os.path.join(ziel, f"{datum}_{hhmm}.json")
        if os.path.exists(p):
            continue
        json.dump(d, open(p, "w"), ensure_ascii=False, indent=1)
        pj.protokoll(t, "training-app", d); neu += 1
    print("NO_REPLY")
if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"⚠️ pj-training-holen: {str(e)[:200]}")
PY
chmod 755 ~/bin/pj-training-holen

python3 - <<'PY'
import os, sys
H = os.path.expanduser
F = {"pd": H("~/bin/pj-daten"), "ci": H("~/bin/pj-checkin-vorbereitung"), "ag": H("~/.openclaw/workspace-schiri/AGENTS.md")}
T = {k: open(p).read() for k, p in F.items()}
if "Training (App" in T["pd"]:
    print("Schon eingebaut."); sys.exit(0)
ERS = {
 "pd": [('    z = zubringer_woche(t, a, b)\n',
   '    td = os.path.join(DATEN, t, "training")\n'
   '    tr = sorted(f for f in (os.listdir(td) if os.path.isdir(td) else []) if f.endswith(".json") and a.isoformat() <= f[:10] <= b.isoformat())\n'
   '    print(f"Training (App, automatisch): {len(tr)} Einheiten W{int(woche):02d}")\n'
   '    for f in tr:\n'
   '        e = lies_json(os.path.join(td, f))\n'
   '        ex = ", ".join(x.get("n", "?") for x in (e.get("ex") or [])[:6])\n'
   '        c = e.get("cardio") or {}\n'
   '        print(f"  {f[8:10]}.{f[5:7]}. {str(e.get(\'start\', \'\'))[11:16]} {e.get(\'art\', \'?\')} „{e.get(\'name\', \'\')}“ {e.get(\'dauer\', \'?\')} Min."\n'
   '              + (f" · {ex}" if ex else "") + (f" · Cardio {c.get(\'min\')} Min. {c.get(\'art\', \'\')}" if c else ""))\n'
   '    z = zubringer_woche(t, a, b)\n')],
 "ci": [('    if d.weekday() in KRAFT | FECHT:\n        tr = tl.get("training") or tl.get("fechten")\n',
   '    app = [f for f in os.listdir(os.path.join(pj.DATEN, "noah", "training")) if f.startswith(d.isoformat())] if os.path.isdir(os.path.join(pj.DATEN, "noah", "training")) else []\n'
   '    appt = []\n'
   '    for f in sorted(app):\n'
   '        e = pj.lies_json(os.path.join(pj.DATEN, "noah", "training", f)); c = e.get("cardio") or {}\n'
   '        appt.append(f"{e.get(\'art\')} {e.get(\'dauer\')} Min." + (f" + Cardio {c.get(\'min\')}" if c else "") + " (App)")\n'
   '    if d.weekday() in KRAFT | FECHT:\n        tr = "; ".join(appt) or tl.get("training") or tl.get("fechten")\n')],
}
for k, liste in ERS.items():
    for alt, neu in liste:
        if T[k].count(alt) != 1:
            print(f"ABBRUCH ({k}): Textstelle nicht eindeutig:", repr(alt[:60])); sys.exit(1)
        T[k] = T[k].replace(alt, neu)
if "import os" not in T["ci"]:
    T["ci"] = T["ci"].replace("import importlib.machinery, importlib.util, sys", "import importlib.machinery, importlib.util, os, sys", 1)
z = [x for x in T["ag"].split("\n") if x.startswith("- Morgenroutine kommt automatisch")]
NEU = ("- Training kommt automatisch aus der PJ-Training-App, für Noah UND Clemens (Zeile „Training (App)“ in `pj-daten abgleich <t> <woche>`; "
       "beim Check-in für beide ausführen). Eine App-Einheit belegt Datum, Art, Dauer, Übungen und Cardio; Angaben im Check-in damit abgleichen. "
       "Fehlt eine Einheit in der App, nachfragen statt automatisch „nicht erfüllt“.")
if len(z) == 1 and "PJ-Training-App" not in T["ag"]:
    T["ag"] = T["ag"].replace(z[0], z[0] + "\n" + NEU)
elif "PJ-Training-App" not in T["ag"]:
    print("ABBRUCH (AGENTS): Morgenroutine-Zeile fehlt"); sys.exit(1)
for k, p in F.items(): open(p, "w").write(T[k])
print("Eingebaut (pj-daten, pj-checkin-vorbereitung, Schiri-AGENTS.md).")
PY
[ $? -eq 0 ] || { echo "Nichts geändert."; exit 1; }
for f in pj-daten pj-checkin-vorbereitung pj-training-holen; do python3 -c "import ast; ast.parse(open('/home/jarvis/bin/$f').read())" || {
  cp -p "$B/pj-daten" "$B/pj-checkin-vorbereitung" ~/bin/; cp -p "$B/AGENTS.md" "$WSS/"; echo "Syntaxfehler in $f → zurückgespielt"; exit 1; }; done
rm -rf ~/bin/__pycache__
echo "=== Testlauf Abholen"; ~/bin/pj-training-holen; ls ~/.openclaw/workspace-schiri/daten/*/training/ 2>&1 | head
echo "=== Abgleich-Kopf (noah, W01)"; ~/bin/pj-daten abgleich noah 1 2>&1 | head -4
echo "=== Abgleich-Kopf (clemens, W01)"; ~/bin/pj-daten abgleich clemens 1 2>&1 | head -3
echo "=== Check-in-Übersicht"; ~/bin/pj-checkin-vorbereitung 1 | head -6
echo "=== Job stündlich :10"
openclaw cron list --json | grep -q "PJ Training holen" || openclaw cron add --name "PJ Training holen (stündlich)" --agent schiri --session isolated --tz Europe/Vienna \
  --cron "10 * * * *" --command-argv '["/home/jarvis/bin/pj-training-holen"]' --timeout-seconds 90 \
  --announce --channel telegram --account schiri --to 1005296724 | grep -E '"(id|name)"'
openclaw cron list | grep -i "training holen"
