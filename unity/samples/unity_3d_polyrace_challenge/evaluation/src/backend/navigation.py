"""Generic ordinary-UI fallback, independent of candidate source and object names.

The required actor/service identity is still checked separately. An unrelated
working button must not become untestable just because ResolveActor is faulty.
"""
import re


def control_pattern(identity, content):
    fixed = {
        "start": r"^(?:play|new game|start|begin|start race|new expedition)$",
        "menu": r"^(?:menu|main menu|return to menu|back to menu)$",
        "pause": r"^pause$",
        "resume": r"^(?:resume|continue|continue game)$",
        "restart": r"^(?:retry|restart|retry race|restart race|restart expedition|retry level)$",
        "next": r"^(?:next|next level|next track|continue)$",
        "continue": r"^(?:continue|continue manual save|load game)$",
        "save": r"^(?:save|save game|manual save)$",
        "shop": r"^(?:shop|powers|power shop)$",
        "close_shop": r"^(?:return to cave|close|back|return)$",
        "options": r"^options$",
        "volume": r"^(?:toggle volume|volume|sound|mute|unmute)(?:\s*[::]?\s*(?:on|off|0|1))?$",
        "return": r"^(?:return|back|menu|return to menu)$",
        "mode_time": r"^(?:time attack|time)$",
        "mode_distance": r"^(?:distance sprint|distance)$",
    }
    if identity in fixed:
        return fixed[identity]
    if re.fullmatch(r"(?:track|level)_[1-5]", identity or ""):
        kind, number = identity.split("_")
        return rf"^{kind}\s*{number}(?:\b.*)?$"
    if re.fullmatch(r"craft_[0-3]", identity or ""):
        car = next(x for x in content["vehicles"] if str(x["id"]) == identity.split("_")[1])
        return rf"^{re.escape(car['name'])}(?:\b.*)?$"
    if (identity or "").startswith("card_"):
        return rf"^{re.escape(identity[5:])}(?:\b.*)?$"
    return None


def labels(reply, identity, content):
    pattern = control_pattern(identity, content)
    if pattern is None:
        return []
    found = []
    for item in reply.get("ui") or []:
        if not item.get("active") or item.get("color", {}).get("a", 1) <= .1:
            continue
        original = item.get("text") or ""
        normalized = re.sub(r"<[^>]+>", "", original).strip()
        if re.fullmatch(pattern, normalized, re.I | re.S) and original not in found:
            found.append(original)
    return found
