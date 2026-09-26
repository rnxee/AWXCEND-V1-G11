"""AWXCEND look: deep-space panels, blue primary, violet accent. Shared widgets for every screen."""
from datetime import datetime

import flet as ft


class C:
    void = "#05070d"
    panel = "#0b0f1a"
    panel_alt = "#111729"
    border = "#1c2640"
    border_bright = "#2e4270"
    primary = "#2b8cff"
    primary_bright = "#63b3ff"
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


def theme() -> ft.Theme:
    return ft.Theme(
        use_material3=True,
        font_family="Lato",
        color_scheme=ft.ColorScheme(
            primary=C.primary, on_primary="#ffffff", secondary=C.accent, on_secondary=C.void,
            surface=C.panel, on_surface=C.text, error=C.danger, outline=C.border_bright,
            surface_container_highest=C.panel_alt,
        ),
        scaffold_bgcolor=C.void,
        canvas_color=C.panel,
    )


def fade(color: str, alpha: int) -> str:
    """color at alpha/255 opacity (Flet reads 8-digit hex as #AARRGGBB, so never append alpha)."""
    return ft.Colors.with_opacity(round(alpha / 255, 3), color)


# ---- text -------------------------------------------------------------------
def title(text: str, size: int = 20, color: str = C.text) -> ft.Text:
    return ft.Text(text.upper(), font_family="Michroma", size=size, color=color)


def heading(text: str, size: int = 16, color: str = C.text) -> ft.Text:
    return ft.Text(text, font_family="LatoBlack", size=size, color=color)


def label(text: str, color: str = C.dim, size: int = 12) -> ft.Text:
    return ft.Text(text.upper(), size=size, color=color, font_family="LatoBold")


def body(text: str, color: str = C.dim, size: int = 14, **kw) -> ft.Text:
    return ft.Text(text, color=color, size=size, **kw)


def num(value, size: int = 24, color: str = C.text) -> ft.Text:
    return ft.Text(f"{value:,}" if isinstance(value, int) else str(value), font_family="LatoBlack", size=size, color=color)


# ---- surfaces ---------------------------------------------------------------
def card(content: ft.Control, padding: int = 16, on_click=None, accent: str | None = None, **kw) -> ft.Container:
    return ft.Container(
        content=content, padding=padding, bgcolor=C.panel, border_radius=14, on_click=on_click,
        border=ft.Border.all(1, accent or C.border), ink=on_click is not None, **kw,
    )


def stat(caption: str, value, color: str = C.text, icon: ft.IconData | None = None) -> ft.Container:
    top = [ft.Icon(icon, size=16, color=color)] if icon else []
    return card(ft.Column([ft.Row(top + [label(caption, size=11)], spacing=6), num(value, 22, color)], spacing=4),
                padding=12, expand=True)


def xp_bar(progress: float, color: str = C.primary) -> ft.ProgressBar:
    return ft.ProgressBar(value=max(0.0, min(progress, 1.0)), color=color, bgcolor=C.border, bar_height=8, border_radius=4)


# ---- inputs -----------------------------------------------------------------
def field(lbl: str, **kw) -> ft.TextField:
    return ft.TextField(label=lbl, border_radius=10, border_color=C.border_bright, filled=True,
                        fill_color=C.panel_alt, **kw)


def number_field(lbl: str, value="", decimals: bool = False, **kw) -> ft.TextField:
    pattern = r"^\d*\.?\d{0,2}$" if decimals else r"^\d*$"
    return field(lbl, value=str(value), keyboard_type=ft.KeyboardType.NUMBER,
                 input_filter=ft.InputFilter(regex_string=pattern, allow=True), **kw)


def dropdown(lbl: str, options: list[tuple[str, str]], value: str | None = None, **kw) -> ft.Dropdown:
    return ft.Dropdown(label=lbl, value=value, options=[ft.DropdownOption(key=k, text=t) for k, t in options],
                       border_radius=10, border_color=C.border_bright, filled=True, fill_color=C.panel_alt, **kw)


