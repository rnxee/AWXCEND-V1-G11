"""AWXCEND look - the "System window" of an action RPG, same design language as the web app:
abyss-black world with two soft auras, blue-glass panels with a glowing edge and corner brackets,
chamfered buttons, segmented game gauges, Michroma titles. Every screen builds from these widgets."""
import math
from datetime import datetime

import flet as ft


class C:
    void = "#05070d"
    void_deep = "#030409"
    panel = "#0b0f1a"
    panel_alt = "#111729"
    border = "#1c2640"
    border_bright = "#2e4270"
    primary = "#2b8cff"
    primary_bright = "#63b3ff"
    primary_deep = "#0a4fd6"
    accent = "#a78bfa"
    camera = "#22d3ee"
    food = "#34d399"
    gold = "#fbbf24"
    danger = "#f87171"
    text = "#f2f6ff"
    dim = "#9aa8c7"
    faint = "#7584a8"


FONTS = {
    "Lato": "fonts/Lato-Regular.ttf",
    "LatoBold": "fonts/Lato-Bold.ttf",
    "LatoBlack": "fonts/Lato-Black.ttf",
    "Michroma": "fonts/Michroma-Regular.ttf",
}

FOCUS_TYPES = [
    ("hybrid", "Hybrid Athlete"), ("powerlifter", "Powerlifter"), ("cali", "Calisthenics"),
    ("aesthetic", "Aesthetic"), ("weightlifter", "Olympic Weightlifter"), ("strongman", "Strongman"),
    ("tactical", "Tactical"), ("hypertrophy", "Hypertrophy"), ("lifestyle", "Lifestyle"),
]
FOCUS_LABEL = dict(FOCUS_TYPES)
MAX_WIDTH = 760
CHAMFER = ft.BeveledRectangleBorder(radius=7)  # the hard cut corners of the System UI


def theme() -> ft.Theme:
    return ft.Theme(
        use_material3=True,
        font_family="Lato",
        color_scheme=ft.ColorScheme(
            primary=C.primary, on_primary="#ffffff", secondary=C.accent, on_secondary=C.void,
            surface=C.panel, on_surface=C.text, error=C.danger, outline=C.border_bright,
            surface_container_highest=C.panel_alt, surface_container=C.panel, surface_container_high=C.panel_alt,
        ),
        scaffold_bgcolor=C.void,
        canvas_color=C.panel,
        divider_color=C.border,
    )


def fade(color: str, alpha: int) -> str:
    """color at alpha/255 opacity (Flet reads 8-digit hex as #AARRGGBB, so never append alpha)."""
    return ft.Colors.with_opacity(round(alpha / 255, 3), color)


def mix(a: str, b: str, t: float) -> str:
    """Blend two #rrggbb colours (t=0 -> a, t=1 -> b)."""
    ca, cb = [int(a[i:i + 2], 16) for i in (1, 3, 5)], [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb, strict=True))


def glow(color: str, strength: int = 0x55, blur: int = 16) -> list[ft.BoxShadow]:
    return [ft.BoxShadow(blur_radius=blur, spread_radius=0, color=fade(color, strength))]


# ---- the world behind every screen -----------------------------------------------
def backdrop(content: ft.Control) -> ft.Control:
    """Abyss-black background with a blue aura top-left and a violet aura bottom-right."""
    fill = dict(left=0, top=0, right=0, bottom=0)
    return ft.Stack([
        ft.Container(bgcolor=C.void, **fill),
        ft.Container(gradient=ft.RadialGradient(center=ft.Alignment(-1.0, -1.1), radius=1.1,
                                                colors=[fade(C.primary, 0x30), fade(C.primary, 0)]), **fill),
        ft.Container(gradient=ft.RadialGradient(center=ft.Alignment(1.1, 1.1), radius=1.0,
                                                colors=[fade(C.accent, 0x26), fade(C.accent, 0)]), **fill),
        ft.Container(content, **fill),
    ], expand=True)


# ---- text -------------------------------------------------------------------
def title(text: str, size: int = 20, color: str = C.text) -> ft.Text:
    return ft.Text(text.upper(), font_family="Michroma", size=size, color=color,
                   style=ft.TextStyle(letter_spacing=1.5, shadow=glow(C.primary, 0x99, 18)))


def heading(text: str, size: int = 16, color: str = C.text) -> ft.Text:
    return ft.Text(text, font_family="LatoBlack", size=size, color=color)


