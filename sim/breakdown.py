"""Why did I win/lose: where the gap between two runs came from, and why.

Both runs are on the same grid (same s nodes). The gap at node i is

    gap(i) = t_them(i) - t_me(i)        (> 0: "me" got there first)

and every interval i -> i+1 adds gain_i = dt_them - dt_me to it, so the gains
add up EXACTLY to the final gap (telescoping sum). Each interval's gain goes
in one bucket (a cause):

    launch   gap(0): the difference in reaction off the green
    corner   inside a corner (the speed each car carried through it)
    mistake  inside a corner where either driver ran wide, AND the exit speed
             lost on the straight after it (running wide ruins the exit)
    braking  either car on the brakes
    exit     on a straight: the speed difference coming out of the last corner
    accel    on a straight: one car simply accelerating harder (power-to-weight,
             traction, gearing)

exit vs accel (work-energy theorem): if both cars had the same net force per
kg, they'd gain the same v^2/2 over the same distance, so a speed difference
at the start of a straight keeps a constant offset in v^2. A what-if "me" that
starts the straight at my speed but accelerates like them:

    v'(s)^2 = v_them(s)^2 + (v_me(a)^2 - v_them(a)^2)

The time that what-if gains on them is "exit"; the rest of the actual gain
is "accel". (PHYSICS_updates_G 6.v.)

A crashed run ends early: the breakdown covers the distance both cars drove.
"""
import math

CAUSES = ("launch", "accel", "exit", "braking", "corner", "mistake")
V_FLOOR = 0.5   # m/s, keeps the what-if speed real if it would dip below zero


def _dt(v0, v1, ds):
    """Time over one interval at the average speed (the sim's own step rule)."""
    return 2.0 * ds / max(v0 + v1, 1e-9)


def _what_if(v_them, c):
    """sqrt(v_them^2 + c), floored only where that would go below V_FLOOR (a
    big negative offset); with c = 0 it is exactly v_them, even at a standstill."""
    return math.sqrt(max(v_them ** 2 + c, min(v_them, V_FLOOR) ** 2))


def _corners(segments):
    """[(text, s_start, s_end)] for every corner, in order."""
    out, pos = [], 0.0
    for seg in segments:
        if seg.is_corner:
            out.append((seg.text, pos, pos + seg.length))
        pos += seg.length
    return out


def _mistakes(corners, me, them):
    """Corner index -> who ran wide there: "me", "them" or "both"."""
    out = {}
    for who, run in (("me", me), ("them", them)):
        for c in getattr(run, "corner_log", []) or []:
            if not c.mistake:
                continue
            k = next((k for k, (_, a, _) in enumerate(corners) if abs(a - c.s_start) < 1.0), None)
            if k is not None:
                out[k] = "both" if out.get(k, who) != who else who
    return out


