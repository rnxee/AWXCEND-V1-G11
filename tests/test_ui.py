"""UI helpers that don't need a running page: timestamps, workout lines, number fields, dialogs."""
import re

import flet as ft
import pytest

import ui
from main import App
from views.home import workout_line


def test_timestamps_without_a_zone_are_utc():
    # workout_logs.logged_at and chat_messages.created_at arrive without a zone, but hold UTC
    assert ui.when("2026-10-16T02:15:00.123456") == ui.when("2026-10-16T02:15:00.123456+00:00")
    assert ui.when("") == "" and ui.when("not a date") == ""


def test_workout_lines():
    assert workout_line({"exercise": "barbellbicepscurl", "sets": 3, "reps": 12, "weight_kg": 32.5}) \
        == "Barbell Bicep Curl · 3×12 · 32.5 kg"
    assert workout_line({"exercise": "plank", "duration_seconds": 45}) == "Plank · 0:45"
    assert workout_line({"exercise": "plank", "sets": None, "reps": None}) == "Plank"  # a public profile's row


@pytest.mark.parametrize("text,ok", [
    ("", True), ("72", True), ("72.", True), ("72.5", True), ("72.55", True), (".5", True),
    (".", False), ("72.555", False), ("7.2.5", False), ("a", False),
])
def test_decimal_fields_only_take_what_float_can_read(text, ok):
    # Flet refuses a keystroke whose result doesn't match the pattern (checked in a live field)
    pattern = ui.number_field("Weight", decimals=True).input_filter.regex_string
    assert bool(re.fullmatch(pattern, text)) is ok
    if ok and text:
        float(text)


def test_closing_a_form_also_closes_the_toast_shown_over_it():
    open_dialogs = [ft.SnackBar(ft.Text("Pick a reason.")), ft.AlertDialog()]  # newest first

    class Page:  # like Flet: pop_dialog() closes the newest open dialog, and a toast is one
        def pop_dialog(self):
            return open_dialogs.pop(0) if open_dialogs else None

    app = App.__new__(App)
    app.page = Page()
    app.close_dialog()
    assert open_dialogs == []


def test_text_fields_block_invisible_characters_but_passwords_are_untouched():
    import re

    import ui
    f = ui.field("Message")
    assert f.input_filter.allow is False and f.input_filter.regex_string == ui.BAD_CHARS
    assert ui.field("Password", password=True).input_filter is None
    assert ui.number_field("Reps").input_filter.allow is True  # its own digits-only filter wins
    hidden = "".join(map(chr, (0x200B, 0x202E, 0x0, 0xFEFF)))
    assert re.sub(ui.BAD_CHARS, "", f"hi{hidden}\tthere\n") == "hi\tthere\n"
    assert re.sub(ui.BAD_CHARS, "", chr(0x1F468) + chr(0x200D) + chr(0x1F469)) == chr(0x1F468) + chr(0x200D) + chr(0x1F469)


def test_chat_word_limit():
    from views.social import MAX_CHAT_WORDS, too_long
    assert too_long(" ".join(["rep"] * MAX_CHAT_WORDS)) is None
    assert too_long(" ".join(["rep"] * (MAX_CHAT_WORDS + 1))) == "Keep messages to 100 words (this one has 101)."
