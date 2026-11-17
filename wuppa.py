#!/usr/bin/env python3
"""Wuppa – Whole Uppa Puppa Package. Ett paket, tre kusiner:

  Uppa   håller dina PowerShell- och Microsoft-CLI-verktyg uppdaterade   github.com/pipebreak33/uppa
  Puppa  M365-adminuppgifter i PowerShell med några knapptryck          github.com/pipebreak33/puppa
  Muppa  flyttar en dator från lokal AD till Entra ID (skript + lista)   github.com/pipebreak33/muppa

  wuppa                    meny
  wuppa status             vilka kusiner som finns och om de kan uppdateras
  wuppa install [namn …]   installera kusiner som saknas (utan namn: alla som saknas)
  wuppa update [namn …]    uppdatera kusinerna som har en nyare version, och Wuppa själv
  wuppa uppa|puppa|muppa … kör en kusin (allt efter namnet skickas vidare)
  wuppa self-update        uppdatera bara Wuppa

Enbart standardbiblioteket, Python 3.8+.
"""
from __future__ import annotations

import json
import os
import random
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

VERSION = "1.0.0"
HOME = Path.home()
DIR = HOME / ".wuppa"
CONFIG = DIR / "config.json"
IS_WIN = os.name == "nt"
REPO_OWNER = "pipebreak33"

# Kusinerna installerar sig själva i ~/.<namn>; se till att deras kommandon hittas även innan PATH laddats om.
if IS_WIN:
    _LA = os.environ.get("LOCALAPPDATA", str(HOME / "AppData" / "Local"))
    EXTRA_PATH = [str(HOME / f".{n}" / "bin") for n in ("wuppa", "uppa", "puppa", "muppa")] + \
                 [os.path.join(_LA, "Microsoft", "WindowsApps")]
