"""Independent oracle derived from the published Match3 rules.

Adapted from the author-side independent probe, not from Gold Lua. This module
never imports, executes, or reads a candidate implementation.
"""

from dataclasses import dataclass
from functools import lru_cache

W, H, MOD = 15, 10, 2147483647
DIRECTIONS = ("left", "right", "up", "down")


def initial(seed=7301):
    board = [[None for _ in range(H)] for _ in range(W)]
    for y in range(H):
        for x in range(W):
            while True:
                seed = (16807 * seed) % MOD
                color = seed % 6
                if x >= 2 and board[x - 1][y] == board[x - 2][y] == color:
                    continue
                if y >= 2 and board[x][y - 1] == board[x][y - 2] == color:
                    continue
                board[x][y] = color
                break
    return tuple(tuple(c) for c in board), seed


def at(board, x, y):
    return board[x][y] if 0 <= x < W and 0 <= y < H else None


def line_at(board, x, y):
    c = at(board, x, y)
    if c is None:
        return False
    for dx, dy in ((1, 0), (0, 1)):
        count = 1
        for sign in (-1, 1):
            xx, yy = x + sign * dx, y + sign * dy
            while at(board, xx, yy) == c:
                count += 1
                xx += sign * dx
                yy += sign * dy
        if count >= 3:
            return True
    return False


def matches(board):
    cells, lines = set(), set()
    for horizontal in (True, False):
        for fixed in range(H if horizontal else W):
            start = 0
            length = W if horizontal else H
            while start < length:
                finish = start + 1
                x, y = (start, fixed) if horizontal else (fixed, start)
                c = at(board, x, y)
                while finish < length:
                    xx, yy = (finish, fixed) if horizontal else (fixed, finish)
                    if at(board, xx, yy) != c:
                        break
                    finish += 1
                if c is not None and finish - start >= 3:
                    cells.update(((i, fixed) if horizontal else (fixed, i)) for i in range(start, finish))
                    if finish - start >= 4:
                        radius = 1 if finish - start >= 5 else 0
                        for n in range(max(0, fixed - radius), min(H if horizontal else W, fixed + radius + 1)):
                            lines.add((horizontal, n))
                start = finish
    return cells, lines


@dataclass(frozen=True)
class State:
    board: tuple
    seed: int
    cleared: int = 0


@lru_cache(maxsize=50000)
def step(state, direction):
    board = [list(c) for c in state.board]
    seed, cleared, batches = state.seed, state.cleared, []
    dx, dy = {"left": (-1, 0), "right": (1, 0), "up": (0, 1), "down": (0, -1)}[direction]
    used, swaps = set(), 0
    xs = range(W - 1, -1, -1) if direction == "left" else range(W)
    ys = range(H - 1, -1, -1) if direction == "down" else range(H)
    for x in xs:
        for y in ys:
            nx, ny = x + dx, y + dy
            if at(board, nx, ny) is None or (x, y) in used or (nx, ny) in used:
                continue
            board[x][y], board[nx][ny] = board[nx][ny], board[x][y]
            if line_at(board, x, y) or line_at(board, nx, ny):
                used.update(((x, y), (nx, ny)))
                swaps += 1
            else:
                board[x][y], board[nx][ny] = board[nx][ny], board[x][y]
    pending = set()
    for _ in range(100):
        if pending:
            cells = {((i, n) if horizontal else (n, i)) for horizontal, n in pending
                     for i in range(W if horizontal else H)}
            pending = set()
        else:
            cells, pending = matches(board)
        if not cells:
            break
        batches.append(len(cells))
        cleared += len(cells)
        for x, y in cells:
            board[x][y] = None
        for x in range(W):
            kept = [c for c in board[x] if c is not None]
            board[x] = kept
            while len(board[x]) < H:
                seed = (16807 * seed) % MOD
                board[x].append(seed % 6)
    else:
        raise AssertionError("cascade did not terminate")
    assert not matches(board)[0]
    return State(tuple(tuple(c) for c in board), seed, cleared), swaps, batches


def no_match_route(seed, moves, target_score):
    """Find a reachable negative-input case from public data, not a Gold route."""
    board, cursor=initial(seed)
    frontier=[(State(board,cursor),())]
    for _ in range(moves):
        choices=[]
        for state,route in frontier:
            for direction in DIRECTIONS:
                nxt,swaps,_=step(state,direction)
                if nxt.cleared*10>=target_score:continue
                path=route+(direction,)
                if swaps==0:return path
                choices.append((swaps,nxt.cleared,nxt,path))
        unique={}
        for item in sorted(choices,key=lambda c:(c[0],c[1],c[3])):
            unique.setdefault((item[2].board,item[2].seed),item)
        frontier=[(x[2],x[3]) for x in list(unique.values())[:128]]
    raise ValueError('NO_REACHABLE_NO_MATCH_CASE_FOUND')
