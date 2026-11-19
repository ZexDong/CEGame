import copy
import json
import math
import re
import time
import traceback
from pathlib import Path
from session_core import n, sn, nums, actor, pos, xyz, fact, text, visible, public, equivalent, ProductError, InfrastructureError, write


def number_label(reply, label, value, tolerance=None):
    aliases = {
        "stars": r"stars?|★|☆|⭐", "lives": r"lives?|life|♥|❤",
        "level": r"level|lvl", "track": r"track|course",
        "shield": r"shield|shd|🛡", "speed": r"speed|spd",
        "potions": r"potions?|flasks?|pot|🧪|⚗", "hp": r"hp|health",
        "time": r"time|elapsed", "points": r"points?|pts|score",
        "gates": r"gates?", "turn": r"turn", "floor": r"floor",
        "stress": r"stress", "enemies": r"enemies|invaders|remaining",
        "wave": r"waves?", "energy": r"energy",
    }
    a = aliases.get(label, re.escape(label))
    number = r"(\d+(?:\.\d+)?)"
    shown = text(reply)
    found = re.findall(r"(?:" + a + r")\s*[::]?\s*" + number, shown, re.I)
    found += re.findall(number + r"\s*(?:" + a + r")", shown, re.I)
    for token in found:
        precision = len(token.partition(".")[2]) if "." in token else 0
        error = tolerance if tolerance is not None else (.51 * 10 ** -precision if precision else .01)
        if abs(float(token) - value) <= error:
            return True
    return False


def frozen_state(save):
    result = public(save)
    result["actors"] = [a for a in result["actors"] if a["kind"] != "control"]
    return result


def feedback_changed(before, after):
    return text(before) != text(after) or any(
        (fact(before, a.get("id")) or {}).get("visualSignature") != a.get("visualSignature")
        for a in after.get("actors") or [] if a.get("renderers", 0) > 0
    )

def bounds_size(sample):
    bounds = sample.get("bounds") or {}
    if "size" in bounds:
        return bounds["size"]
    return {k: 2 * v for k, v in bounds.get("m_Extent", {}).items()}

def bounds_center(sample):
    bounds = sample.get("bounds") or {}
    return bounds.get("center") or bounds.get("m_Center") or {}


