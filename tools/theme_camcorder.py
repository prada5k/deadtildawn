"""theme.tres -> the CAMCORDER look (Spire, Oct 2026: "get rid of the button
panels... they take away from the feel"). The menus are the camcorder's own
on-screen display over the garage footage: no paper, no tape, no stickers
behind the text.

- Panels (paper, flyers, clipboard, receipt...) -> a faint dark smoke, no
  border (just enough to read text over the footage).
- The whiteboard -> a phone screen (the calendar is on your phone).
- Buttons -> camcorder menu: VT323, white; main actions in a thin white
  frame, small ones bare text; SEND IT in red.
- Ink colors (made for paper) -> light, with a hard shadow so they read on
  the footage. Money stays green, rep orange, good green, bad red.

    python tools/theme_camcorder.py      (idempotent: re-run after theme edits)
"""
import re
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "godot" / "theme.tres"
t = P.read_text(encoding="utf-8")

WHITE = (0.95, 0.94, 0.91, 1)
MUTED = (0.72, 0.72, 0.74, 1)
MONEY = (0.38, 0.92, 0.46, 1)
GOOD = (0.42, 0.92, 0.46, 1)
BAD = (1.0, 0.36, 0.3, 1)
BLUE = (0.45, 0.68, 1.0, 1)
MARKER = (0.99, 0.86, 0.42, 1)          # the builder's handwriting: a yellow paint pen
SMOKE = (0.02, 0.02, 0.03, 0.45)


def col(c):
    return "Color(%s, %s, %s, %s)" % tuple(round(v, 3) for v in c)


def set_color(var, key, c):
    global t
    line = f"{var}/colors/{key} = "
    if line in t:
        t = re.sub(re.escape(line) + r"Color\([^)]*\)", line + col(c), t)
    else:
        anchor = re.search(rf"^{re.escape(var)}/base_type = .*$", t, re.M)
        if anchor:
            t = t[:anchor.end()] + "\n" + line + col(c) + t[anchor.end():]


def set_const(var, key, v):
    global t
    line = f"{var}/constants/{key} = "
    if line in t:
        t = re.sub(re.escape(line) + r"-?\d+", line + str(v), t)
    else:
        anchor = re.search(rf"^{re.escape(var)}/base_type = .*$", t, re.M)
        if anchor:
            t = t[:anchor.end()] + "\n" + line + str(v) + t[anchor.end():]


def set_font(var, rid):
    global t
    line = f"{var}/fonts/font = "
    if line in t:
        t = re.sub(re.escape(line) + r".*", line + f'ExtResource("{rid}")', t)
    else:
        anchor = re.search(rf"^{re.escape(var)}/base_type = .*$", t, re.M)
        if anchor:
            t = t[:anchor.end()] + "\n" + line + f'ExtResource("{rid}")' + t[anchor.end():]


def shadow(var):
    set_color(var, "font_shadow_color", (0, 0, 0, 0.85))
    set_const(var, "shadow_offset_x", 2)
    set_const(var, "shadow_offset_y", 2)


def replace_style(sid, body_lines, kind="StyleBoxFlat"):
    global t
    pat = re.compile(r'\[sub_resource type="\w+" id="%s"\]\n(.*?)\n\n' % re.escape(sid), re.S)
    m = pat.search(t)
    if not m:
        return
    margins = dict(re.findall(r"content_margin_(left|top|right|bottom) = ([\d.]+)", m.group(1)))
    lines = [f'[sub_resource type="{kind}" id="{sid}"]']
    for side in ("left", "top", "right", "bottom"):
        lines.append(f"content_margin_{side} = {float(margins.get(side, 12)):.1f}")
    t = t[:m.start()] + "\n".join(lines + body_lines) + "\n\n" + t[m.end():]


# The VT323 font (the OSD's)
vt = re.search(r'\[ext_resource type="FontFile"[^\]]*path="res://fonts/VT323-Regular.ttf" id="([^"]+)"\]', t).group(1)

# ---- panels: smoke
for sid in ("paper", "clipboard", "speech", "polaroid", "memory_photo", "receipt", "flyer_yellow",
            "flyer_pink", "flyer_blue", "cardboard", "corkboard", "bench", "dymo"):
    replace_style(sid, [f"bg_color = {col(SMOKE if sid != 'dymo' else (0, 0, 0, 0))}"])
# ---- the whiteboard: a phone (the calendar)
replace_style("whiteboard", [f"bg_color = {col((0.035, 0.035, 0.05, 0.97))}",
                             "border_width_left = 10", "border_width_top = 26", "border_width_right = 10",
                             "border_width_bottom = 26", f"border_color = {col((0.09, 0.09, 0.11, 1))}",
                             "corner_radius_top_left = 38", "corner_radius_top_right = 38",
                             "corner_radius_bottom_right = 38", "corner_radius_bottom_left = 38",
                             "shadow_color = Color(0, 0, 0, 0.6)", "shadow_size = 12"])

