"""Rep counters: synthetic poses in, rep counts out. No camera, no MediaPipe."""
import math
from types import SimpleNamespace as P

import pytest

from pose.counters import EXERCISES, RepCounter, angle


def lm(points: dict[int, tuple[float, float]], vis: float = 0.9):
    """33 landmarks, invisible except the ones given."""
    out = [P(x=0.0, y=0.0, visibility=0.0) for _ in range(33)]
    for i, (x, y) in points.items():
        out[i] = P(x=x, y=y, visibility=vis)
    return out


def limb(a, b_angle_deg, length=0.2):
    """Point `length` away from `a` in direction `b_angle_deg` (0 = right, 90 = down)."""
    r = math.radians(b_angle_deg)
    return (a[0] + length * math.cos(r), a[1] + length * math.sin(r))


def leg(hip, knee_angle, thigh_dir=90):
    """Hip, knee, ankle with the given inner knee angle (180 = straight)."""
    knee = limb(hip, thigh_dir)
    ankle = limb(knee, thigh_dir + (180 - knee_angle))
    return hip, knee, ankle


def squat_pose(left_knee, right_knee):
    lh, lk, la = leg((0.45, 0.5), left_knee)
    rh, rk, ra = leg((0.55, 0.5), right_knee)
    return lm({11: (0.45, 0.3), 12: (0.55, 0.3), 23: lh, 24: rh, 25: lk, 26: rk, 27: la, 28: ra})


def arm_pose(elbow_angle, side="left", upper_dir=90, body_flat=False):
    """Shoulder-elbow-wrist on one side; body vertical unless body_flat (push-up)."""
    sh = (0.5, 0.3)
    el = limb(sh, upper_dir)
    wr = limb(el, upper_dir + (180 - elbow_angle))
    hip = (0.8, 0.32) if body_flat else (0.5, 0.6)
    s, e, w, h = (11, 13, 15, 23) if side == "left" else (12, 14, 16, 24)
    return lm({s: sh, e: el, w: wr, h: hip})


def run(counter, poses, dt=0.1, hold=True):
    """Feed poses at a steady frame rate. Real sets start by holding the first position for a moment
    (the counter needs READY_S of it), so by default the first pose is held for 0.6 s first."""
    if hold and poses:
        poses = [poses[0]] * (int(0.6 / dt) + 1) + list(poses)
    t = 0.0
    for p in poses:
        counter.update(p, t)
        t += dt
    return counter.reps


def test_angle_right_and_straight():
    assert angle((0, 1), (0, 0), (1, 0)) == pytest.approx(90)
    assert angle((-1, 0), (0, 0), (1, 0)) == pytest.approx(180)


def squat_rep():
    return [squat_pose(a, a) for a in (175, 150, 120, 90, 80, 90, 120, 150, 175)]


def test_squat_counts_full_reps():
    c = RepCounter("squat")
    assert run(c, squat_rep() * 3) == 3


def test_knee_raise_is_not_a_squat():
    c = RepCounter("squat")
    knee_raise = [squat_pose(a, 178) for a in (175, 120, 80, 60, 80, 120, 175)]
    assert run(c, knee_raise * 3) == 0


def test_half_squat_does_not_count_and_says_why():
    c = RepCounter("squat")
    half = [squat_pose(a, a) for a in (175, 150, 130, 125, 130, 150, 175)]
    assert run(c, half) == 0
    assert "lower" in c.feedback.lower()


def test_starting_mid_rep_does_not_count_the_first_half():
    c = RepCounter("squat")
    from_bottom = [squat_pose(a, a) for a in (85, 85, 85, 120, 150, 175)]  # tracking starts mid-squat
    stand = [squat_pose(175, 175)] * 6
    assert run(c, from_bottom + stand + squat_rep(), hold=False) == 1  # only the full rep after it counts


def test_movement_while_getting_into_position_is_not_a_rep():
    # Setting up: two separate 0.2 s flashes of straight arms, each followed by a dip slow enough to pass
    # as a rep. Neither flash is a steady start (and together they don't add up to one), so neither counts.
    c = RepCounter("pushup")
    flash = (170, 172, 70, 60, 65, 70)
    setup = [arm_pose(a, body_flat=True) for a in (80,) + flash + flash]
    plank = [arm_pose(175, body_flat=True)] * 8
    rep = [arm_pose(a, body_flat=True) for a in (175, 130, 95, 130, 175)]
    assert run(c, setup + plank + rep * 2) == 2  # one continuous clock


