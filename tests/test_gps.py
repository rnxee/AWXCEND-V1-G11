"""GPS distance: honest movement counts; drift, jumps and weak readings don't."""
from gps import MAX_ACCURACY_M, Track, haversine_m

LAT, LON = 14.5995, 120.9842
M_PER_DEG_LAT = 111_195.0  # metres in one degree of latitude


def north(metres: float) -> float:
    return LAT + metres / M_PER_DEG_LAT


def test_haversine_matches_a_degree_of_latitude():
    assert abs(haversine_m(LAT, LON, LAT + 1, LON) - M_PER_DEG_LAT) < 150
    assert haversine_m(LAT, LON, LAT, LON) == 0


def test_walking_in_a_straight_line_adds_up():
    track = Track()
    results = [track.add(north(i * 10), LON, 5.0, i * 8.0) for i in range(11)]  # 10 m every 8 s = 1.25 m/s
    assert results == ["start"] + ["counted"] * 10
    assert abs(track.distance_m - 100) < 1


def test_standing_still_adds_nothing():
    track = Track()
    track.add(LAT, LON, 8.0, 0)
    for i in range(1, 30):  # 2 m of drift each way, every 5 s
        assert track.add(north(2 if i % 2 else -2), LON, 8.0, i * 5.0) == "still"
    assert track.distance_m == 0


def test_weak_or_unreported_accuracy_is_ignored():
    track = Track()
    assert track.add(LAT, LON, MAX_ACCURACY_M + 1, 0) == "weak"
    assert track.add(LAT, LON, 0, 1) == "weak"      # the plugin reports 0 when it has no value
    assert track.add(LAT, LON, None, 2) == "weak"
    assert track.last is None                      # nothing was accepted, not even as a start


def test_a_gps_jump_is_not_counted_but_tracking_carries_on():
    track = Track()
    track.add(LAT, LON, 5.0, 0)
    assert track.add(north(500), LON, 5.0, 5) == "jump"      # 100 m/s
    assert track.add(north(8), LON, 5.0, 8) == "counted"     # the real next step, measured from the old point
    assert abs(track.distance_m - 8) < 0.1


def test_readings_out_of_order_are_ignored():
    track = Track()
    track.add(LAT, LON, 5.0, 10)
    assert track.add(north(20), LON, 5.0, 10) == "late"
    assert track.add(north(20), LON, 5.0, 4) == "late"


def test_after_a_pause_the_trip_in_between_is_not_counted():
    track = Track()
    track.add(LAT, LON, 5.0, 0)
    track.add(north(10), LON, 5.0, 8)
    track.break_here()                                  # paused; carried on from far away
    assert track.add(north(5000), LON, 5.0, 600) == "start"
    assert track.add(north(5010), LON, 5.0, 608) == "counted"
    assert abs(track.distance_m - 20) < 0.2


def test_a_tiny_step_from_a_very_accurate_fix_is_still_drift():
    track = Track()
    track.add(LAT, LON, 2.0, 0)
    assert track.add(north(2), LON, 2.0, 5) == "still"   # under the 3 m floor even though accuracy/2 is 1 m
    assert track.add(north(4), LON, 2.0, 10) == "counted"
