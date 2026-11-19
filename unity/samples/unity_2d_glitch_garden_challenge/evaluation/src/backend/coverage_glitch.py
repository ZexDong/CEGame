import copy
import math
import re
import time
from session_core import n, sn, actor, pos, xyz, fact, text, visible, ProductError, InfrastructureError
from coverage_common import feedback_changed, frozen_state, equivalent, number_label, bounds_size, bounds_center


def garden_progress_visible(reply, spawned, total_waves, live_enemies):
    pending = total_waves - spawned
    # The public wording permits spawned/remaining waves, live enemies, or all
    # still-to-defeat invaders (pending + live).  Do not force one HUD design.
    return (number_label(reply, "wave", spawned)
            or number_label(reply, "wave", pending)
            or number_label(reply, "enemies", live_enemies)
            or number_label(reply, "enemies", pending + live_enemies))


class GlitchChecks:
    def glitch(self):
        super().glitch()
        cases = [
            ("GG/content-and-natural-selection", ["d2.placement", "d3.placement", "d5.controls", "d5.hud"], ["GG-01", "GG-02", "GG-07", "GG-10"], self.gg_content),
            ("GG/full-natural-wave-schedules", ["d2.waves", "d3.waves", "d5.hud"], ["GG-01", "GG-06", "GG-10"], self.gg_schedules),
            ("GG/full-production-cycles", ["d2.economy", "d3.economy", "d5.feedback"], ["GG-03", "GG-10"], self.gg_production),
            ("GG/projectile-cadence-speed-and-order", ["d2.projectiles", "d3.projectiles"], ["GG-02", "GG-04"], self.gg_shooting),
            ("GG/enemy-speed-full-attacks-vault", ["d2.enemies", "d3.enemies", "d5.feedback"], ["GG-05", "GG-10"], self.gg_enemies),
            ("GG/active-systems-pause-and-restart", ["d4.pause", "d4.restart"], ["GG-03", "GG-08"], self.gg_active_pause),
            ("GG/real-event-audio-and-mute", ["d5.feedback"], ["GG-09"], self.gg_audio),
            ("GG/result-freeze-and-final-campaign", ["d2.campaign", "d3.campaign", "d4.journey", "d5.overlays"], ["GG-06", "GG-07", "GG-08", "GG-10"], self.gg_results),
        ]
        for name, leaves, requirements, fn in cases:
            self.obligation(name, leaves, requirements, fn)

    def gg_content(self):
        for level in range(1, 6):
            self.p.call("reset", seconds=0)
            r = self.click("level_" + str(level))
            s = self.validate(r)
            cells = [a for a in s["actors"] if a["kind"] == "cell"]
            self.check("d2.placement", n(s, "level") == level and len(cells) == 40
                       and all(xyz(actor(s, f"cell_{row}_{col}")) == (col + 1, row + 1, 0)
                               for row in range(5) for col in range(8))
                       and all(a["state"] == "empty" and n(a, "hp") == 0 for a in cells)
                       and n(s, "stars") == 300 and n(s, "lives") == 5,
                       f"Normal level{level} selection enters exact fresh5x8 content, stars300/lives5")
            self.check("d5.controls", s["phase"] == "playing", "Visible normal level selection receives genuine click")
            self.assert_hud(r, {"level": level, "stars": 300, "lives": 5})
        for index, definition in enumerate(self.content["defenders"]):
            def prepare(s):
                sn(s, "stars", definition["cost"])
            self.setup(prepare)
            old = n(self.validate(self.p.last), "stars")
            selected = self.click("card_" + str(index))
            self.check("d3.placement", n(self.validate(selected), "stars") == old,
                       "Selecting a card does not debit currency")
            before = selected
            r = self.click("cell_2_3")
            s = self.validate(r)
            occupied = [a for a in s["actors"] if a["kind"] == "cell" and a["state"] != "empty"]
            self.check("d3.placement", len(occupied) == 1 and occupied[0]["id"] == "cell_2_3"
                       and n(occupied[0], "hp") == definition["hp"] and n(s, "stars") == 0,
                       "Exactly affordable normal click creates exactly one correct-HP defender and charges once")
            self.check("d5.controls", feedback_changed(before, r), "Selection/placement has actual visual/UI feedback")

    def gg_schedules(self):
        # Independent local temporal windows cover EVERY specified spawn. This
        # does not depend on winning an upstream run or on exact OS sleep timing.
        for entry, level in zip(self.model["entries"], self.content["levels"]):
            for index, wave in enumerate(level["waves"]):
                def prepare(s):
                    before = max(0, wave["time"] - .35)
                    sn(s, "elapsed", before)
                    sn(s, "spawn_index", index)
                    for i, w in enumerate(level["waves"]):
                        a = actor(s, w["id"])
                        a["state"] = "dead" if i < index else "pending"
                        a["present"] = False
                        sn(a, "hp", 0 if i < index else (100 if w["type"] == "lizard" else 120))
                self.setup(prepare, entry)
                start = self.validate(self.p.last)
                self.check("d3.waves", n(start, "spawn_index") == index and not actor(start, wave["id"])["present"],
                           f"{entry}/{wave['id']} not spawned before scheduled time")
                r = self.wait_elapsed(wave["time"] + .12, .04)
                s = self.validate(r)
                a = actor(s, wave["id"])
                elapsed = n(s, "elapsed")
                due = sum(w["time"] <= elapsed for w in level["waves"])
                self.check("d2.waves", a["present"] and a["state"] == wave["type"] and visible(r, a["id"]),
                           f"{entry}/{wave['id']} naturally spawns real visible correct type")
                self.check("d3.waves", n(s, "spawn_index") == due and a["position"]["y"] == wave["lane"] + 1
                           and abs(a["position"]["x"] - (10 - (.65 if wave["type"] == "fox" else .45) * (elapsed - wave["time"]))) < .13,
                           f"{entry}/{wave['id']} exact count/lane/time and genuine entrance movement")
                self.assert_hud(r, {"level": n(s, "level"), "stars": n(s, "stars"),
                                    "lives": n(s, "lives"), "time": n(s, "elapsed")})
                self.check("d5.hud", garden_progress_visible(r, n(s, "spawn_index"), len(level["waves"]),
                           sum(a["kind"] == "enemy" and a["present"] for a in s["actors"])),
                           "Actual HUD truthfully reports spawned/pending waves, live enemies, or pending+live remaining invaders")
            # No restored outcome: pending-free tail remains playing with a
            # living enemy, and no post-duration wave may appear.
            self.setup(lambda s: self.garden_target(s, x=9, typ="lizard"), entry)
            before = self.validate(self.p.last)
            after = self.validate(self.idle(.5))
            self.check("d3.waves", after["phase"] == "playing"
                       and n(after, "spawn_index") == len(level["waves"])
                       and sum(a["present"] for a in after["actors"] if a["kind"] == "enemy") == 1,
                       "Duration ends spawning, not live-enemy cleanup")
        # A full prefix without any save edits also proves accumulated scheduling.
        self.fresh()
        self.p.call("begin", seconds=0)
        for target in [1.2, 4.5, 9.0, 15.2]:
            r = self.wait_elapsed(target)
            s = self.validate(r)
            waves = self.content["levels"][0]["waves"]
            self.check("d3.waves", n(s, "spawn_index") == sum(w["time"] <= n(s, "elapsed") for w in waves),
                       "Unedited continuous first-level prefix accumulates every due wave without duplication")

    def gg_production(self):
        def prepare(s):
            # Keep one distant enemy to avoid a result while timers run.
            self.garden_target(s, x=10, typ="lizard")
            self.defend(s, 0, 0, "trophy")
            self.defend(s, 4, 0, "trophy")
            sn(s, "stars", 0)
        self.setup(prepare)
        start = n(self.validate(self.p.last), "elapsed")
        before = self.p.last
        r = self.wait_elapsed(start + 4.55)
        self.check("d3.economy", n(self.validate(r), "stars") == 0, "Two producers do not award stars before full5s")
        r = self.wait_elapsed(start + 5.3)
        self.check("d3.economy", n(self.validate(r), "stars") == 100, "Two lanes each produce50 on their first full interval")
        r = self.wait_elapsed(start + 10.3)
        self.check("d3.economy", n(self.validate(r), "stars") == 200, "Two natural complete production cycles retain exact cadence")
        self.check("d5.feedback", feedback_changed(before, r), "Natural production has visible state/UI feedback")
        self.click("card_0")
        r = self.click("cell_2_1")
        self.check("d2.economy", actor(self.validate(r), "cell_2_1")["state"] == "cactus"
                   and n(self.validate(r), "stars") == 100, "Actually produced stars can buy a normal defender")
        def dying(s):
            a = self.garden_target(s, x=2.55, typ="lizard")
            self.defend(s, int(a["position"]["y"]) - 1, 1, "trophy", 0, 20)
            sn(s, "stars", 73)
        self.setup(dying)
        r = self.idle(1.4)
        self.idle(5)
        s = self.validate(self.p.last)
        self.check("d3.economy", n(s, "stars") == 73, "Destroyed producer cannot award at its old5s deadline")
        for role in ["cactus", "gnome", "gravestone"]:
            self.setup(lambda s: self.defend(s, 0, 0, role))
            self.idle(5)
            self.check("d3.economy", n(self.validate(self.idle(.35)), "stars") == 300,
                       role + " never produces stars over a full production interval")

    def gg_shooting(self):
        for role, period, damage in [("cactus", 1, 20), ("gnome", 2, 35)]:
            def prepare(s):
                a = self.garden_target(s, x=9.5, typ="lizard")
                self.defend(s, int(a["position"]["y"]) - 1, 0, role)
            self.setup(prepare)
            start = n(self.validate(self.p.last), "elapsed")
            r = self.wait_elapsed(start + period - .25, .035)
            self.check("d3.projectiles", not any(a["kind"] == "projectile" and a["present"] for a in self.validate(r)["actors"]),
                       role + " waits complete natural first firing period")
            r = self.wait_until(lambda s: any(a["kind"] == "projectile" and a["present"] for a in s["actors"]), .7, .025)
            shots = [a for a in self.validate(r)["actors"] if a["kind"] == "projectile" and a["present"]]
            if not shots:
                self.check("d2.projectiles", False, role + " never emits a projectile")
                continue
            shot = shots[0]
            first = self.validate(r)
            r2 = self.idle(.16)
            second = self.validate(r2)
            later = next((a for a in second["actors"] if a["id"] == shot["id"] and a["present"]), None)
            dt = n(second, "elapsed") - n(first, "elapsed")
            self.check("d3.projectiles", later is not None and abs((later["position"]["x"] - shot["position"]["x"]) / dt - 6) < .35,
                       role + " projectile actual transform moves at speed6")
            r = self.wait_elapsed(start + 2 * period + .15, .03)
            ids = [a["id"] for a in self.validate(r)["actors"] if a["kind"] == "projectile"]
            self.check("d3.projectiles", any(i != shot["id"] for i in ids),
                       role + " naturally emits another projectile after its second complete interval")
        # Nearest same-lane first hit. A legal existing wave identity, not an
        # invented projectile, supplies the second target.
        def ordered(s):
            first = self.garden_target(s, x=3.4, typ="lizard")
            lane = int(first["position"]["y"]) - 1
            second_wave = next(w for w in self.content["levels"][0]["waves"] if w["lane"] == lane and w["id"] != first["id"])
            other = actor(s, second_wave["id"])
            other["present"] = True
            other["state"] = second_wave["type"]
            sn(other, "hp", 100 if second_wave["type"] == "lizard" else 120)
            pos(other, 5.3, lane + 1)
            self.defend(s, lane, 0, "cactus", .9)
            self.target_order = (first["id"], other["id"], n(other, "hp"))
        self.setup(ordered)
        r = self.idle(.4)
        s = self.validate(r)
        a, b, hp = self.target_order
        self.check("d3.projectiles", n(actor(s, a), "hp") == 80 and n(actor(s, b), "hp") == hp,
                   "One real shot hits the nearest of two same-lane enemies, not the farther target")
        first_ids = {a["id"] for a in s["actors"] if a["kind"] == "projectile" and a["present"]}
        r = self.idle(.12)
        self.check("d3.projectiles", n(actor(self.validate(r), a), "hp") == 80 and not first_ids,
                   "Hit projectile was removed and does not repeatedly damage")
        for behind in [False, True]:
            def no_target(s):
                a = self.garden_target(s, x=1.3, typ="lizard")
                self.defend(s, int(a["position"]["y"]) - 1, 5, "cactus")
                if not behind:
                    a["present"] = False
                    a["state"] = "dead"
                    sn(a, "hp", 0)
                    pos(a, 10, a["position"]["y"])
                    # Avoid immediate win by retaining the natural duration tail.
                    sn(s, "elapsed", self.content["levels"][0]["waves"][-1]["time"] + .1)
            self.setup(no_target)
            s = self.validate(self.idle(1.3))
            self.check("d3.projectiles", not any(a["kind"] == "projectile" and a["present"] for a in s["actors"]),
                       "No firing into an empty/behind-only lane")

    def gg_enemies(self):
        for typ, speed in [("lizard", .45), ("fox", .65)]:
            self.setup(lambda s: self.garden_target(s, x=7, hp=100 if typ == "lizard" else 120, typ=typ))
            a0 = next(a for a in self.validate(self.p.last)["actors"] if a["kind"] == "enemy" and a["present"])
            t0 = n(self.validate(self.p.last), "elapsed")
            r = self.idle(.45)
            s = self.validate(r)
            self.check("d3.enemies", abs((a0["position"]["x"] - actor(s, a0["id"])["position"]["x"]) /
                                       (n(s, "elapsed") - t0) - speed) < .06, typ + " exact unobstructed movement speed")
            def contact(s):
                a = self.garden_target(s, x=2.55, hp=100 if typ == "lizard" else 120, typ=typ)
                self.defend(s, int(a["position"]["y"]) - 1, 1, "trophy", hp=80)
            self.setup(contact)
            start = n(self.validate(self.p.last), "elapsed")
            r = self.wait_elapsed(start + .7, .05)
            s = self.validate(r)
            enemy = next(a for a in s["actors"] if a["kind"] == "enemy" and a["present"])
            cid = f"cell_{int(enemy['position']['y'])-1}_1"
            self.check("d3.enemies", n(actor(s, cid), "hp") == 80 and abs(enemy["position"]["x"] - 2.55) < .03,
                       typ + " stops at actual same-lane defender and does not hit before1s")
            r = self.wait_elapsed(start + 2.25, .04)
            self.check("d3.enemies", n(actor(self.validate(r), cid), "hp") == 40, typ + " deals20 on each of two full1s attacks")
        # Trace real transform/renderer animation, not merely a jumped flag.
        def fox(s):
            a = self.garden_target(s, x=3.4, hp=120, typ="fox")
            self.defend(s, int(a["position"]["y"]) - 1, 1, "gravestone")
            self.vault_id = a["id"]
        self.setup(fox)
        r = self.p.call("observe", seconds=3.0, watch=self.vault_id)
        trace = r.get("motion") or []
        animated = any(
            any(abs(q["scale"][axis] - trace[0]["scale"][axis]) > .03 for axis in ["x", "y", "z"])
            or any(abs((q["euler"][axis] - trace[0]["euler"][axis] + 180) % 360 - 180) > 1 for axis in ["x", "y", "z"])
            or (trace and abs(bounds_size(q).get("y", 0) - bounds_size(trace[0]).get("y", 0)) > .04)
            or (trace and abs(bounds_center(q).get("y", 0) - bounds_center(trace[0]).get("y", 0)) > .04)
            or (trace and abs(q["position"]["y"] - trace[0]["position"]["y"]) > .04)
            for q in trace)
        self.check("d2.enemies", animated and actor(self.validate(r), self.vault_id)["position"]["x"] < 2,
                   "Fox vault has independently sampled real lift/rotation/scale/renderer animation and left-side landing")
        self.check("d5.feedback", animated, "Fox jump is player-observable, not just a state flag")

    def gg_active_pause(self):
        def prepare(s):
            a = self.garden_target(s, x=7, typ="lizard")
            lane = int(a["position"]["y"]) - 1
            self.defend(s, lane, 0, "cactus", .9)
            self.defend(s, (lane + 1) % 5, 0, "trophy", 4.4)
        self.setup(prepare)
        self.idle(.16)
        r = self.click("pause")
        before = self.validate(r)
        after = self.validate(self.idle(1.2))
        self.check("d4.pause", equivalent(frozen_state(before), frozen_state(after)),
                   "Active projectile, producer, enemy and time all freeze under Pause")
        self.click("resume")
        after = self.validate(self.idle(.8))
        self.check("d4.pause", n(after, "elapsed") > n(before, "elapsed") and n(after, "stars") == n(before, "stars") + 50,
                   "Resume retains production progress and continues active systems")
        oldmask = n(after, "completed_mask")
        r = self.restart()
        s = self.validate(r)
        self.check("d4.restart", n(s, "stars") == 300 and n(s, "lives") == 5 and n(s, "completed_mask") == oldmask
                   and all(a["state"] == "empty" for a in s["actors"] if a["kind"] == "cell")
                   and not any(a["kind"] == "projectile" and a["present"] for a in s["actors"]),
                   "Play Retry clears active projectiles/production without erasing earned campaign bits")

    def gg_audio(self):
        r = self.p.call("audio-probe", seconds=.15)
        if r.get("audioPeak", 0) < .0001:
            raise InfrastructureError("Calibrated host audio output cannot be observed; do not penalize candidate")
        for muted in [False, True]:
            def prepare(s):
                a = self.garden_target(s, x=3, hp=20, typ="lizard")
                self.defend(s, int(a["position"]["y"]) - 1, 0, "cactus", .75)
                sn(s, "volume", 0 if muted else 1)
            self.setup(prepare)
            self.idle(.12)  # discard preparation/import sounds
            r = self.p.call("observe", seconds=.8)
            audible = r.get("audioPeak", 0) > .0001
            self.check("d5.feedback", audible != muted,
                       "Mixed engine output proves firing/hit/result audio is audible with volume1 and silent with volume0")
            def placement(s):
                sn(s, "volume", 0 if muted else 1)
            self.setup(placement)
            self.idle(.2)
            self.click("card_0")
            self.idle(.25)
            r = self.click("cell_0_0", seconds=.15)
            self.check("d5.feedback", (r.get("audioPeak", 0) > .0001) != muted,
                       "Real normal placement event audio obeys mute on mixed output")
            for event in ["firing", "damage", "loss"]:
                def prepare_event(s):
                    sn(s, "volume", 0 if muted else 1)
                    if event == "firing":
                        a = self.garden_target(s, x=9, typ="lizard")
                        self.defend(s, int(a["position"]["y"]) - 1, 0, "cactus")
                    elif event == "damage":
                        a = self.garden_target(s, x=2.55, typ="lizard")
                        self.defend(s, int(a["position"]["y"]) - 1, 1, "gravestone")
                    else:
                        self.garden_target(s, x=.6, typ="lizard")
                        sn(s, "lives", 1)
                self.setup(prepare_event)
                self.idle(.25)
                r = self.idle(1.3)
                self.check("d5.feedback", (r.get("audioPeak", 0) > .0001) != muted,
                           f"Isolated real {event} event obeys {'muted' if muted else 'audible'} output; no unrelated placement sounds")

    def gg_results(self):
        for level in [1, 5]:
            def win(s):
                a = self.garden_target(s, x=3, hp=20, typ="lizard")
                self.defend(s, int(a["position"]["y"]) - 1, 0, "cactus", .9)
                self.defend(s, (int(a["position"]["y"])) % 5, 1, "trophy", 4.2)
            self.setup(win, "level_" + str(level))
            r = self.idle(.8)
            s = self.validate(r)
            self.check("d2.campaign", s["phase"] == "won", "Real final shot earns level result")
            before = copy.deepcopy(s)
            after = self.validate(self.idle(1.3))
            self.assert_stable(before, after)
            self.check("d3.campaign", n(after, "stars") == n(before, "stars"),
                       "Result stops pending production, projectiles and level clock")
            self.check("d5.overlays", bool(re.search("complete|safe|campaign|victor|cleared|win", text(r), re.I)),
                       "Final campaign/result overlay has actual readable completion presentation")
            if level == 1:
                r = self.click("next")
                s = self.validate(r)
                self.check("d3.campaign", n(s, "level") == 2 and not any(a["kind"] == "projectile" and a["present"] for a in s["actors"]),
                           "Next cleans all old projectiles while entering actual next level")