def test_moving_around_after_the_set_is_not_a_rep():
    # 2 reps, then stand up (body not level) for 1.5 s, then bend over the phone moving the arms
    rep = [arm_pose(a, body_flat=True) for a in (175, 130, 95, 130, 175)]
    stand = [arm_pose(175, body_flat=False)] * 15
    reach = [arm_pose(a, body_flat=True) for a in (80, 70, 60, 175, 170, 90, 175)]
    c = RepCounter("pushup")
    assert run(c, rep * 2 + stand + reach) == 2


def test_one_bad_frame_mid_set_does_not_disarm():
    rep = [arm_pose(a, body_flat=True) for a in (175, 130, 95, 130, 175)]
    glitch = [arm_pose(175, body_flat=False)]
    c = RepCounter("pushup")
    assert run(c, rep + glitch + rep + glitch + rep) == 3


def test_jitter_at_the_bottom_counts_once():
    c = RepCounter("squat")
    shaky = [squat_pose(a, a) for a in (175, 120, 90, 96, 88, 97, 90, 130, 175)]
    assert run(c, shaky) == 1


def test_too_fast_bounce_is_ignored():
    c = RepCounter("squat")
    assert run(c, squat_rep(), dt=0.02) == 0  # whole "rep" in 0.16 s


def test_invisible_frames_are_skipped_not_counted():
    c = RepCounter("squat")
    hidden = lm({})
    poses = [squat_pose(175, 175), hidden, squat_pose(80, 80), hidden, squat_pose(175, 175)]
    assert run(c, poses) == 1


def test_tracking_dropout_alone_never_makes_a_rep():
    c = RepCounter("squat")
    hidden = lm({}, vis=0.2)
    assert run(c, [squat_pose(175, 175), hidden, hidden, hidden, squat_pose(175, 175)]) == 0
    assert "view" in c.feedback.lower() or c.feedback.startswith("Ready")


def test_no_person_detected_is_just_a_skipped_frame():
    c = RepCounter("squat")
    assert run(c, [squat_pose(175, 175), None, squat_pose(80, 80), None, squat_pose(175, 175)]) == 1
    c.update(None, 9.0)
    assert "view" in c.feedback.lower()


def test_pushup_needs_a_flat_body():
    rep = [175, 140, 100, 80, 100, 140, 175]
    flat = RepCounter("pushup")
    assert run(flat, [arm_pose(a, body_flat=True, upper_dir=90) for a in rep] * 2) == 2
    standing = RepCounter("pushup")
    assert run(standing, [arm_pose(a, body_flat=False) for a in rep] * 2) == 0


def test_shallow_pushup_counts_with_a_depth_tip_but_a_half_one_does_not():
    shallow = RepCounter("pushup")  # bottom 112 deg: past the count line, short of full depth
    assert run(shallow, [arm_pose(a, body_flat=True) for a in (175, 135, 112, 135, 175)]) == 1
    assert "lower" in shallow.feedback.lower()
    full = RepCounter("pushup")
    run(full, [arm_pose(a, body_flat=True) for a in (175, 120, 85, 120, 175)])
    assert full.reps == 1 and full.feedback == "Good rep"
    half = RepCounter("pushup")  # bottom 130 deg: not a rep
    assert run(half, [arm_pose(a, body_flat=True) for a in (175, 135, 130, 135, 175)]) == 0


def test_fast_pushups_with_a_soft_lockout_count_separately():
    c = RepCounter("pushup")  # arms only straighten to 143 deg between quick reps
    poses = [arm_pose(a, body_flat=True) for a in (175, 130, 95, 125, 143, 125, 95, 130, 175)]
    assert run(c, poses) == 2


def test_a_slow_controlled_rep_still_counts():
    c = RepCounter("pushup")  # very slow tempo: ~5 s spent below the lockout line
    down = [175 - i * 2.5 for i in range(39)]  # 175 -> 80 in 0.1 s steps
    assert run(c, [arm_pose(a, body_flat=True) for a in down + down[::-1]]) == 1


def test_getting_into_position_slowly_is_not_a_rep():
    c = RepCounter("pushup")  # kneel with straight arms, lie flat for 8 s, push up into a plank
    poses = [arm_pose(175, body_flat=True)] + [arm_pose(80, body_flat=True)] * 80 + [arm_pose(175, body_flat=True)]
    assert run(c, poses) == 0
    assert run(c, [arm_pose(a, body_flat=True) for a in (175, 120, 90, 120, 175)]) == 1


def test_pushup_uses_the_visible_side():
    rep = [175, 120, 80, 120, 175]
    c = RepCounter("pushup")
    assert run(c, [arm_pose(a, side="right", body_flat=True) for a in rep]) == 1