class CommonChecks:

    def click(self, id=None, label=None, seconds=.04):
        # ResolveActor contract failures are scored independently. Still attempt
        # a genuine visible ordinary Button through the public rendering API.
        from navigation import labels
        from session_core import ProductError
        try:
            return super().click(id=id, label=label, seconds=seconds)
        except ProductError:
            choices = labels(self.p.last, id, self.content) if id else []
            if not choices:
                raise
            # Host.Target resolves an exact label on a visible interactable
            # Button, checks actual raycast, and sends a real mouse device event.
            return super().click(label="|".join(choices), seconds=seconds)

    def scenario(self, name, ids, fn):
        if getattr(self, "only_cases", None) and name not in self.only_cases:
            return
        self.context = name
        try:
            fn()
        except ProductError as ex:
            detail = str(ex)
            if "Cannot earn completion" in detail:
                root = "d3.campaign"
            elif "Cannot earn race record" in detail:
                root = "d3.race"
            elif "Real normal approach did not produce" in detail:
                root = "d3.shield"
            elif "No visible control/cell:" in detail:
                root = "d5.controls"
            else:
                root = "d1.service"
            self.record(root, "FAIL_OBSERVED", "Direct candidate delivery violation: " + detail)
            for check in ids:
                if check != root:
                    self.record(check, "BLOCKED_BY_PRODUCT", detail)
                    self.leaves[check]["observations"][-1]["blocked_by"] = [root]
        except InfrastructureError as ex:
            for check in ids:
                self.record(check, "INCONCLUSIVE_EVALUATOR", str(ex))
        except Exception:
            for check in ids:
                self.record(check, "INCONCLUSIVE_EVALUATOR", traceback.format_exc())
        self.save()

    def restart(self):
        save = self.p.last.get("save") or {}
        if not any(a["id"] == "restart" and a["present"] for a in save.get("actors", [])):
            if save.get("phase") == "playing":
                self.key("Escape")
        return self.click("restart")

    def obligation(self, name, ids, requirements, fn):
        if getattr(self, "only_cases", None) and name not in self.only_cases:
            return
        if not hasattr(self, "coverage_executions"):
            self.coverage_executions = []
        first = {i: len(self.leaves[i]["observations"]) for i in ids}
        self.scenario(name, ids, fn)
        self.coverage_executions.append(dict(
            id=name, requirements=requirements, leaves=ids,
            observations={i: self.leaves[i]["observations"][first[i]:] for i in ids}))
        self.save()

    def wait_until(self, predicate, seconds, step=.08, watch=None):
        end = time.monotonic() + seconds
        reply = self.p.last
        while not predicate(self.validate(reply)) and time.monotonic() < end:
            reply = self.p.call("observe", seconds=step, **({"watch": watch} if watch else {}))
        return reply

    def wait_elapsed(self, target, step=.2):
        return self.wait_until(lambda s: n(s, "elapsed") >= target or s["phase"] != "playing",
                               max(2, target - n(self.validate(self.p.last), "elapsed") + 3), step)

    def fresh_seed(self, entry, seed):
        self.p.call("reset", seconds=0)
        reply = self.p.call("open", entry=entry, seed=seed, seconds=0)
        self.validate(reply)
        return reply

    def assert_hud(self, reply, fields, leaf="d5.hud"):
        for label, value in fields.items():
            self.check(leaf, number_label(reply, label, value),
                       f"Actual rendered semantic HUD {label} matches {value}")

    def assert_stable(self, before, after, leaf="d4.journey"):
        self.check(leaf, equivalent(frozen_state(before), frozen_state(after)),
                   "Terminal gameplay state remains unchanged despite delivered input and elapsed time")

    def lifecycle(self):
        super().lifecycle()

        def repeat_navigation():
            footprints = []
            self.p.call("reset", seconds=0)
            for _ in range(3):
                self.start()
                r = self.idle(.08)
                s = self.validate(r)
                footprints.append(dict(
                    actors=sorted((a["id"], a["kind"]) for a in s["actors"] if a["present"]),
                    event_systems=r.get("eventSystems"), canvases=r.get("canvases"),
                    buttons=r.get("buttons")))
                self.return_menu()
            self.check("d4.entry", all(q == footprints[0] for q in footprints)
                       and footprints[0]["event_systems"] == 1,
                       "Three normal Menu/Start cycles have stable actual actor/control/EventSystem cardinality")
        self.obligation("COMMON/repeated-natural-menu", ["d4.entry"],
                        ["FC-11", "GG-08", "PR-08"], repeat_navigation)
        def readable_overlays():
            self.p.call("reset", seconds=0)
            self.check("d5.overlays", bool(re.search(
                "move|wasd|arrow|select|acceler|shift|click|instructions|controls|help",
                text(self.p.last), re.I)),
                "Actual readable title includes instructions or a discoverable Help control")
            self.start()
            r = self.key("Escape")
            self.check("d5.overlays", bool(re.search("paus", text(r), re.I)),
                       "Actual readable pause overlay is available after ordinary Start/Escape")
        self.obligation("COMMON/required-readable-instructions-and-pause", ["d5.overlays"],
                        ["FC-01", "FC-11", "FC-13", "GG-01", "GG-08", "GG-10", "PR-01", "PR-08", "PR-09"],
                        readable_overlays)
        def own_restore():
            for entry in self.model["entries"]:
                r = self.fresh(entry)
                before = copy.deepcopy(self.validate_schema(r))
                before["actors"] = [a for a in before["actors"] if a["kind"] != "control"]
                r = self.p.call("restore", save=before, seconds=0)
                after = self.validate_schema(r)
                self.check("d1.service", equivalent(frozen_state(before), frozen_state(after)),
                           "Every chapter restores its own unedited detached public state before any authored fixture")
                self.p.call("detach", seconds=0)
                self.p.call("invalid", seconds=0)
        self.obligation("COMMON/session-detached-atomic-own-restore", ["d1.service"],
                        ["DELIVERY"], own_restore)

    def save(self):
        super().save()
        if getattr(self, "coverage_executions", None) and self.out.exists():
            write(self.out / "coverage-execution.json", self.coverage_executions)