def button(text: str, on_click=None, icon=None, kind: str = "primary", **kw) -> ft.Control:
    if kind == "ghost":
        return ft.OutlinedButton(content=text, icon=icon, on_click=on_click, **kw)
    if kind == "text":
        return ft.TextButton(content=text, icon=icon, on_click=on_click, **kw)
    color = {"primary": C.primary, "danger": C.danger, "camera": C.camera, "food": C.food, "accent": C.accent}[kind]
    fg = C.void if kind in ("camera", "food", "accent") else "#ffffff"
    return ft.FilledButton(content=text, icon=icon, on_click=on_click, bgcolor=color, color=fg, **kw)


def chips(options: list[tuple[str, str]], selected: str, on_pick) -> ft.Row:
    """A row of single-select chips (tabs). on_pick(key) is called with the chosen key."""
    row = ft.Row(wrap=True, spacing=8, run_spacing=8)

    def render(current):
        row.controls = [
            ft.Chip(label=ft.Text(t), selected=k == current, selected_color=fade(C.primary, 0x44),
                    bgcolor=C.panel_alt, on_select=lambda e, k=k: pick(k))
            for k, t in options
        ]

    def pick(k):
        render(k)
        row.update()
        on_pick(k)

    render(selected)
    return row


# ---- states -----------------------------------------------------------------
def loading(text: str = "Loading...") -> ft.Control:
    return ft.Container(ft.Row([ft.ProgressRing(width=18, height=18, stroke_width=2, color=C.accent), body(text)],
                               alignment=ft.MainAxisAlignment.CENTER), padding=24)


def empty(text: str, icon=ft.Icons.INBOX_OUTLINED) -> ft.Control:
    return ft.Container(ft.Column([ft.Icon(icon, color=C.faint, size=32), body(text, text_align=ft.TextAlign.CENTER)],
                                  horizontal_alignment=ft.CrossAxisAlignment.CENTER), padding=24,
                        alignment=ft.Alignment.CENTER)


def error_box(text: str, on_retry=None) -> ft.Control:
    items = [ft.Icon(ft.Icons.ERROR_OUTLINE, color=C.danger), ft.Text(text, color=C.danger, expand=True)]
    if on_retry:
        items.append(button("Retry", lambda e: on_retry(), kind="text"))
    return card(ft.Row(items), accent=fade(C.danger, 0x88))


def avatar(name: str, size: int = 40, color: str = C.primary) -> ft.CircleAvatar:
    return ft.CircleAvatar(content=ft.Text((name or "?")[:1].upper(), font_family="LatoBlack"),
                           bgcolor=fade(color, 0x33), color=color, radius=size / 2)


def rank_text(p: dict) -> str:
    rank = p.get("rank") or "Unranked"
    sub = p.get("rank_sub_index")
    return f"{rank} {sub}" if sub else rank


def screen(heading_text: str, *controls: ft.Control, actions: list[ft.Control] | None = None,
           subtitle: str | None = None) -> ft.Control:
    """Standard page: title row, then content, centred and capped for wide windows."""
    head = [ft.Column([title(heading_text, 18)] + ([body(subtitle, size=13)] if subtitle else []), spacing=2, expand=True)]
    col = ft.Column([ft.Row(head + (actions or []), vertical_alignment=ft.CrossAxisAlignment.CENTER), *controls],
                    spacing=14, scroll=ft.ScrollMode.AUTO, expand=True)
    return ft.Container(ft.Container(col, width=MAX_WIDTH, expand=True), padding=ft.Padding.symmetric(horizontal=16, vertical=16),
                        alignment=ft.Alignment.TOP_CENTER, expand=True)


def when(iso: str) -> str:
    """Server timestamp -> local 'Sep 26, 3:04 PM'."""
    try:
        t = datetime.fromisoformat((iso or "").replace("Z", "+00:00")).astimezone()
    except ValueError:
        return ""
    return t.strftime("%b %d, %I:%M %p").replace(" 0", " ")
