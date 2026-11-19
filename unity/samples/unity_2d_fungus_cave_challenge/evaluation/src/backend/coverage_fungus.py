import copy
import math
import re
from session_core import n, sn, nums, actor, pos, xyz, fact, text, visible, public, equivalent, ProductError, InfrastructureError, Player
from coverage_common import frozen_state, feedback_changed


class FungusChecks:
    def fungus(self):
        super().fungus()
        for name, leaves, requirements, fn in [
            ("FC/exact-content-all-bindings-energy", ["d2.movement", "d3.movement", "d5.hud"], ["FC-01", "FC-02", "FC-03", "FC-13"], self.fc_movement),
            ("FC/enemy-energy-pursuit-occupancy", ["d2.combat", "d3.combat"], ["FC-02", "FC-04", "FC-05"], self.fc_enemy_turns),
            ("FC/all-nine-powers-real-effects-and-slots", ["d2.powers", "d3.powers", "d5.feedback"], ["FC-07", "FC-08"], self.fc_power_effects),
            ("FC/seeded-infection-generation-and-thresholds", ["d2.infection", "d3.infection", "d3.powers"], ["FC-06", "FC-08"], self.fc_infection_generation),
            ("FC/reinfection-same-type-duration-cap", ["d3.infection"], ["FC-06"], self.fc_reinfection),
            ("FC/recovery-clear-and-mutated-reward", ["d3.infection", "d3.combat", "d3.survival", "d4.journey"], ["FC-05", "FC-06", "FC-08"], self.fc_recovery),
            ("FC/pressure-exclusions-and-locked-exit", ["d2.pressure", "d3.pressure", "d3.survival", "d4.journey"], ["FC-09", "FC-10"], self.fc_pressure),
            ("FC/full-resource-floor-carry-and-reset", ["d3.survival", "d4.journey", "d4.restart"], ["FC-05", "FC-10", "FC-11"], self.fc_carry),
            ("FC/ordinary-complex-manual-save-new-process", ["d4.reopen", "d4.restart"], ["FC-07", "FC-11", "FC-12", "FC-13"], self.fc_full_save),
        ]:
            self.obligation(name, leaves, requirements, fn)

    def fc_isolated(self, s, player=(1, 1)):
        self.isolate_fungus(s)
        pos(actor(s, "player"), *player)

    def fc_power(self, s, power, active=True, slot=1):
        prerequisite = next(p for p in self.content["powers"] if p["id"] == power)["prerequisite"]
        mask = (1 << (power - 1)) | ((1 << (prerequisite - 1)) if prerequisite else 0)
        sn(s, "powers_mask", mask)
        for i in range(1, 4):
            sn(s, "slot_" + str(i), power if i == slot else 0)
        sn(s, "stress", slot if active else slot - 1)

    def fc_movement(self):
        for index, entry in enumerate(self.model["entries"]):
            r = self.fresh(entry)
            s = self.validate(r)
            f = self.content["floors"][index]
            lookup = {"#": "wall", "~": "pool", "f": "fungus", "X": "exit"}
            correct = all(
                actor(s, f"tile_{x}_{y}")["state"] == lookup.get(f["rows"][9-y][x], "floor")
                and xyz(actor(s, f"tile_{x}_{y}")) == (x, y, 0)
                and visible(r, f"tile_{x}_{y}")
                for y in range(10) for x in range(12))
            self.check("d2.movement", correct, "Every fixed wall/water/fungus/exit cell in every actual floor matches public content and renderer")
            self.check("d3.movement", all(n(s, k) == v for k, v in {
                "hp": 10, "potions": 2, "energy": 4000, "stress": 0,
                "infection": 0, "infection_turns": 0, "powers_mask": 0,
                "turn": 0, "beetle_counter": 30}.items()),
                "Each normal chapter entry has exact declared fresh resources")
        for key, delta in [
            ("W", (0, 1)), ("UpArrow", (0, 1)), ("S", (0, -1)), ("DownArrow", (0, -1)),
            ("A", (-1, 0)), ("LeftArrow", (-1, 0)), ("D", (1, 0)), ("RightArrow", (1, 0)),
            ("Q", (-1, 1)), ("E", (1, 1)), ("Z", (-1, -1)), ("C", (1, -1)), ("Period", (0, 0))]:
            self.setup(lambda s: self.fc_isolated(s, (2, 5)))
            r = self.key(key, .35)
            s = self.validate(r)
            self.check("d3.movement", xyz(actor(s, "player")) == (2 + delta[0], 5 + delta[1], 0)
                       and n(s, "turn") == 1
                       and n(s, "energy") == (3600 if delta[0] and delta[1] else 4000),
                       "Each binding makes exactly one accepted action while held, with exact cardinal/diagonal/wait energy")
            self.assert_hud(r, {"hp": n(s, "hp"), "potions": n(s, "potions"), "stress": n(s, "stress"),
                                "turn": n(s, "turn"), "floor": n(s, "floor")})
        for slow in [False, True]:
            for diagonal in [False, True]:
                def prepare(s):
                    self.fc_isolated(s, (3, 2))
                    if slow:
                        sn(s, "infection", 1)
                        sn(s, "infection_turns", 5)
                self.setup(prepare)
                s = self.validate(self.key("E" if diagonal else "D"))
                expected = 4000 - 400 - (400 if diagonal else 0) - (800 if slow else 0)
                self.check("d3.movement", n(s, "energy") == expected,
                           "Leaving actual pool combines exact400 cost with diagonal and Slow modifiers")
        for energy in [2999, 3000]:
            def prepare(s):
                self.fc_isolated(s)
                sn(s, "energy", energy)
            self.setup(prepare)
            s = self.validate(self.key("D"))
            self.check("d3.movement", actor(s, "player")["position"]["x"] == (1 if energy < 3000 else 2)
                       and n(s, "energy") == (3999 if energy < 3000 else 3000) and n(s, "turn") == 1,
                       "Energy threshold2999/3000 distinguishes forced wait from real movement")

    def fc_enemy_turns(self):
        for energy, expected_hp, expected_energy in [(0, 10, 1000), (1999, 10, 2999), (2000, 9, 1600), (4000, 9, 2600)]:
            self.setup(lambda s: self.fungus_target(s, hp=6, energy=energy))
            s = self.validate(self.key("Period"))
            self.check("d3.combat", n(s, "hp") == expected_hp and n(actor(s, "enemy_0"), "energy") == expected_energy,
                       "Enemy +1000/cap4000, threshold3000, at-most-one attack and1400 attack cost")
        def pursue(s):
            self.fungus_target(s, hp=6, enemy=(4, 1), energy=3000)
        self.setup(pursue)
        r = self.key("Period")
        s = self.validate(r)
        self.check("d2.combat", xyz(actor(s, "enemy_0")) == (3, 1, 0)
                   and xyz(fact(r, "enemy_0")) == (3, 1, 0),
                   "Real non-adjacent enemy takes one pursuit step, not a stationary report")
        self.check("d3.combat", n(actor(s, "enemy_0"), "energy") == 3000 and n(s, "hp") == 10,
                   "Pursuit step costs1000 and cannot chain another move/attack in same player turn")
        def occupied(s):
            self.fungus_target(s, hp=6, enemy=(4, 1), energy=3000)
            b = actor(s, "enemy_1")
            b["present"], b["state"] = True, "active"
            pos(b, 3, 1)
            sn(b, "hp", 4)
            sn(b, "energy", 0)
            sn(s, "kills", n(s, "kills") - 1)
        self.setup(occupied)
        s = self.validate(self.key("Period"))
        live = [xyz(a) for a in s["actors"] if a["kind"] in ["player", "enemy", "beetle"] and a["present"]]
        self.check("d3.combat", len(live) == len(set(live)), "Enemy pursuit cannot occupy another live actor or player cell")
        def wall(s):
            self.fungus_target(s, hp=6, player=(6, 6), enemy=(4, 6), energy=3000)
        self.setup(wall)
        previous = xyz(actor(self.validate(self.p.last), "enemy_0"))
        for _ in range(4):
            s = self.validate(self.key("Period"))
            enemy = actor(s, "enemy_0")
            x, y, z = xyz(enemy)
            grid = self.content["floors"][0]["rows"]
            legal = int(x) == x and int(y) == y and z == 0 and 0 <= x < 12 and 0 <= y < 10
            self.check("d3.combat", legal and grid[9-int(y)][int(x)] != "#"
                       and abs(x-previous[0]) + abs(y-previous[1]) <= 1,
                       "Repeated pursuit beside an actual wall never walks through it or chains multiple cardinal steps")
            previous = (x, y, z)

    def fc_power_effects(self):
        for power, hp, infection, expected in [
            (1, 10, 0, ("energy", 1200)), (4, 5, 0, ("energy", 1200)),
            (4, 4, 0, ("energy", 1400)), (3, 4, 0, ("hp", 5)),
            (3, 5, 0, ("hp", 5)), (6, 7, 1, ("hp", 8)),
            (6, 8, 1, ("hp", 8)), (6, 7, 0, ("hp", 7)),
            (5, 10, 1, ("infection_turns", 3)),
        ]:
            for active in [False, True]:
                def prepare(s):
                    self.fc_isolated(s)
                    self.fc_power(s, power, active)
                    sn(s, "hp", hp)
                    sn(s, "energy", 0)
                    sn(s, "infection", infection)
                    sn(s, "infection_turns", 5 if infection else 0)
                self.setup(prepare)
                s = self.validate(self.key("Period"))
                field, target = expected
                if not active:
                    target = 1000 if field == "energy" else hp if field == "hp" else 4
                self.check("d3.powers", n(s, field) == target,
                           f"Power{power} actual {'active' if active else 'inactive'} {field}, HP/infection boundary={hp}/{infection}")
        for power in [7, 9]:
            for active in [False, True]:
                def prepare(s):
                    self.fungus_target(s, hp=6, energy=2000 if power == 7 else 0)
                    self.fc_power(s, power, active)
                self.setup(prepare)
                r = self.key("D")
                s = self.validate(r)
                if power == 7:
                    okay = n(actor(s, "enemy_0"), "energy") == (2400 if active else 1600)
                else:
                    okay = n(actor(s, "enemy_0"), "hp") == (3 if active else 4)
                self.check("d3.powers", okay, "Siphon subtracts actual damage*300 energy / Bleed adds actual1 damage only while active")
        for slot in [1, 2, 3]:
            for active in [False, True]:
                def prepare(s):
                    self.fc_isolated(s)
                    self.fc_power(s, 1, active, slot)
                    sn(s, "energy", 0)
                self.setup(prepare)
                self.check("d3.powers", n(self.validate(self.key("Period")), "energy") == (1200 if active else 1000),
                           "Each of all three slots activates only at its own stress threshold")
        # Isolate three rejection reasons rather than conflate prerequisites and funds.
        for kind in ["prerequisite", "funds", "duplicate"]:
            power = 4 if kind == "prerequisite" else 1
            def prepare(s):
                self.fc_isolated(s)
                sn(s, "potions", 4 if kind != "funds" else 1)
                if kind == "duplicate":
                    sn(s, "powers_mask", 1)
            self.setup(prepare)
            self.click("shop")
            before = copy.deepcopy(self.validate(self.p.last))
            r = self.click("buy_" + str(power))
            s = self.validate(r)
            self.check("d3.powers", n(s, "potions") == n(before, "potions")
                       and n(s, "powers_mask") == n(before, "powers_mask") and n(s, "turn") == n(before, "turn"),
                       kind + " purchase is atomically rejected without advancing combat")
            self.check("d5.feedback", feedback_changed({"ui": []}, r), "Shop has visible explanatory/rejection information")
        def slots(s):
            self.fc_isolated(s)
            sn(s, "powers_mask", 15)
            for i in range(1, 4):
                sn(s, "slot_" + str(i), i)
        self.setup(slots)
        self.click("shop")
        values = []
        for _ in range(3):
            s = self.validate(self.click("slot_3"))
            values.append(n(s, "slot_3"))
            nonempty = [n(s, "slot_" + str(i)) for i in range(1, 4) if n(s, "slot_" + str(i))]
            self.check("d3.powers", len(nonempty) == len(set(nonempty)) and n(s, "turn") == 0,
                       "Normal slot cycling cannot duplicate another active slot or advance combat")
        self.check("d3.powers", set(values) == {0, 3, 4}, "Slot cycle covers its owned unused powers and empty exactly")

    def fc_seeded_hit(self, seed, pool=False, low=False, plague=False):
        self.fresh_seed("floor_1", seed)
        save = copy.deepcopy(self.validate(self.p.last))
        save["actors"] = [a for a in save["actors"] if a["kind"] != "control"]
        def prepare(s):
            self.fungus_target(s, hp=3 if low else 6,
                               player=(2, 2) if pool else (1, 1),
                               enemy=(3, 2) if pool else (2, 1))
            if plague:
                self.fc_power(s, 8, True)
        self.restore_preparation(save, prepare)
        s = self.validate(self.key("D"))
        return n(actor(s, "enemy_0"), "infection") > 0

    def fc_infection_generation(self):
        groups = {}
        seeds = list(range(1100, 1196))
        for label, pool, low, plague in [
            ("base40", False, False, False), ("pool80", True, False, False),
            ("low80", False, True, False), ("plague60", False, False, True)]:
            outcomes = [self.fc_seeded_hit(seed, pool, low, plague) for seed in seeds]
            rate = sum(outcomes) / len(outcomes)
            groups[label] = outcomes
            expected = .8 if pool or low else .6 if plague else .4
            self.check("d3.infection", abs(rate - expected) <= .18,
                       f"Seeded actual attack infection rate {label}: {sum(outcomes)}/{len(outcomes)}, broad preregistered ±.18 binomial tolerance")
        delta = sum(groups["plague60"]) / len(seeds) - sum(groups["base40"]) / len(seeds)
        self.check("d3.powers", .05 <= delta <= .35,
                   "Active Plague changes the measured infection probability, not merely its purchase flag")
        self.check("d2.infection", 0 < sum(groups["base40"]) < len(seeds),
                   "Actual normal attacks sometimes infect and sometimes do not")
        self.check("d3.infection", self.fc_seeded_hit(1105) == self.fc_seeded_hit(1105),
                   "Reopening the same published seed gives reproducible infection outcome")
        for stress, immunity in [(0, False), (1, False), (2, False), (3, False), (3, True), (4, True)]:
            events = 0
            for seed in range(2100, 2124):
                self.fresh_seed("floor_1", seed)
                save = copy.deepcopy(self.validate(self.p.last))
                save["actors"] = [a for a in save["actors"] if a["kind"] != "control"]
                def prepare(s):
                    self.fungus_target(s, hp=6, energy=2000)
                    if immunity:
                        self.fc_power(s, 2, True)
                    sn(s, "stress", stress)
                self.restore_preparation(save, prepare)
                s = self.validate(self.key("Period"))
                threshold = 4 if immunity else 3
                changed = n(s, "stress") != stress or n(s, "infection") > 0
                events += changed
                self.check("d3.infection", (n(s, "infection") == 0 and n(s, "stress") in [stress, stress+1])
                           if stress < threshold else n(s, "stress") == stress,
                           "Actual incoming attack obeys player stress-before-infection / active Immunity threshold")
            self.check("d3.infection", events > 0, "Repeated seeded real incoming attacks actually trigger stress/infection events")

    def fc_recovery(self):
        for kind in [1, 2, 3]:
            def prepare(s):
                self.fc_isolated(s)
                sn(s, "infection", kind)
                sn(s, "infection_turns", 1)
            self.setup(prepare)
            s = self.validate(self.key("Period"))
            self.check("d3.infection", n(s, "infection") == 0 and n(s, "infection_turns") == 0,
                       "All infection types clear exactly at duration zero")
        def mutated(s):
            self.fungus_target(s, hp=2)
            sn(s, "potions", 0)
            sn(actor(s, "enemy_0"), "infection", 3)
            sn(actor(s, "enemy_0"), "infection_turns", 5)
        self.setup(mutated)
        r = self.key("D")
        s = self.validate(r)
        self.check("d3.combat", n(s, "potions") == 2 and not actor(s, "enemy_0")["present"],
                   "Mutated dead enemy grants one extra actual potion")
        for _ in range(4):
            s = self.validate(self.key("Period"))
        self.check("d3.combat", n(s, "hp") == 10, "Killed enemy never attacks on later accepted turns")
        # A pre-existing non-Mutated infection prevents a legitimate newly
        # rolled Mutated on the lethal hit from changing the normal HP branch.
        # Random algorithm/seed mapping is not prescribed by the input.
        for mutation, hp in [(1, 10), (3, 5)]:
            def revive(s):
                self.fungus_target(s, hp=6, energy=2000)
                sn(s, "hp", 1)
                sn(s, "potions", 1)
                sn(s, "stress", 4)
                sn(s, "infection", mutation)
                sn(s, "infection_turns", 5 if mutation else 0)
            self.setup(revive)
            s = self.validate(self.key("Period"))
            self.check("d3.survival", n(s, "hp") == hp and n(s, "potions") == 0 and n(s, "energy") == 4000 and n(s, "stress") == 0,
                       "Real lethal attack revival preserves exact normal/Mutated HP, potion debit, energy cap and stress reduction")
        def defeat(s):
            self.fungus_target(s, hp=6, energy=2000)
            sn(s, "hp", 1)
            sn(s, "potions", 0)
        self.setup(defeat)
        s = self.validate(self.key("Period"))
        self.check("d3.survival", s["phase"] == "lost" and n(s, "hp") == 0,
                   "Real lethal attack with no potion reaches actual defeat")
        after = self.validate(self.key("D,Period", .3))
        self.assert_stable(s, after)

    def fc_reinfection(self):
        extended = 0
        for turns in [5, 9]:
            for seed in range(3100, 3124):
                self.fresh_seed("floor_1", seed)
                save = copy.deepcopy(self.validate(self.p.last))
                save["actors"] = [a for a in save["actors"] if a["kind"] != "control"]
                def prepare(s):
                    self.fungus_target(s, hp=6)
                    victim = actor(s, "enemy_0")
                    sn(victim, "infection", 1)
                    sn(victim, "infection_turns", turns)
                self.restore_preparation(save, prepare)
                s = self.validate(self.key("D"))
                victim = actor(s, "enemy_0")
                duration = n(victim, "infection_turns")
                self.check("d3.infection", n(victim, "infection") == 1 and duration in [turns-1, turns]
                           and duration <= 9,
                           "Reinfection keeps existing type, adds at most one turn, and respects cap9 across actual turn recovery")
                if turns == 5 and duration == 5:
                    extended += 1
        self.check("d3.infection", extended > 0, "Seeded real repeated hits demonstrate actual duration extension")

    def fc_pressure(self):
        for adjacent, expected in [(False, 9), (True, 8)]:
            def prepare(s):
                self.fungus_target(s, hp=2, player=(6, 7) if adjacent else (1, 1), enemy=(7, 7) if adjacent else (2, 1))
                sn(s, "beetle_counter", 10)
            self.setup(prepare)
            self.check("d3.pressure", n(self.validate(self.key("D")), "beetle_counter") == expected,
                       "Ordinary versus fungus-neighbor victim decrements pressure by1/2")
        def beetle(s):
            self.fc_isolated(s)
            b = actor(s, "beetle_0")
            b["present"], b["state"] = True, "active"
            pos(b, 2, 1)
            sn(b, "hp", 2)
            sn(s, "beetle_counter", 10)
        self.setup(beetle)
        s = self.validate(self.key("D"))
        self.check("d3.pressure", n(s, "beetle_counter") == 10 and n(s, "potions") == 2,
                   "Actual beetle kill neither grants potions nor recursively decrements beetle pressure")
        def locked(s):
            self.fungus_target(s, hp=6, player=(9, 1), enemy=(7, 5))
        self.setup(locked)
        self.check("d3.survival", n(self.validate(self.key("D")), "floor") == 1,
                   "Actual exit entry remains locked with one live reward-bearing enemy")
        def cleared_with_beetle(s):
            self.fc_isolated(s, (9, 1))
            b = actor(s, "beetle_0")
            b["present"], b["state"] = True, "active"
            pos(b, 5, 5)
            sn(b, "hp", 3)
        self.setup(cleared_with_beetle)
        self.check("d4.journey", n(self.validate(self.key("D")), "floor") == 2,
                   "Living beetles do not prevent real floor-clear exit progression")
        def revival_pressure(s):
            self.fungus_target(s, hp=6, energy=2000)
            sn(s, "hp", 1)
            sn(s, "potions", 1)
            sn(s, "beetle_counter", 1)
        self.setup(revival_pressure)
        r = self.key("Period")
        s = self.validate(r)
        beetles = [a for a in s["actors"] if a["kind"] == "beetle" and a["present"]]
        self.check("d3.pressure", len(beetles) == 4 and n(s, "beetle_counter") == 30,
                   "Actual revival also decrements pressure and spawns beetles at threshold")
        player = actor(s, "player")["position"]
        occupied = {xyz(a) for a in s["actors"] if a["kind"] in ["player", "enemy"] and a["present"]}
        candidates = sorted((a["position"]["x"]-player["x"])**2 + (a["position"]["y"]-player["y"])**2
                            for a in s["actors"] if a["kind"] == "tile" and a["state"] != "wall"
                            and xyz(a) not in occupied)
        self.check("d3.pressure", len(beetles) == 4 and all(
            (a["position"]["x"]-player["x"])**2 + (a["position"]["y"]-player["y"])**2 <= candidates[3]
            for a in beetles), "Spawned beetles occupy nearest legal free cells; tied nearest cells are equally legal")

    def fc_carry(self):
        for floor in [1, 2]:
            def prepare(s):
                self.fc_isolated(s, (9, 1))
                sn(s, "hp", 7)
                sn(s, "potions", 3)
                sn(s, "stress", 2)
                sn(s, "infection", 2)
                sn(s, "infection_turns", 5)
                sn(s, "powers_mask", 3)
                sn(s, "slot_1", 1)
                sn(s, "slot_2", 2)
                sn(s, "turn", 123)
                sn(s, "beetle_counter", 7)
            self.setup(prepare, "floor_" + str(floor))
            self.check("d4.journey", n(self.validate(self.p.last), "floor") == floor and self.validate(self.p.last)["phase"] == "playing",
                       "Restoring legal cleared near-exit state does not itself change floor or grant win")
            r = self.key("D")
            s = self.validate(r)
            expected = {"floor": floor+1, "hp": 7, "potions": 3, "stress": 2, "infection": 2,
                        "infection_turns": 4, "powers_mask": 3, "slot_1": 1, "slot_2": 2,
                        "energy": 4000, "turn": 0, "beetle_counter": 30, "kills": 0}
            self.check("d3.survival", all(n(s, k) == v for k, v in expected.items()),
                       "Real adjacent floor transition carries all survival/power fields and resets local enemies/turn/energy/pressure")

    def fc_full_save(self):
        self.p.call("reset", seconds=0)
        self.start()
        self.key("D")
        self.key("D")
        self.click("shop")
        self.click("buy_1")
        self.click("close_shop")
        r = self.click("save")
        before = copy.deepcopy(self.validate(r))
        old_pid = self.p.process.pid
        self.p.close()
        self.p = Player(self.out / "player/Game.exe", self.out / "process-3-full-save", False)
        menu = self.validate(self.p.last)
        self.check("d4.reopen", menu["phase"] == "menu" and self.p.process.pid != old_pid,
                   "Complex normal manual save reopens in a genuinely new process at title")
        r = self.click("continue")
        after = self.validate(r)
        self.check("d4.reopen", equivalent(frozen_state(before), frozen_state(after)),
                   "Ordinary Continue restores all floor/resource/enemy/energy/power/loadout state, not just player HP/pose")
        r = self.key("D")
        self.check("d4.reopen", n(self.validate(r), "turn") == n(before, "turn") + 1, "Normal input continues the restored real game")
        self.key("Escape")
        r = self.click("restart")
        s = self.validate(r)
        self.check("d4.restart", n(s, "floor") == 1 and n(s, "turn") == 0 and n(s, "powers_mask") == 0
                   and n(s, "potions") == 2 and xyz(actor(s, "player")) == (1, 1, 0),
                   "Restart starts fresh instead of silently resuming saved acquired power/loadout")