def label(text: str, color: str = C.dim, size: int = 12) -> ft.Text:
    return ft.Text(text.upper(), size=size, color=color, font_family="LatoBold",
                   style=ft.TextStyle(letter_spacing=1.2))


def body(text: str, color: str = C.dim, size: int = 14, **kw) -> ft.Text:
    return ft.Text(text, color=color, size=size, **kw)


def num(value, size: int = 24, color: str = C.text) -> ft.Text:
    """Big game number with a soft glow in its own colour."""
    return ft.Text(f"{value:,}" if isinstance(value, int) else str(value), font_family="LatoBlack", size=size,
                   color=color, style=ft.TextStyle(shadow=glow(color, 0x66, 14)))


def diamond(color: str = C.accent, size: int = 8) -> ft.Control:
    return ft.Container(width=size, height=size, bgcolor=color, rotate=ft.Rotate(math.pi / 4),
                        shadow=glow(color, 0x99, 8))


def section(text: str, color: str = C.accent) -> ft.Control:
    """Section header: ◆ LABEL ───── (a glowing diamond, caps label and a fading rule)."""
    rule = ft.Container(height=1, expand=True,
                        gradient=ft.LinearGradient(colors=[fade(color, 0x88), fade(color, 0)]))
    return ft.Row([diamond(color), label(text, C.dim, 12), rule], spacing=10,
                  vertical_alignment=ft.CrossAxisAlignment.CENTER)


def tag(text: str, color: str = C.accent) -> ft.Control:
    """A small chamfer-ish status pill, e.g. LEVEL 12, HYBRID."""
    return ft.Container(label(text, color, 10), padding=ft.Padding.symmetric(horizontal=8, vertical=3),
                        bgcolor=fade(color, 0x1f), border=ft.Border.all(1, fade(color, 0x66)), border_radius=3)


def icon_chip(icon, color: str, size: int = 38) -> ft.Control:
    """An icon on a tinted square with a glow: the tile/stat marker."""
    return ft.Container(ft.Icon(icon, color=color, size=size * 0.55), width=size, height=size,
                        alignment=ft.Alignment.CENTER, bgcolor=fade(color, 0x1f), border_radius=6,
                        border=ft.Border.all(1, fade(color, 0x55)), shadow=glow(color, 0x33, 12))


# ---- surfaces ---------------------------------------------------------------
_LAYOUT_KEYS = ("expand", "col", "width", "height", "margin", "visible", "expand_loose")


def card(content: ft.Control, padding: int = 16, on_click=None, accent: str | None = None, **kw) -> ft.Control:
    """A System window: blue-glass panel, glowing edge, a lit top rule and corner brackets."""
    edge = (accent or C.primary_bright).split(",")[0]  # accept an already-faded colour too
    layout = {k: kw.pop(k) for k in _LAYOUT_KEYS if k in kw}
    panel = ft.Container(
        content=content, padding=padding, on_click=on_click, ink=on_click is not None, border_radius=4,
        gradient=ft.LinearGradient(begin=ft.Alignment.TOP_CENTER, end=ft.Alignment.BOTTOM_CENTER,
                                   colors=[fade("#16306e", 0x60), fade("#0a122a", 0xc6), fade("#060a18", 0xdb)],
                                   stops=[0.0, 0.45, 1.0]),
        border=ft.Border.all(1, fade(edge, 0x55)),
        shadow=glow(edge, 0x2a, 16), **kw,  # no `animate` here: with ink it applies the padding twice
    )
    if on_click is not None:  # desktop hover: the frame lights up
        def hover(e, p=panel):
            p.border = ft.Border.all(1, fade(edge, 0xcc if e.data == "true" else 0x55))
            p.shadow = glow(edge, 0x55 if e.data == "true" else 0x2a, 20)
            p.update()
        panel.on_hover = hover

    def bracket(**pos):
        side = ft.BorderSide(2, edge)
        none = ft.BorderSide(0, ft.Colors.TRANSPARENT)
        b = ft.Border(top=side if "top" in pos else none, bottom=side if "bottom" in pos else none,
                      left=side if "left" in pos else none, right=side if "right" in pos else none)
        return ft.Container(width=12, height=12, border=b, **pos)

    top_rule = ft.Container(height=1, left=40, right=40, top=0,
                            gradient=ft.LinearGradient(colors=[fade(C.accent, 0), C.accent, fade(C.accent, 0)]))
    return ft.Stack([panel, bracket(left=0, top=0), bracket(right=0, top=0), bracket(left=0, bottom=0),
                     bracket(right=0, bottom=0), top_rule], fit=ft.StackFit.PASS_THROUGH, **layout)