# ---- buttons: the camcorder menu
def frame(bg, border, width=2):
    return [f"bg_color = {col(bg)}", f"border_width_left = {width}", f"border_width_top = {width}",
            f"border_width_right = {width}", f"border_width_bottom = {width}", f"border_color = {col(border)}"]

replace_style("gaff", frame((0, 0, 0, 0.25), WHITE))
replace_style("gaff_hover", frame((1, 1, 1, 0.14), WHITE))
replace_style("gaff_pressed", frame((0.95, 0.94, 0.91, 0.9), WHITE))
replace_style("gaff_disabled", frame((0, 0, 0, 0.2), (1, 1, 1, 0.3)))
replace_style("gaff_small", frame((0, 0, 0, 0.25), WHITE))
replace_style("gaff_small_pressed", frame((0.95, 0.94, 0.91, 0.9), WHITE))
replace_style("gaff_small_disabled", frame((0, 0, 0, 0.2), (1, 1, 1, 0.3)))
replace_style("gaff_red", frame((0.85, 0.12, 0.1, 0.35), BAD, 3))
replace_style("gaff_red_hover", frame((0.95, 0.15, 0.12, 0.5), BAD, 3))
replace_style("gaff_red_pressed", frame((0.95, 0.2, 0.15, 0.85), BAD, 3))
for sid in ("tape", "tape_small", "tape_disabled"):
    replace_style(sid, ["bg_color = Color(0, 0, 0, 0)"])

for var in ("GaffButton", "GaffSmallButton", "GaffRedButton", "TapeButton", "SmallTapeButton"):
    set_font(var, vt)
    for key in ("font_color", "font_focus_color", "font_hover_color"):
        set_color(var, key, WHITE)
    set_color(var, "font_pressed_color", (0.06, 0.05, 0.05, 1) if var.startswith("Gaff") else MARKER)
    set_color(var, "font_hover_pressed_color", (0.06, 0.05, 0.05, 1) if var.startswith("Gaff") else MARKER)
    set_color(var, "font_disabled_color", (1, 1, 1, 0.35))
    shadow(var)
for var in ("TapeButton", "SmallTapeButton"):
    set_color(var, "font_hover_color", MARKER)
set_color("GaffRedButton", "font_pressed_color", WHITE)
set_color("GaffRedButton", "font_hover_pressed_color", WHITE)
for var in ("PartPickButton",):
    for key in ("font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"):
        set_color(var, key, WHITE)
    set_color(var, "font_disabled_color", (1, 1, 1, 0.35))
set_font("TapeLabel", vt)
set_font("DymoLabel", vt)

# ---- text: light ink with a hard shadow
for var in ("InkLabel", "InkHeadingLabel", "SpeechLabel", "FlyerTextLabel", "FlyerTitleLabel", "TapeLabel",
            "WhiteboardLabel", "WhiteboardSmallLabel"):
    set_color(var, "font_color", WHITE)
    shadow(var)
for var in ("InkMutedLabel",):
    set_color(var, "font_color", MUTED)
    shadow(var)
for var in ("MarkerLabel", "MarkerSmallLabel"):
    set_color(var, "font_color", MARKER)
    shadow(var)
for var in ("InkMoneyLabel", "InkMoneyBigLabel", "FlyerPriceLabel", "WhiteboardGreenLabel"):
    set_color(var, "font_color", MONEY)
    shadow(var)
for var in ("InkRepLabel",):
    shadow(var)
set_color("InkGoodLabel", "font_color", GOOD)
shadow("InkGoodLabel")
for var in ("InkBadLabel", "WhiteboardRedLabel", "WhiteboardRedSmallLabel"):
    set_color(var, "font_color", BAD)
    shadow(var)
set_color("WhiteboardBlueLabel", "font_color", BLUE)
shadow("WhiteboardBlueLabel")
set_color("StampLabel", "font_color", BAD)
for key, c in (("caret_color", WHITE), ("font_color", WHITE), ("font_selected_color", WHITE),
               ("font_placeholder_color", (1, 1, 1, 0.4))):
    set_color("InkLineEdit", key, c)
# Drawn widgets that read their colors from the theme
set_color("InkTrackMap", "line", (1, 1, 1, 0.55))
set_color("InkTrackMap", "marker", WHITE)
set_color("InkTrackMap", "faster", BLUE)
set_color("InkTrackMap", "slower", BAD)
set_color("InkDynoChart", "grid", (1, 1, 1, 0.14))
set_color("InkDynoChart", "text", MUTED)
set_color("InkDynoChart", "power", BAD)
set_color("InkDynoChart", "torque", BLUE)
set_color("InkDynoChart", "redline", (1.0, 0.36, 0.3, 0.12))

P.write_text(t, encoding="utf-8")
print("ok")
