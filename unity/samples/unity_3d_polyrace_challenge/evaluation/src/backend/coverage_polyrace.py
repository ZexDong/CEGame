import copy
import math
import re
import time
from session_core import n, sn, nums, actor, pos, xyz, fact, text, visible, ProductError, InfrastructureError
from coverage_common import feedback_changed, frozen_state, equivalent, number_label


def race_time_visible(reply, value):
    if number_label(reply, "time", value):
        return True
    # A readable seconds unit is a semantic time label too (e.g. 00.00s).
    # Do not confuse SPD/SHD or an arbitrary unlabelled number with seconds.
    # In "elapsed / limit s", the unit applies to the entire ratio and elapsed
    # is the numerator.  Consume the denominator as part of the same match so
    # it cannot itself be mistaken for the current elapsed time.
    for match in re.finditer(r"(?<![\d./])(\d+(?:\.\d+)?)(?:\s*/\s*(\d+(?:\.\d+)?))?\s*(?:s|secs?|seconds?)\b", text(reply), re.I):
        token = match[1]
        precision = len(token.partition(".")[2]) if "." in token else 0
        tolerance = .51 * 10 ** -precision if precision else .01
        if abs(float(token) - value) <= tolerance:
            return True
    return False


class PolyRaceChecks:
    def assert_race_hud(self, reply, fields, leaf="d5.hud"):
        for label, value in fields.items():
            valid = race_time_visible(reply, value) if label == "time" else number_label(reply, label, value)
            self.check(leaf, valid, f"Actual rendered semantic HUD {label} matches {value}")

    def polyrace(self):
        super().polyrace()
        for name, leaves, requirements, fn in [
            ("PR/all-natural-selections-countdown", ["d2.motion", "d3.motion", "d2.terrain", "d5.controls", "d5.hud"], ["PR-01", "PR-02", "PR-09"], self.pr_selections),
            ("PR/all-craft-coast-brake-limits-steering", ["d3.motion", "d2.boost", "d3.boost", "d5.feedback"], ["PR-02", "PR-03", "PR-09"], self.pr_tuning),
            ("PR/all-craft-contact-grace-regeneration", ["d2.shield", "d3.shield", "d3.boost"], ["PR-03", "PR-04", "PR-08"], self.pr_collisions),
            ("PR/continuous-ramps-and-real-road", ["d2.terrain", "d3.terrain"], ["PR-01", "PR-03", "PR-06"], self.pr_terrain),
            ("PR/all-spatial-pickup-boundaries-cap", ["d2.pickups", "d3.pickups"], ["PR-05"], self.pr_pickups),
            ("PR/six-natural-races-and-result-freeze", ["d2.race", "d3.race", "d4.journey", "d4.restart", "d5.hud", "d5.overlays"], ["PR-06", "PR-07", "PR-08", "PR-09"], self.pr_journeys),
            ("PR/fastest-record-isolation-and-retry", ["d3.race", "d4.reopen"], ["PR-07", "PR-08"], self.pr_records),
        ]:
            self.obligation(name, leaves, requirements, fn)

    def pr_selections(self):
        for track in range(1, 4):
            for mode in [0, 1]:
                for car in self.content["vehicles"]:
                    self.p.call("reset", seconds=0)
                    for control in [f"track_{track}", "mode_time" if mode == 0 else "mode_distance", "craft_" + str(car["id"])]:
                        self.click(control)
                    r = self.start()
                    s = self.validate(r)
                    self.check("d2.motion", n(s, "track") == track and n(s, "mode") == mode and n(s, "vehicle") == car["id"]
                               and abs(n(s, "shield") - car["shield"]) < .01
                               and abs(actor(s, "racer")["position"]["y"] - car["hover_height"]) < .1,
                               "Every ordinary track/mode/craft selection launches its actual fresh selected craft/course")
                    self.check("d5.controls", s["phase"] == "playing", "Ordinary controls are genuinely raycast/click-operated")
                    track_content = self.content["tracks"][track-1]
                    self.check("d2.terrain", all(
                        abs(actor(s, item["id"])["position"]["x"] - item["x"]) < .03
                        and abs(actor(s, item["id"])["position"]["z"] - item["z"]) < .03
                        and fact(r, item["id"]).get("renderers", 0) > 0
                        for item in track_content["obstacles"] + track_content["rings"]),
                        "Every natural selection exposes the correct actual course obstacle/ring locations and real renderer geometry")
                    self.assert_race_hud(r, {"track": n(s, "track"), "shield": n(s, "shield"), "speed": n(s, "speed"),
                                        "time": n(s, "elapsed"), "gates": n(s, "next_gate"), "points": n(s, "score")})
        self.fresh()
        self.p.call("begin", seconds=0)
        r = self.key("W", .05, label="hold")
        first = self.validate(r)
        r = self.idle(2.35)
        s = self.validate(r)
        self.check("d3.motion", n(s, "countdown") > 0 and n(s, "speed") == 0 and n(s, "elapsed") == 0
                   and actor(s, "racer")["position"]["z"] == 2,
                   "Countdown blocks throttle for the full first2.35s, not only the first frame")
        r = self.idle(.9)
        s = self.validate(r)
        self.check("d3.motion", n(s, "countdown") == 0 and n(s, "elapsed") > 0 and n(s, "speed") > 0,
                   "The3s countdown actually completes and releases normal input")
        self.p.call("release", seconds=0)

    def pr_tuning(self):
        for car in self.content["vehicles"]:
            for boost in [False, True]:
                limit = car["max_speed"] * (1.4 if boost else 1)
                self.setup(lambda s: self.race_setup(s, vehicle=car["id"], speed=limit - .3))
                r = self.key("UpArrow,LeftShift" if boost else "UpArrow", .05, label="hold")
                r = self.idle(.3)
                s = self.validate(r)
                self.check("d3.boost" if boost else "d3.motion", abs(n(s, "speed") - limit) < .08,
                           "Actual " + car["name"] + (" boost max1.4x" if boost else " normal maximum") + " is exact")
                self.p.call("release", seconds=0)
                if boost:
                    before = self.validate(self.p.last)
                    r = self.key("W", .05, label="hold")
                    after = self.validate(r)
                    self.check("d3.boost", n(after, "speed") <= n(before, "speed") + .01
                               and n(after, "speed") > car["max_speed"] - .1,
                               "Release decreases boost speed towards normal limit, rather than accelerating or dropping to zero")
                    self.p.call("release", seconds=0)
            for key, rate in [("", 2), ("DownArrow", 20)]:
                self.setup(lambda s: self.race_setup(s, vehicle=car["id"], speed=12))
                r0 = self.key(key or "None", .04, label="hold") if key else self.idle(.04)
                s0 = self.validate(r0)
                r = self.idle(.25)
                s = self.validate(r)
                dt = n(s, "elapsed") - n(s0, "elapsed")
                observed = (n(s0, "speed") - n(s, "speed")) / dt
                self.check("d3.motion", abs(observed - rate) < .65,
                           f"{car['name']} {'brakes' if key else 'coasts'} at declared {rate}/s over continuous measured elapsed time; actual={observed:.4f}")
                self.p.call("release", seconds=0)
            for key, direction in [("RightArrow", 1), ("LeftArrow", -1)]:
                self.setup(lambda s: self.race_setup(s, vehicle=car["id"]))
                r0 = self.key(key, .04, label="hold")
                s0 = self.validate(r0)
                r = self.p.call("observe", seconds=.2, watch="racer")
                s = self.validate(r)
                dx = actor(s, "racer")["position"]["x"] - actor(s0, "racer")["position"]["x"]
                dt = n(s, "elapsed") - n(s0, "elapsed")
                self.check("d3.motion", abs(dx / dt - direction * car["steering"]) < .2,
                           "Arrow alias uses exact craft-specific real steering rate")
                self.check("d5.feedback", any(abs(q["euler"]["y"]) > 1 or abs(q["euler"]["z"]) > 1 for q in r.get("motion") or []),
                           "Steering has independently observed actual yaw/bank feedback")
                self.p.call("release", seconds=0)
            self.setup(lambda s: self.race_setup(s, vehicle=car["id"], speed=10))
            before = self.p.last
            self.key("W,LeftShift", .05, label="hold")
            r = self.idle(.25)
            self.check("d2.boost", n(self.validate(r), "boost") == 1 and visible(r, "racer"), "Each craft actually enters boost")
            self.check("d5.feedback", fact(r, "racer").get("particles", 0) > fact(before, "racer").get("particles", 0)
                       or feedback_changed(before, r) or fact(r, "racer").get("visualSignature") != fact(before, "racer").get("visualSignature"),
                       "Boost produces actual particle/material/UI feedback")
            self.p.call("release", seconds=0)
        for fps in [30, 90]:
            self.setup(lambda s: self.race_setup(s))
            self.p.call("set-fps", seed=fps, seconds=.2)
            r0 = self.key("W", .08, label="hold")
            s0 = self.validate(r0)
            s = self.validate(self.idle(.35))
            dt = n(s, "elapsed") - n(s0, "elapsed")
            self.check("d3.motion", abs((n(s, "speed") - n(s0, "speed")) / dt - self.content["vehicles"][0]["acceleration"]) < .4,
                       "Measured acceleration remains elapsed-time based at external frame cap" + str(fps))
            self.p.call("release", seconds=0)
        self.p.call("set-fps", seed=60, seconds=.05)

    def pr_collisions(self):
        for car in self.content["vehicles"]:
            for boosting in [False, True]:
                self.setup(lambda s: self.race_setup(s, x=5.25, speed=0, vehicle=car["id"]))
                r = self.p.call("key", key="D,LeftShift" if boosting else "D", label="hold", seconds=.26, watch="racer")
                s = self.validate(r)
                expected = max(0, car["shield"] - car["collision_cost"] * (2 if boosting else 1))
                self.check("d3.boost" if boosting else "d3.shield",
                           abs(n(s, "shield") - expected) < .03 and abs(actor(s, "racer")["position"]["x"] - 5.5) < .02,
                           f"{car['name']} real rail contact bounds x and debits exact {'double' if boosting else 'ordinary'} cost")
                self.check("d2.shield", n(s, "shield") < car["shield"], "Each craft has a real spatial rail collision")
                self.p.call("release", seconds=0)
            # Sustained contact: record first and second observed debit times.
            self.setup(lambda s: self.race_setup(s, x=5.25, speed=0, vehicle=car["id"]))
            r = self.p.call("key", key="D", label="hold", seconds=1.4, watch="racer")
            events = []
            previous = car["shield"]
            for q in r.get("motion") or []:
                values = nums(q.get("values"))
                if values.get("shield", previous) < previous - .1:
                    events.append(q)
                previous = values.get("shield", previous)
            self.check("d3.shield", len(events) >= 2 and all(.55 <= b["time"] - a["time"] <= .72 for a, b in zip(events, events[1:])),
                       "Sustained real rail contact applies0.6s grace, not damage every frame")
            self.p.call("release", seconds=0)
            # A fresh normal input contact followed by leaving the rail supplies
            # a real cooldown; no assumed implementation-private timer.
            self.setup(lambda s: self.race_setup(s, x=5.25, speed=0, vehicle=car["id"]))
            self.key("D", .16)
            self.key("A", .25)
            baseline = self.validate(self.p.last)
            amount = n(baseline, "shield")
            self.idle(.8)
            s = self.validate(self.p.last)
            self.check("d3.shield", n(s, "shield") == amount, "Shield does not regenerate during real recent-contact delay")
            self.idle(1.7)
            r0 = self.p.last
            s0 = self.validate(r0)
            r = self.idle(.4)
            s = self.validate(r)
            dt = n(s, "elapsed") - n(s0, "elapsed")
            expected = min(car["shield"], n(s0, "shield") + car["regen"] * dt)
            self.check("d3.shield", abs(n(s, "shield") - expected) < .08 and n(s, "shield") > amount,
                       f"{car['name']} actual regeneration rate{car['regen']}/s begins after contact delay and respects capacity")
        # Collision slowdown is observed in consecutive genuine engine frames.
        ob = self.content["tracks"][0]["obstacles"][0]
        self.setup(lambda s: self.race_setup(s, x=ob["x"], z=ob["z"] - 4, speed=12))
        r = self.p.call("key", key="W", label="hold", seconds=.5, watch="racer")
        trace = r.get("motion") or []
        pairs = [(a, b) for a, b in zip(trace, trace[1:]) if nums(b["values"])["shield"] < nums(a["values"])["shield"]]
        self.check("d3.shield", bool(pairs) and all(abs(nums(b["values"])["speed"] / nums(a["values"])["speed"] - .35) < .04 for a, b in pairs),
                   "Actual obstacle collision changes live forward speed to35%, with real pose observations")
        self.p.call("release", seconds=0)

    def pr_terrain(self):
        for track in self.content["tracks"]:
            entry = "track_" + str(track["id"]) + "_time"
            for car in self.content["vehicles"]:
                start = track["ramp_start"] - 1.5
                self.setup(lambda s: self.race_setup(s, z=start, speed=8, gate=1, vehicle=car["id"]), entry)
                r = self.p.call("key", key="W", label="hold", seconds=4.7, watch="racer")
                self.p.call("release", seconds=0)
                samples = r.get("motion") or []
                self.check("d3.terrain", samples and all(abs(q["position"]["y"] - self.height(track, q["position"]["z"]) - car["hover_height"]) < .16 for q in samples),
                           "Continuous actual ascent/peak/descent respects every selected craft hover height")
                surfaces = fact(r, "road").get("surfaces") or []
                raised = [q for q in surfaces if q["center"]["y"] + q["size"]["y"] / 2 > track["ramp_height"] * .65]
                self.check("d2.terrain", bool(raised), "Actual road renderer geometry, not just racer height, contains a raised ramp")
                # The trace must include the peak; pause/coast gives enough
                # extent without finishing the race or crossing the finish gate.
                self.check("d3.terrain", any(q["position"]["z"] >= track["ramp_peak"] for q in samples)
                           and any(q["position"]["z"] <= track["ramp_start"] for q in samples)
                           and any(q["position"]["z"] >= track["ramp_end"] for q in samples),
                           "Ramp check observes continuous approach, peak and descent rather than restoring directly to peak")

    def pr_pickups(self):
        for track in self.content["tracks"]:
            for index, ring in enumerate(track["rings"]):
                # Full shield removes regen ambiguity: collection must still cap.
                def approach(s):
                    self.race_setup(s, x=ring["x"], z=ring["z"] - 2.2, speed=8,
                                    gate=sum(g < ring["z"] - 2.2 for g in track["gates"]))
                self.setup(approach, f"track_{track['id']}_distance")
                r = self.key("W", .3)
                s = self.validate(r)
                bonus = n(s, "score") - math.floor(actor(s, "racer")["position"]["z"] - 2)
                self.check("d2.pickups", actor(s, ring["id"])["state"] == "collected" and not fact(r, ring["id"]).get("active", False),
                           "Every actual ring in every track is spatially collected and disappears")
                self.check("d3.pickups", bonus == 100 and n(s, "shield") == self.content["vehicles"][0]["shield"],
                           "Every ring grants one100 bonus and clamps +10 at full shield")
        ring = self.content["tracks"][0]["rings"][0]
        for offset, collected in [(.82, True), (1.02, False)]:
            self.setup(lambda s: self.race_setup(s, x=ring["x"] + offset, z=ring["z"] - 2.2, speed=8),
                       "track_1_distance")
            r = self.key("W", .3)
            self.check("d3.pickups", (actor(self.validate(r), ring["id"])["state"] == "collected") == collected,
                       "Real crossing tests either side of declared0.9 lateral collection radius")
        # Pause approaching a ring, then resume across it with unchanged state.
        self.setup(lambda s: self.race_setup(s, x=ring["x"], z=ring["z"] - 2.2, speed=4),
                   "track_1_distance")
        r = self.click("pause")
        before = self.validate(r)
        after = self.validate(self.key("W", .5))
        self.check("d4.pause", equivalent(frozen_state(before), frozen_state(after)), "Pause freezes actual imminent pickup and racer state")
        self.click("resume")
        r = self.key("W", .5)
        self.check("d3.pickups", actor(self.validate(r), ring["id"])["state"] == "collected", "Resumed normal approach still collects exactly the same pending ring")

    def pr_journeys(self):
        for entry in self.model["entries"]:
            track_index = int(entry.split("_")[1])
            mode = entry.split("_")[2]
            self.p.call("reset", seconds=0)
            for control in ["track_" + str(track_index), "mode_" + mode, "craft_0"]:
                self.click(control)
            self.start()
            self.key("W", .05, label="hold")
            r = self.wait_until(lambda s: s["phase"] != "playing", 24, .2)
            s = self.validate(r)
            self.p.call("release", seconds=0)
            self.check("d2.race", s["phase"] == "won" and n(s, "next_gate") == 3,
                       "Normal unedited full race crosses all three ordered gates from its actual countdown")
            self.check("d5.hud", race_time_visible(r, n(s, "elapsed")),
                       "Truthful completed-race time is readable at nonzero elapsed time, not a constant zero label")
            self.check("d4.journey", s["phase"] == "won", "Ordinary whole track/mode race has reachable stable success")
            if s["phase"] == "won":
                before = self.validate(self.p.last)
                after = self.validate(self.key("W,D,LeftShift", .4))
                self.assert_stable(before, after)
                if track_index == 3:
                    r = self.click("next")
                    self.check("d5.overlays", bool(re.search("campaign|complete|trials|victory", text(r), re.I)),
                               "Track3 Next has an actual visible campaign conclusion")
        def early(s):
            self.race_setup(s, z=10, speed=0, gate=0)
            sn(s, "elapsed", 400)
        self.setup(early)
        self.check("d3.race", self.validate(self.idle(.3))["phase"] == "playing",
                   "Elapsed time alone cannot finish Time Attack with no gate crossings")
        # Preserve a collected history and changed craft, then prove Retry resets
        # gameplay content rather than merely resetting the displayed timer.
        def dirty(s):
            self.race_setup(s, vehicle=2, z=30, speed=10)
            ring = actor(s, "ring_0")
            ring["state"], ring["present"] = "collected", False
            sn(s, "score", 100)
        self.setup(dirty)
        self.key("Escape")
        r = self.click("restart")
        s = self.validate(r)
        self.check("d4.restart", n(s, "vehicle") == 2 and n(s, "shield") == self.content["vehicles"][2]["shield"]
                   and n(s, "speed") == 0 and n(s, "next_gate") == 0 and n(s, "countdown") > 2
                   and all(a["state"] == "active" and a["present"] for a in s["actors"] if a["kind"] == "ring")
                   and all(a["state"] == "pending" for a in s["actors"] if a["kind"] == "gate"),
                   "Paused Retry preserves selected craft but restores shield/countdown/all rings/all gates/no residual speed")

    def pr_finish_time(self, entry, car, elapsed):
        track = self.content["tracks"][int(entry.split("_")[1]) - 1]
        def prepare(s):
            self.race_setup(s, z=track["length"] - .8, speed=8, gate=2, vehicle=car)
            sn(s, "elapsed", elapsed)
        self.setup(prepare, entry)
        r = self.key("W", .15)
        self.check("d3.race", self.validate(r)["phase"] == "won", "Record is earned only by real final crossing")
        return self.validate(r)

    def pr_records(self):
        # Start from whichever previous legitimate records the evaluator earned;
        # do not fabricate persistence using edited best_time fields.
        self.p.call("reset", seconds=0)
        self.fresh("track_1_time")
        initial = n(self.validate(self.p.last), "best_time")
        good_time = min(3, initial / 2) if initial > 0 else 3
        first = self.pr_finish_time("track_1_time", 0, good_time)
        record = n(first, "best_time")
        slower = self.pr_finish_time("track_1_time", 0, good_time + 5)
        self.check("d3.race", abs(n(slower, "best_time") - record) < .01,
                   "A slower successful race never overwrites faster successful record")
        other = self.pr_finish_time("track_2_time", 1, 9)
        self.fresh("track_1_time")
        self.check("d4.reopen", abs(n(self.validate(self.p.last), "best_time") - record) < .01,
                   "Another track/craft record does not overwrite the first track/craft record")