def stat(caption: str, value, color: str = C.text, icon: ft.IconData | None = None) -> ft.Control:
    """Stat tile: icon chip, big glowing number, caption under it (fits a third of a phone screen)."""
    head = [icon_chip(icon, color, 28)] if icon else []
    return card(ft.Column([*head, num(value, 22, color),
                           ft.Text(caption.upper(), size=10, color=C.dim, font_family="LatoBold", no_wrap=True,
                                   overflow=ft.TextOverflow.ELLIPSIS, style=ft.TextStyle(letter_spacing=1))],
                          spacing=4), padding=12, expand=True, accent=color)


def xp_bar(progress: float, color: str = C.primary, height: int = 10, segments: int = 10,
           end_color: str = C.accent) -> ft.Control:
    """A segmented game gauge: the fill runs blue -> violet across the segments and glows."""
    p = max(0.0, min(progress, 1.0)) * segments
    cells = []
    for i in range(segments):
        tint = mix(color, end_color, i / max(segments - 1, 1))
        amount = max(0.0, min(p - i, 1.0))
        if amount >= 1:
            cells.append(ft.Container(expand=1, bgcolor=tint, shadow=glow(tint, 0x66, 8)))
        elif amount > 0:
            filled = int(amount * 100)
            cells.append(ft.Container(ft.Row([ft.Container(expand=filled, bgcolor=tint),
                                              ft.Container(expand=100 - filled)], spacing=0),
                                      expand=1, bgcolor=C.void_deep, shadow=glow(tint, 0x44, 8)))
        else:
            cells.append(ft.Container(expand=1, bgcolor=C.void_deep, border=ft.Border.all(1, C.border)))
    return ft.Container(ft.Row(cells, spacing=2), height=height)


# ---- inputs -----------------------------------------------------------------
def _field_style() -> dict:
    return dict(border_radius=4, border_color=C.border_bright, focused_border_color=C.accent, filled=True,
                fill_color=fade(C.void_deep, 0xcc), label_style=ft.TextStyle(color=C.dim),
                cursor_color=C.accent)


def field(lbl: str, **kw) -> ft.TextField:
    return ft.TextField(label=lbl, **{**_field_style(), **kw})


def number_field(lbl: str, value="", decimals: bool = False, **kw) -> ft.TextField:
    pattern = r"^\d*\.?\d{0,2}$" if decimals else r"^\d*$"
    return field(lbl, value=str(value), keyboard_type=ft.KeyboardType.NUMBER,
                 input_filter=ft.InputFilter(regex_string=pattern, allow=True), **kw)


def dropdown(lbl: str, options: list[tuple[str, str]], value: str | None = None, **kw) -> ft.Dropdown:
    style = {k: v for k, v in _field_style().items() if k != "cursor_color"}
    return ft.Dropdown(label=lbl, value=value, options=[ft.DropdownOption(key=k, text=t) for k, t in options],
                       **{**style, **kw})


def button(text: str, on_click=None, icon=None, kind: str = "primary", **kw) -> ft.Control:
    """Chamfered System button with a glow; ghost/text variants for secondary actions."""
    if kind == "text":
        return ft.TextButton(content=text, icon=icon, on_click=on_click,
                             style=ft.ButtonStyle(color=C.primary_bright, shape=CHAMFER), **kw)
    if kind == "ghost":
        return ft.OutlinedButton(content=text, icon=icon, on_click=on_click, style=ft.ButtonStyle(
            shape=CHAMFER, color=C.primary_bright, side=ft.BorderSide(1, fade(C.primary_bright, 0x88)),
            overlay_color=fade(C.primary, 0x22), padding=ft.Padding.symmetric(horizontal=16, vertical=12)), **kw)
    color = {"primary": C.primary, "danger": C.danger, "camera": C.camera, "food": C.food, "accent": C.accent}[kind]
    fg = C.void if kind in ("camera", "food", "accent") else "#ffffff"
    return ft.FilledButton(content=text, icon=icon, on_click=on_click, style=ft.ButtonStyle(
        shape=CHAMFER, bgcolor=color, color=fg, elevation=6, shadow_color=color,
        overlay_color=fade("#ffffff", 0x22), padding=ft.Padding.symmetric(horizontal=18, vertical=14),
        text_style=ft.TextStyle(font_family="LatoBlack", letter_spacing=0.8)), **kw)