else:
    EXTRA_PATH = [str(HOME / ".local/bin"), "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
os.environ["PATH"] = os.pathsep.join(dict.fromkeys(os.environ.get("PATH", "").split(os.pathsep) + EXTRA_PATH))


class Cousin:
    def __init__(self, key, name, logo, color, desc):
        self.key, self.name, self.logo, self.color, self.desc = key, name, logo, color, desc
        self.current = None      # installerad version (None = saknas)
        self.latest = None       # version på GitHub (None = gick inte att nå)

    @property
    def installed(self):
        return self.current is not None

    @property
    def outdated(self):
        return self.installed and newer(self.latest, self.current)


COUSINS = [
    Cousin("uppa", "Uppa", "U›", "38;5;49", "håller PowerShell- och Microsoft-verktygen uppdaterade"),
    Cousin("puppa", "Puppa", "P›", "38;5;75", "M365-admin i PowerShell med några knapptryck"),
    Cousin("muppa", "Muppa", "M›", "38;5;177", "flyttar en dator från lokal AD till Entra ID"),
]
BY_KEY = {k.key: k for k in COUSINS}


# ───────────────────────────── terminal ─────────────────────────────
def _win_console():
    """UTF-8 + ANSI-färger i Windows-konsolen (Windows Terminal, conhost, VS Code)."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    try:
        import ctypes
        k = ctypes.windll.kernel32
        k.SetConsoleOutputCP(65001)
        h = k.GetStdHandle(-11)
        mode = ctypes.c_uint32()
        if k.GetConsoleMode(h, ctypes.byref(mode)):
            k.SetConsoleMode(h, mode.value | 0x0004)       # ENABLE_VIRTUAL_TERMINAL_PROCESSING
    except Exception:
        pass


if IS_WIN:
    _win_console()
TTY = sys.stdout.isatty()
COLOR = TTY and "NO_COLOR" not in os.environ
ANIM = TTY and not os.environ.get("WUPPA_NO_ANIM") and not os.environ.get("CI")
DIRTY = False          # något har skrivits ut som användaren bör hinna läsa innan skärmen töms


def c(code, s):
    return f"\033[{code}m{s}\033[0m" if COLOR else s


def green(s): return c("38;5;42", s)
def yellow(s): return c("38;5;214", s)
def red(s): return c("38;5;203", s)
def dim(s): return c("2", s)
def bold(s): return c("1", s)
def accent(s): return c("38;5;220", s)


ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")


def vlen(s):
    return len(ANSI.sub("", s))


def pad(s, n):
    return s + " " * max(0, n - vlen(s))


def cut(s, n):
    s = ANSI.sub("", s).replace("\t", " ").strip()
    return s if len(s) <= n else s[: max(0, n - 1)] + "…"


def width():
    return max(20, shutil.get_terminal_size((100, 30)).columns)


def term_size():
    t = shutil.get_terminal_size((100, 30))
    return t.columns, t.lines


def fit(s, w=None):
    """Klipp en (färgad) rad så att den aldrig radbryts i terminalen."""
    w = max(8, (w or width()) - 1)
    if vlen(s) <= w:
        return s
    out, n, i = [], 0, 0
    while i < len(s) and n < w - 1:
        m = ANSI.match(s, i)
        if m:
            out.append(m.group(0))
            i = m.end()
            continue
        out.append(s[i])
        n += 1
        i += 1
    return "".join(out) + ("\033[0m" if COLOR else "") + "…"


class Live:
    """Ritar om ett block rader på plats, även efter att fönstret ändrat storlek."""

    def __init__(self):
        self.prev = []

    def _up(self):
        w = width()
        return sum(max(1, -(-n // w)) for n in self.prev)

    def draw(self, lines):
        w = width()
        lines = [fit(l, w) for l in lines]
        sys.stdout.write("\r" + "\033[F" * self._up() + "\033[J" + "".join(l + "\n" for l in lines))
        sys.stdout.flush()
        self.prev = [vlen(l) for l in lines]

    def clear(self):
        sys.stdout.write("\r" + "\033[F" * self._up() + "\033[J")
        sys.stdout.flush()
        self.prev = []


class Keys:
    """Rå tangentläsning. Windows: msvcrt. macOS/Linux: termios + select. read() ger None vid timeout."""

    def __enter__(self):
        if IS_WIN:
            import msvcrt
            self.m = msvcrt
        else:
            import termios
            import tty
            self.fd = sys.stdin.fileno()
            self.old = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)
        sys.stdout.write("\033[?25l")
        sys.stdout.flush()
        return self

    def __exit__(self, *a):
        if not IS_WIN:
            import termios
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old)
        sys.stdout.write("\033[?25h")
        sys.stdout.flush()

    def read(self, timeout=0.25):
        if IS_WIN:
            end = time.time() + timeout
            while time.time() < end:
                if self.m.kbhit():
                    ch = self.m.getwch()
                    if ch in ("\x00", "\xe0"):
                        return {"H": "\x1b[A", "P": "\x1b[B", "K": "\x1b[D", "M": "\x1b[C"}.get(self.m.getwch(), "")
                    return ch
                time.sleep(0.02)
            return None
        import select
        r, _, _ = select.select([self.fd], [], [], timeout)
        return os.read(self.fd, 3).decode(errors="ignore") if r else None


# ───────────────────────────── helpers ─────────────────────────────
def which(cmd):
    return shutil.which(cmd)


def run(cmd, timeout=60):
    """(rc, stdout, stderr). Kastar aldrig för ett saknat kommando."""
    exe = which(cmd[0]) if IS_WIN and not os.path.isabs(cmd[0]) else None
    try:
        p = subprocess.run([exe or cmd[0]] + list(cmd[1:]), capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", f"{cmd[0]}: hittades inte"
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")[:4])


def newer(latest, current):
    try:
        return bool(latest) and vtuple(latest) > vtuple(current)
    except Exception:
        return False


def config():
    try:
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception:
        return {}


def repo_for(name):
    """GitHub-repo och gren för ett verktyg. Styr med t.ex. PUPPA_REPO/PUPPA_BRANCH eller config.json {"repos": …}."""
    env = name.upper()
    repo = os.environ.get(env + "_REPO") or (config().get("repos") or {}).get(name) or f"{REPO_OWNER}/{name}"
    return repo, os.environ.get(env + "_BRANCH") or "main"


def github_version(name):
    """VERSION i <namn>.py på GitHub (raw), eller None om det inte går att nå."""
    repo, branch = repo_for(name)
    try:
        req = urllib.request.Request(f"https://raw.githubusercontent.com/{repo}/{branch}/{name}.py",
                                     headers={"User-Agent": "wuppa/" + VERSION, "Cache-Control": "no-cache"})
        with urllib.request.urlopen(req, timeout=15) as r:
            text = r.read().decode("utf-8", "replace")
    except Exception:
        return None
    m = re.search(r'^VERSION\s*=\s*["\']([^"\']+)', text, re.M)
    return m.group(1) if m else None


def installed_version(name):
    if not which(name):
        return None
    rc, out, err = run([name, "--version"], timeout=30)
    m = re.search(r"\d+\.\d+(\.\d+)?", out + err)
    return m.group(0) if m else "?"


def installer_cmd(name):
    """Kommandot som kör verktygets egen installationsrad (samma rad som man klistrar in själv).
    Finns en lokal checkout (config.json {"local": {"puppa": "/sökväg"}}) används den i stället."""
    local = (config().get("local") or {}).get(name)
    if local:
        script = Path(local).expanduser() / ("install.ps1" if IS_WIN else "install.sh")
        if IS_WIN:
            return ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
        return ["sh", str(script)]
    repo, branch = repo_for(name)
    base = f"https://raw.githubusercontent.com/{repo}/{branch}"
    if IS_WIN:
        return ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", f"irm {base}/install.ps1 | iex"]
    # Ladda ner först: med "curl | sh" skulle ett nätfel se ut som en lyckad installation
    return ["sh", "-c", f'f="$(mktemp)" && curl -fsSL {base}/install.sh -o "$f" && sh "$f"; rc=$?; '
                        f'rm -f "$f"; exit $rc']


def run_installer(name, env=None):
    """Kör installern synligt (utdata direkt i terminalen). True om den lyckades."""
    cmd = installer_cmd(name)
    exe = which(cmd[0]) or cmd[0]
    try:
        return subprocess.call([exe] + cmd[1:], env={**os.environ, **(env or {})}) == 0
    except FileNotFoundError:
        print("  " + red("✘") + f" {cmd[0]} hittades inte")
        return False


def scan():
    """Fyll i installerad och senaste version för kusinerna och Wuppa själv, parallellt."""
    jobs = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        for k in COUSINS:
            jobs[(k.key, "cur")] = ex.submit(installed_version, k.key)
            jobs[(k.key, "lat")] = ex.submit(github_version, k.key)
        jobs[("wuppa", "lat")] = ex.submit(github_version, "wuppa")
    for k in COUSINS:
        k.current = jobs[(k.key, "cur")].result()
        k.latest = jobs[(k.key, "lat")].result()
    return jobs[("wuppa", "lat")].result()


# ───────────────────────────── Wuppa, maskoten ─────────────────────────────
# Wuppa är ett W, storkusin till U:et, P:et och M:et. Ansiktet sitter mellan W:ets armar.
EYES = {"happy": " ◕   ◕ ", "blink": " ─   ─ ", "left": "◕   ◕  ", "right": "  ◕   ◕", "look": "◔   ◔  ",
        "sad": " ◕   ◕ ", "proud": " ^   ^ ", "wow": " ◕   ◕ ", "worry": " ◔   ◔ ", "wait": " ◕   ◕ "}
MOUTH = {"happy": "   ‿   ", "blink": "   ‿   ", "left": "  ‿    ", "right": "    ‿  ", "look": "  ‿    ",
         "sad": "   ⁀   ", "proud": "   ◡   ", "wow": "   o   ", "worry": "   ~   ", "wait": "   ─   "}
ART = ["██       ██", "██{e}██", "██{m}██", "██▄ ▄█▄ ▄██", " ▀██▀ ▀██▀ "]
SHADE = ["38;5;228", "38;5;221", "38;5;220", "38;5;214", "38;5;208"]     # ljus topp → mörkare botten
SAD_SHADE = ["38;5;187", "38;5;180", "38;5;144", "38;5;137", "38;5;101"]
ART_W = 11
LOGO = "W›"
JOKES = [
    "Whole Uppa Puppa Package. Muppa kom inte med i förkortningen, men har bästa platsen i menyn.",
    "Jag är ett W. Två U bredvid varandra. Dubbelt så uppdaterad.",
    "Ett paket, tre kusiner, noll beroenden.",
    "Uppa uppdaterar, Puppa administrerar, Muppa migrerar. Jag håller ordning på släkten.",
    "Kör samma rad igen så uppdateras allt. Det är hela tricket.",
    "Jag har inga egna moduler. Jag har kusiner.",
]


def wuppa_art(mood="happy"):
    e, m = EYES.get(mood, EYES["happy"]), MOUTH.get(mood, MOUTH["happy"])
    sh = SAD_SHADE if mood == "sad" else SHADE

    def mid(k, inner):
        return c(sh[k], "██") + bold(inner) + c(sh[k], "██")
    return [c(sh[0], ART[0]), mid(1, e), mid(2, m), c(sh[3], ART[3]), c(sh[4], ART[4])]


def wrap(msg, w, maxl=4):
    lines, cur = [], ""
    for word in ANSI.sub("", msg).split():
        if cur and len(cur) + 1 + len(word) > w:
            lines.append(cur)
            cur = word
        else:
            cur = (cur + " " + word).strip()
    if cur:
        lines.append(cur)
    if len(lines) > maxl:
        lines = lines[:maxl]
        lines[-1] = cut(lines[-1] + " …", w)
    return [cut(l, w) for l in lines] or [""]


def frame(msg="", mood="happy", lift=0, top="", sub=""):
    """Maskot + pratbubbla. Under 46 kolumner döljs maskoten."""
    w = width()
    if w < 46:
        lines = []
        if msg:
            for k, l in enumerate(wrap(msg, w - 6, 4)):
                lines.append((f"  {accent(bold(LOGO))} " if k == 0 else "     ") + l)
        if sub:
            lines.append("     " + dim(cut(sub, w - 7)))
        return lines
    rows = [""] * 7
    for k, r in enumerate(wuppa_art(mood)):
        rows[k + 1 - lift] = r
    if top and not rows[0]:
        rows[0] = top
    bub = []
    if msg:
        lines = wrap(msg, max(14, min(60, w - 22)), 4)
        iw = max(len(l) for l in lines)
        bub = [dim("╭" + "─" * (iw + 2) + "╮")] + \
              [dim("│ ") + l + " " * (iw - len(l)) + dim(" │") for l in lines] + \
              [dim("╰" + "─" * (iw + 2) + "╯")]
    res = []
    for k in range(7):
        line = "  " + pad(rows[k], ART_W + 1)
        if 0 <= k - 1 < len(bub):
            line += " " + (accent("◂ ") if k == 2 else "  ") + bub[k - 1]
        elif sub and k - 1 == len(bub):
            line += "    " + dim(cut(sub, w - ART_W - 9))
        res.append(fit(line, w))
    while res and not ANSI.sub("", res[-1]).strip():
        res.pop()
    while res and not ANSI.sub("", res[0]).strip():
        res.pop(0)
    return res


def say(msg, mood="happy", sub=""):
    global DIRTY
    DIRTY = True
    if TTY:
        print("\n".join(frame(msg, mood, sub=sub)))
    else:
        print(f"  {LOGO} {msg}")


def idle_mood(t):
    """Blinkar då och då, tittar runt ibland."""
    if t % 4.1 < 0.16:
        return "blink"
    return {2: "left", 5: "right"}.get(int(t / 2.3) % 7, "happy")


def celebrate(msg):
    global DIRTY
    DIRTY = True
    if not ANIM:
        return say(msg, "proud")
    cols = ["38;5;220", "38;5;49", "38;5;75", "38;5;177", "38;5;227"]   # Wuppa + kusinernas färger
    live = Live()
    sys.stdout.write("\033[?25l")
    try:
        for f in range(14):
            top = "".join(c(random.choice(cols), random.choice("✦✧⋆·*")) if random.random() < .35 else " "
                          for _ in range(ART_W + 1))
            live.draw(frame(msg, "proud" if f % 5 else "blink", lift=f % 2, top=top))
            time.sleep(0.09)
        live.draw(frame(msg, "proud"))
    finally:
        sys.stdout.write("\033[?25h")
        sys.stdout.flush()


class Spinner:
    """Wuppa svävar och blinkar medan kusinerna räknas in."""

    def __init__(self, msg):
        self.msg = msg
        self.stop = threading.Event()
        self.t = threading.Thread(target=self.loop, daemon=True)
        self.live = Live()

    def __enter__(self):
        if ANIM:
            sys.stdout.write("\033[?25l")
            self.t.start()
        return self

    def loop(self):
        t0 = time.time()
        while not self.stop.is_set():
            t = time.time() - t0
            self.live.draw(frame(self.msg, idle_mood(t), lift=int(t * 2.5) % 2))
            self.stop.wait(0.12)

    def __exit__(self, *a):
        if ANIM:
            self.stop.set()
            self.t.join()
            self.live.clear()
            sys.stdout.write("\033[?25h")
            sys.stdout.flush()


def pause():
    if sys.stdin.isatty():
        try:
            input(dim("\n   enter för att fortsätta "))
        except (EOFError, KeyboardInterrupt):
            print()


def new_screen():
    """Töm skärmen inför en meny. Har något just skrivits ut får man läsa klart först."""
    global DIRTY
    if DIRTY:
        pause()
    DIRTY = False
    if TTY:
        sys.stdout.write("\033[H\033[2J")
        sys.stdout.flush()


# ───────────────────────────── status ─────────────────────────────
def cousin_line(k, w=None, desc=True):
    w = w or width()
    if not k.installed:
        mark, ver = dim("○"), dim("saknas" + (f" · {k.latest} finns" if k.latest else ""))
    elif k.outdated:
        mark, ver = yellow("●"), f"{k.current} {dim('→')} {yellow(k.latest)}"
    else:
        mark, ver = green("●"), dim(k.current)
    head = f"  {mark} {c(k.color, bold(k.logo))} {pad(bold(k.name), 6)} "
    if w < 58 or not desc:
        return head + ver
    return head + pad(ver, 18) + "  " + dim(cut(k.desc, max(10, w - 40)))


def status_lines(self_latest=None, desc=True):
    lines = [cousin_line(k, desc=desc) for k in COUSINS]
    if newer(self_latest, VERSION):
        lines.append(f"  {yellow('●')} {accent(bold(LOGO))} {pad(bold('Wuppa'), 6)} {VERSION} {dim('→')} "
                     f"{yellow(self_latest)}")
    return lines


def greeting(self_latest):
    missing = [k.name for k in COUSINS if not k.installed]
    old = [k.name for k in COUSINS if k.outdated] + (["jag själv"] if newer(self_latest, VERSION) else [])
    if missing and len(missing) == len(COUSINS):
        return ("Hej! Jag är Wuppa. Jag håller ihop kusinerna Uppa, Puppa och Muppa, men ingen av dem är "
                "installerad än. Ska vi hämta hem dem?"), "wow"
    if missing:
        return (f"Hej! Jag är Wuppa. {join_names(missing)} saknas fortfarande i släkten. "
                f"Ska jag installera {'den' if len(missing) == 1 else 'dem'}?"), "worry"
    if old:
        return (f"Hej! Jag är Wuppa. Det finns nytt för {join_names(old)}. Ska vi wuppa?"), "wow"
    joke = (" " + random.choice(JOKES)) if width() >= 80 else ""    # smalt fönster: bubblan ska inte klippas
    return "Hej! Jag är Wuppa. Alla tre kusinerna är hemma och fräscha." + joke, "happy"


def join_names(names):
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " och " + names[-1]


# ───────────────────────────── kommandon ─────────────────────────────
def pick_names(names, default):
    if not names:
        return default
    bad = [n for n in names if n.lower() not in BY_KEY]
    if bad:
        raise SystemExit(f"  okänd kusin: {', '.join(bad)} (välj bland uppa, puppa, muppa)")
    return [BY_KEY[n.lower()] for n in dict.fromkeys(names)]


def do_install(targets, verb="Installerar"):
    """Kör kusinernas egna installers en i taget. Returnerar listan som misslyckades."""
    failed = []
    for k in targets:
        print()
        print(fit(f"  {c(k.color, bold(k.logo))} {bold(verb + ' ' + k.name)}"))
        if not run_installer(k.key):
            failed.append(k)
            print("  " + red("✘") + f" {k.name} gick inte att {'installera' if verb == 'Installerar' else 'uppdatera'}.")
    return failed


def report(done, failed, what):
    if failed:
        say(f"{join_names([k.name for k in failed])} strulade. Resten gick bra. Kör samma kommando igen om en stund.",
            "sad")
        return 1
    if done:
        celebrate(f"Klart! {join_names([k.name for k in done])} är {what}.")
    return 0


def cmd_status(a):
    with Spinner("Ringer runt till kusinerna…"):
        lat = scan()
    print()
    for l in status_lines(lat):
        print(fit(l))
    offline = all(k.latest is None for k in COUSINS)
    print(dim(f"\n  wuppa {VERSION}") + (dim(" · kunde inte nå GitHub") if offline else ""))
    return 0


def cmd_install(a):
    with Spinner("Kollar vilka kusiner som redan bor här…"):
        scan()
    targets = pick_names(a.names, [k for k in COUSINS if not k.installed])
    if not a.names:
        targets = [k for k in targets if not k.installed]
    if not targets:
        say("Alla tre kusinerna är redan installerade. Vill du uppdatera dem: wuppa update", "proud")
        return 0
    failed = do_install(targets)
    return report([k for k in targets if k not in failed], failed, "installerade")


def cmd_update(a):
    with Spinner("Frågar GitHub om det finns nytt…"):
        lat = scan()
    chosen = pick_names(a.names, COUSINS)
    targets = [k for k in chosen if k.outdated or (a.names and k.installed and a.force)]
    missing = [k for k in chosen if not k.installed]
    self_new = newer(lat, VERSION) and not a.names
    if not targets and not self_new:
        msg = "Allt är redan senaste versionen."
        if missing:
            msg += f" {join_names([k.name for k in missing])} är inte installerad: wuppa install"
        say(msg, "proud")
        return 0
    failed = do_install(targets, "Uppdaterar")
    rc = report([k for k in targets if k not in failed], failed, "uppdaterade")
    if self_new:
        rc = cmd_self_update(a) or rc
    return rc


def cmd_self_update(a):
    print()
    print(fit(f"  {accent(bold(LOGO))} {bold('Uppdaterar Wuppa')}"))
    me = Path(os.path.realpath(__file__))
    if (me.parent / ".git").exists():
        rc, out, err = run(["git", "-C", str(me.parent), "pull", "--ff-only"], timeout=120)
        print(("  " + green("✔") + " " if rc == 0 else "  " + red("✘") + " ") + ((out or err).strip().splitlines()
                                                                               or [""])[-1])
        return rc
    ok = run_installer("wuppa", env={"WUPPA_ONLY": "1"})      # bara Wuppa, inte kusinerna
    print("  " + (green("✔ Wuppa uppdaterad.") if ok else red("✘ Wuppa kunde inte uppdateras.")))
    return 0 if ok else 1


def cmd_run(name, args):
    exe = which(name)
    if not exe:
        say(f"{BY_KEY[name].name} är inte installerad än. Kör: wuppa install {name}", "worry")
        return 1
    try:
        return subprocess.call([exe] + list(args))
    except KeyboardInterrupt:
        return 130


# ───────────────────────────── meny ─────────────────────────────
def choose(rows, msg="", mood="happy", status=None, title=""):
    """Piltangent-meny i kusinernas stil. rows: ("head", text) eller dict(label, hint, value, key).
    Siffra väljer direkt, q/esc avbryter (→ None)."""
    if not sys.stdin.isatty():
        return None
    new_screen()
    sel = [k for k, r in enumerate(rows) if not isinstance(r, tuple)]
    keys, n = {}, 0
    for k in sel:
        r = rows[k]
        if r.get("key"):
            keys[r["key"]] = k
        else:
            n += 1
            if n <= 9:
                r["_num"] = str(n)
                keys[str(n)] = k
    pos, top = sel[0], 0
    live = Live()
    t0 = time.time()

    def draw(mood_now):
        nonlocal top
        w = width()
        lines = frame(msg, mood_now, sub=f"wuppa {VERSION} · Whole Uppa Puppa Package") if msg else []
        if status:
            lines += [""] + status()
        lines.append("")
        if title:
            lines.append("  " + accent("▍") + bold(title))
        narrow = w < 58
        lw = min(max(len(rows[k]["label"]) for k in sel) + 2, max(10, w - 14 if narrow else min(34, w // 2)))
        room = max(3, term_size()[1] - len(lines) - 3)
        top = min(max(top, pos - room + 1), pos)
        top = max(0, min(top, max(0, len(rows) - room)))
        if top > 0:
            lines.append(dim("     ↑ fler"))
        for k in range(top, min(len(rows), top + room)):
            r = rows[k]
            if isinstance(r, tuple):
                lines.append("   " + dim(cut(r[1].upper(), w - 5)))
                continue
            on = k == pos
            key = r.get("key") or r.get("_num") or " "
            label = cut(r["label"], lw - 1)
            label = bold(accent(label)) if on else label
            if narrow:
                line = f"  {accent('❯') if on else ' '}{dim(key)} {label}"
            else:
                line = f"   {accent('❯') if on else ' '} {dim(key)}  " + pad(label, lw)
                if r.get("hint") and w >= 64:
                    line += dim(r["hint"])
            lines.append(line)
        if top + room < len(rows):
            lines.append(dim("     ↓ fler"))
        lines.append("")
        lines.append(dim("   " + ("↑/↓ · enter · siffra väljer · q avsluta" if w >= 50 else "↑↓ enter · q")))
        live.draw(lines)

    choice, cur_mood, size = None, None, None
    with Keys() as kb:
        while True:
            m = mood
            if ANIM:
                im = idle_mood(time.time() - t0)
                m = im if mood == "happy" else ("blink" if im == "blink" else mood)
            if size != term_size() or m != cur_mood:
                size, cur_mood = term_size(), m
                draw(m)
            ch = kb.read(0.12)
            if ch is None:
                continue
            idx = sel.index(pos)
            if ch in ("\x1b[A", "k", "\x1bOA"):
                pos = sel[(idx - 1) % len(sel)]
            elif ch in ("\x1b[B", "j", "\x1bOB"):
                pos = sel[(idx + 1) % len(sel)]
            elif ch in keys:
                pos = keys[ch]
                choice = rows[pos]["value"]
                break
            elif ch in ("\r", "\n"):
                choice = rows[pos]["value"]
                break
            elif ch in ("q", "\x1b", "\x03", "\x04"):
                break
            size = None
        live.clear()
    return choice


class Args:
    names, force = [], False


def menu():
    global DIRTY
    if not sys.stdin.isatty():
        return cmd_status(Args())
    if TTY:
        sys.stdout.write("\033[H\033[2J")
    with Spinner("Ringer runt till kusinerna…"):
        lat = scan()
    while True:
        msg, mood = greeting(lat)
        missing = [k for k in COUSINS if not k.installed]
        old = [k for k in COUSINS if k.outdated]
        rows = [("head", "Starta")]
        for k in COUSINS:
            if k.installed:
                rows.append(dict(label=f"{k.name}", hint=k.desc, value=("run", k.key)))
        rows.append(("head", "Paketet"))
        if old or newer(lat, VERSION):
            n = len(old) + (1 if newer(lat, VERSION) else 0)
            rows.append(dict(label="Uppdatera allt", hint=f"{n} kan uppdateras", value=("update",), key="u"))
        if missing:
            rows.append(dict(label="Installera " + ("alla tre" if len(missing) == 3 else join_names(
                [k.name for k in missing])), hint="kör kusinernas egna installers", value=("install",), key="i"))
        for k in COUSINS:
            if k.installed:
                rows.append(dict(label=f"Uppdatera {k.name}", hint=(f"{k.current} → {k.latest}" if k.outdated
                                                                    else "installera om senaste"),
                                 value=("one", k.key)))
        rows.append(dict(label="Uppdatera Wuppa", hint=(f"{VERSION} → {lat}" if newer(lat, VERSION)
                                                        else "redan senaste"), value=("self",)))
        rows.append(dict(label="Skanna om", value=("rescan",), key="r"))
        rows.append(dict(label="Avsluta", value=("quit",), key="q"))
        v = choose(rows, msg, mood, status=lambda: status_lines(lat, desc=False))
        if v is None or v[0] == "quit":
            return 0
        if TTY:
            sys.stdout.write("\033[H\033[2J")
            sys.stdout.flush()
        if v[0] == "run":
            cmd_run(v[1], [])
            DIRTY = False
        elif v[0] == "update":
            a = Args()
            failed = do_install(old, "Uppdaterar")
            report([k for k in old if k not in failed], failed, "uppdaterade")
            if newer(lat, VERSION):
                return restart_after_self_update(a)
        elif v[0] == "install":
            failed = do_install(missing)
            report([k for k in missing if k not in failed], failed, "installerade")
        elif v[0] == "one":
            k = BY_KEY[v[1]]
            failed = do_install([k], "Uppdaterar")
            report([k] if not failed else [], failed, "uppdaterad")
        elif v[0] == "self":
            return restart_after_self_update(Args())
        with Spinner("Räknar in kusinerna igen…"):
            lat = scan()


def file_version(path):
    try:
        m = re.search(r'^VERSION = "([^"]+)"', Path(path).read_text(encoding="utf-8"), re.M)
        return m.group(1) if m else None
    except Exception:
        return None


def restart_after_self_update(a):
    """Uppdatera Wuppa och starta om menyn i den nya versionen."""
    me = os.path.realpath(__file__)
    cmd_self_update(a)
    new = file_version(me)
    if new and new != VERSION:
        print()
        say(f"Startar om som wuppa {new}…", "proud")
        time.sleep(0.8)
        os.execv(sys.executable, [sys.executable, me])
    pause()
    return menu()


# ───────────────────────────── main ─────────────────────────────
def main(argv=None):
    global ANIM, COLOR
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0].lower() in BY_KEY:              # wuppa puppa … → skicka allt vidare
        return cmd_run(argv[0].lower(), argv[1:])
    if "--no-anim" in argv:
        argv.remove("--no-anim")
        ANIM = False
    if argv[:1] in (["--version"], ["-V"], ["version"]):
        print(f"wuppa {VERSION}")
        return 0
    if argv[:1] in (["-h"], ["--help"], ["help"]):
        print(__doc__.strip())
        return 0
    a = Args()
    a.force = any(x in ("-f", "--force") for x in argv)
    rest = [x for x in argv if not x.startswith("-")]
    cmd, a.names = (rest[0], rest[1:]) if rest else (None, [])
    try:
        if cmd is None:
            return menu()
        fn = {"status": cmd_status, "install": cmd_install, "update": cmd_update, "upgrade": cmd_update,
              "self-update": cmd_self_update}.get(cmd)
        if not fn:
            print(f"  okänt kommando: {cmd}\n")
            print(__doc__.strip())
            return 2
        return fn(a)
    except KeyboardInterrupt:
        print()
        return 130


if __name__ == "__main__":
    sys.exit(main())