def breakdown(segments, me, them):
    """Where `me` gained and lost time on `them`, and why. Both are LapResults
    (anything with .telemetry, .corner_log, .dnf) run on the same grid.

    Returns a dict (JSON-ready, times in s, speeds in m/s):
      gap       final gap over the distance both drove (> 0: me ahead)
      launch    gap at the start line (reaction difference)
      totals    {cause: gain} over the whole run (launch included)
      sections  one per corner (ending at its exit) plus the run to the line:
                {name, s_end, t_me, t_them, gain, total, causes, top_cause,
                 exit_from, mistake_by, v_min_me, v_min_them, v_top_me, v_top_them}
      swings    the 3 biggest (where, cause, gain) items, biggest first
      verdict   the cause behind the result: biggest loss if me lost, biggest
                gain if me won; "crash" / "their_crash" when a crash decided it
      complete  False when a crash cut the comparison short
    """
    tm, tt = me.telemetry, them.telemetry
    n = min(len(tm.s), len(tt.s))
    s = tm.s[:n]
    corners = _corners(segments)
    mistakes = _mistakes(corners, me, them)

    def corner_at(x):
        return next((k for k, (_, a, b) in enumerate(corners) if a <= x < b), None)

    def section_at(x):
        return next((k for k, (_, _, b) in enumerate(corners) if x < b), len(corners))

    n_sec = len(corners) + 1
    # Per section; "wide_exit" (the exit after a corner someone ran wide in) is
    # reported as part of "mistake" but kept apart so it can name that corner
    sec_causes = [dict.fromkeys(CAUSES[1:] + ("wide_exit",), 0.0) for _ in range(n_sec)]
    sec_last = [None] * n_sec            # last node index reached in each section
    v_min = [[math.inf, math.inf] for _ in range(n_sec)]
    v_top = [[0.0, 0.0] for _ in range(n_sec)]

    run_c = None                          # v^2 offset of the current straight run
    prev_phase = None
    for i in range(n - 1):
        ds = s[i + 1] - s[i]
        mid = (s[i] + s[i + 1]) / 2.0
        k = corner_at(mid)
        sec = section_at(mid)
        gain = (tt.t[i + 1] - tt.t[i]) - (tm.t[i + 1] - tm.t[i])
        if k is not None:
            phase = "mistake" if k in mistakes else "corner"
            v_min[sec][0] = min(v_min[sec][0], tm.v[i + 1])
            v_min[sec][1] = min(v_min[sec][1], tt.v[i + 1])
        elif tm.brake[i] > 0.0 or tt.brake[i] > 0.0:
            phase = "braking"
        else:
            phase = "straight"
            v_top[sec][0] = max(v_top[sec][0], tm.v[i + 1])
            v_top[sec][1] = max(v_top[sec][1], tt.v[i + 1])
        if phase == "straight":
            if prev_phase != "straight":  # a new straight run: fix the v^2 offset
                run_c = tm.v[i] ** 2 - tt.v[i] ** 2
            w0, w1 = _what_if(tt.v[i], run_c), _what_if(tt.v[i + 1], run_c)
            carry = _dt(tt.v[i], tt.v[i + 1], ds) - _dt(w0, w1, ds)
            # Coming out of a corner someone ran wide in: the slow exit is the mistake's
            sec_causes[sec]["wide_exit" if sec - 1 in mistakes else "exit"] += carry
            sec_causes[sec]["accel"] += gain - carry
        else:
            sec_causes[sec][phase] += gain
        sec_last[sec] = i + 1
        prev_phase = phase

    def gap(i):
        return tt.t[i] - tm.t[i]

    launch = gap(0)
    sections = []
    for k in range(n_sec):
        if sec_last[k] is None:
            continue
        end = sec_last[k]
        name = corners[k][0] if k < len(corners) else "FINISH"
        raw = dict(sec_causes[k])
        raw["mistake"] += raw.pop("wide_exit")
        causes = {c: round(g, 3) for c, g in raw.items()}
        top = max(raw, key=lambda c: abs(raw[c]))
        sections.append({
            "name": name, "s_end": round(s[end], 1),
            "t_me": round(tm.t[end], 3), "t_them": round(tt.t[end], 3),
            "gain": round(sum(sec_causes[k].values()), 3), "total": round(gap(end), 3),
            "causes": causes, "top_cause": top,
            "exit_from": corners[k - 1][0] if k > 0 else "",
            "mistake_by": mistakes.get(k, "") if k < len(corners) else "",
            "v_min_me": None if math.isinf(v_min[k][0]) else round(v_min[k][0], 2),
            "v_min_them": None if math.isinf(v_min[k][1]) else round(v_min[k][1], 2),
            "v_top_me": round(v_top[k][0], 2), "v_top_them": round(v_top[k][1], 2),
        })

    totals = dict.fromkeys(CAUSES, 0.0)
    totals["launch"] = launch
    for causes in sec_causes:
        for c, g in causes.items():
            totals["mistake" if c == "wide_exit" else c] += g
    final = gap(n - 1)

    # Swing items: (where, cause). A mistake's wide exit joins that corner's mistake.
    items = {("", "launch"): launch}
    for k in range(n_sec):
        if sec_last[k] is None:
            continue
        here = corners[k][0] if k < len(corners) else "FINISH"
        before = corners[k - 1][0] if k > 0 else ""
        for c, g in sec_causes[k].items():
            key = {"exit": (before, "exit"), "wide_exit": (before, "mistake")}.get(c, (here, c))
            items[key] = items.get(key, 0.0) + g
    who = {corners[k][0]: by for k, by in mistakes.items()}
    items = [{"where": w, "cause": c, "gain": g, "mistake_by": who.get(w, "") if c == "mistake" else ""}
             for (w, c), g in items.items()]
    items = [it for it in items if abs(it["gain"]) >= 0.01]
    items.sort(key=lambda it: -abs(it["gain"]))
    for it in items:
        it["gain"] = round(it["gain"], 3)

    if me.dnf:
        verdict = "crash"
    elif them.dnf:
        verdict = "their_crash"
    elif final < 0:
        verdict = min(totals, key=lambda c: totals[c])
    else:
        verdict = max(totals, key=lambda c: totals[c])

    return {"gap": round(final, 3), "launch": round(launch, 3),
            "totals": {c: round(g, 3) for c, g in totals.items()},
            "sections": sections, "swings": items[:3], "verdict": verdict,
            "complete": not (me.dnf or them.dnf), "until_s": round(s[n - 1], 1)}