def test_curl_counts_and_rejects_swinging():
    rep = [170, 120, 70, 40, 70, 120, 170]
    strict = RepCounter("bicep_curl")
    assert run(strict, [arm_pose(a, upper_dir=90) for a in rep] * 2) == 2
    swing = RepCounter("bicep_curl")  # upper arm swung 60 degrees forward at the top
    poses = [arm_pose(a, upper_dir=90 if a > 100 else 30) for a in rep]
    assert run(swing, poses) == 0
    assert "elbow" in swing.feedback.lower()


def sideways(lms):
    """The same pose as it arrives from a phone standing upright while streaming landscape (90 deg turn)."""
    return [P(x=p.y, y=1 - p.x, visibility=p.visibility) for p in lms]


def test_curls_count_even_when_the_video_is_sideways():
    rep = [170, 120, 70, 40, 70, 120, 170]
    c = RepCounter("bicep_curl")
    assert run(c, [sideways(arm_pose(a, upper_dir=90)) for a in rep] * 2) == 2
    swing = RepCounter("bicep_curl")  # still catches a real swing
    assert run(swing, [sideways(arm_pose(a, upper_dir=90 if a > 100 else 30)) for a in rep]) == 0


def test_a_quick_wobble_between_lunges_is_not_a_lunge():
    c = RepCounter("lunge")
    stand = [lunge_pose(175, 175)] * 3
    wobble = [lunge_pose(128, 128)] * 4  # 0.4 s dip: shifting weight, not a lunge
    # a far-leg lunge: the near knee bends deep (so the hips really drop) but the straighter-knee
    # reading only reaches 125 (camera bias on the far leg); a real lunge takes ~1 s or more
    lunge = [lunge_pose(f, b) for f, b in ((175, 175), (140, 150), (115, 135), (95, 128), (90, 125), (90, 125),
                                           (95, 128), (115, 135), (140, 150), (175, 175))]
    assert run(c, stand + wobble + stand + lunge + stand + wobble + stand) == 1


def lunge_pose(front, back, grounded=True, hide_back=False):
    """Side-view lunge. grounded: feet stay on the floor, so bending the knees lowers the hips (real).
    grounded=False keeps the hips still while the knees 'bend' (a tracking wobble, not a lunge).
    hide_back: the far leg is hidden behind the near one (low visibility), as when standing side-on."""
    fh, fk, fa = leg((0.5, 0.5), front, thigh_dir=85)
    bh, bk, ba = leg((0.5, 0.5), back, thigh_dir=95)
    dy = 0.95 - max(fa[1], ba[1]) if grounded else 0.0
    pts = {11: (0.5, 0.3), 12: (0.5, 0.3), 23: fh, 24: bh, 25: fk, 26: bk, 27: fa, 28: ba}
    out = lm({i: (x, y + dy) for i, (x, y) in pts.items()})
    if hide_back:
        for i in (24, 26, 28):
            out[i].visibility = 0.2
    return out


def test_standing_with_the_far_leg_hidden_is_still_standing():
    # between lunges the legs come together and the far leg disappears behind the near one
    down = [lunge_pose(a, a) for a in (150, 130, 110, 95, 95, 110, 130, 150)]
    stand_hidden = [lunge_pose(176, 176, hide_back=True)] * 15  # 1.5 s: longer than the disarm time
    c = RepCounter("lunge")
    assert run(c, stand_hidden + down + stand_hidden + down + stand_hidden) == 2


def test_knees_dipping_without_the_hips_dropping_is_not_a_lunge():
    down = [(150, 150), (130, 130), (110, 110), (100, 100), (100, 100), (110, 110), (130, 130), (150, 150)]
    stand = [lunge_pose(176, 176)] * 6
    real = [lunge_pose(a, b) for a, b in down]
    wobble = [lunge_pose(a, b, grounded=False) for a, b in down]  # same knee angles, hips never move
    c = RepCounter("lunge")
    assert run(c, stand + real + stand + wobble + stand + real + stand) == 2


def test_lunge_needs_both_knees_bent():
    c = RepCounter("lunge")
    # about 1 s per lunge, like a real one
    down = ((150, 150), (140, 145), (125, 130), (95, 110), (95, 110))
    rep = [lunge_pose(a, b) for a, b in ((175, 175),) + down + down[::-1] + ((175, 175),)]
    assert run(c, rep * 2) == 2
    one_leg = RepCounter("lunge")
    kick = [lunge_pose(a, 176) for a in (175, 150, 140, 125, 90, 90, 125, 140, 150, 175)]
    assert run(one_leg, kick * 2) == 0


def test_every_exercise_has_a_label_and_setup_tip():
    for key, ex in EXERCISES.items():
        assert ex.label and ex.tip, key