def chips(options: list[tuple[str, str]], selected: str, on_pick) -> ft.Row:
    """Single-select tabs, System style: the active one is lit blue with a glow."""
    row = ft.Row(wrap=True, spacing=8, run_spacing=8)

    def tab(k, t, active):
        return ft.Container(
            ft.Text(t.upper(), size=12, font_family="LatoBold", color=C.text if active else C.dim,
                    style=ft.TextStyle(letter_spacing=1)),
            padding=ft.Padding.symmetric(horizontal=14, vertical=9), border_radius=3, ink=True,
            bgcolor=fade(C.primary, 0x33) if active else fade(C.void_deep, 0xaa),
            border=ft.Border.all(1, C.primary_bright if active else C.border),
            shadow=glow(C.primary, 0x44, 12) if active else None,
            on_click=lambda e, k=k: pick(k))

    def render(current):
        row.controls = [tab(k, t, k == current) for k, t in options]

    def pick(k):
        render(k)
        row.update()
        on_pick(k)

    render(selected)
    return row


# ---- states -----------------------------------------------------------------
def loading(text: str = "Loading...") -> ft.Control:
    return ft.Container(ft.Row([ft.ProgressRing(width=18, height=18, stroke_width=2, color=C.accent),
                                label(text, C.dim, 12)], alignment=ft.MainAxisAlignment.CENTER), padding=24)


def empty(text: str, icon=ft.Icons.INBOX_OUTLINED) -> ft.Control:
    return ft.Container(ft.Column([icon_chip(icon, C.faint, 44), body(text, text_align=ft.TextAlign.CENTER)],
                                  horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=10), padding=24,
                        alignment=ft.Alignment.CENTER)


def error_box(text: str, on_retry=None) -> ft.Control:
    items = [ft.Icon(ft.Icons.ERROR_OUTLINE, color=C.danger), ft.Text(text, color=C.danger, expand=True)]
    if on_retry:
        items.append(button("Retry", lambda e: on_retry(), kind="text"))
    return card(ft.Row(items), accent=C.danger)


def avatar(name: str, size: int = 40, color: str = C.primary) -> ft.Control:
    """Initial in a glowing ring."""
    return ft.Container(
        ft.Text((name or "?")[:1].upper(), font_family="Michroma", size=size * 0.36, color=color),
        width=size, height=size, alignment=ft.Alignment.CENTER, shape=ft.BoxShape.CIRCLE,
        bgcolor=fade(color, 0x22), border=ft.Border.all(1.5, fade(color, 0xaa)), shadow=glow(color, 0x44, 14))


def rank_text(p: dict) -> str:
    rank = p.get("rank") or "Unranked"
    sub = p.get("rank_sub_index")
    return f"{rank} {sub}" if sub else rank


def screen(heading_text: str, *controls: ft.Control, actions: list[ft.Control] | None = None,
           subtitle: str | None = None) -> ft.Control:
    """Standard page: glowing title + fading rule, then content, centred and capped for wide windows."""
    rule = ft.Container(height=1, gradient=ft.LinearGradient(colors=[C.primary_bright, fade(C.accent, 0x88),
                                                                     fade(C.accent, 0)]))
    head = [ft.Column([title(heading_text, 18)] + ([body(subtitle, size=13)] if subtitle else []), spacing=4,
                      expand=True)]
    col = ft.Column([ft.Row(head + (actions or []), vertical_alignment=ft.CrossAxisAlignment.CENTER), rule,
                     *controls], spacing=14, scroll=ft.ScrollMode.AUTO, expand=True)
    return ft.Container(ft.Container(col, width=MAX_WIDTH, expand=True),
                        padding=ft.Padding.symmetric(horizontal=16, vertical=16),
                        alignment=ft.Alignment.TOP_CENTER, expand=True)


def when(iso: str) -> str:
    """Server timestamp -> local 'Sep 26, 3:04 PM'."""
    try:
        t = datetime.fromisoformat((iso or "").replace("Z", "+00:00")).astimezone()
    except ValueError:
        return ""
    return t.strftime("%b %d, %I:%M %p").replace(" 0", " ")
