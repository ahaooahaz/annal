#!/usr/bin/env python3
"""Terminal Minesweeper -- standard-library curses only.

Usage:
    python3 minesweeper.py [easy|medium|hard]
    python3 minesweeper.py ROWS COLS MINES

Controls:
    arrows / hjkl    move cursor
    space / enter    dig
    f                toggle flag
    a                chord: dig neighbours when flags match the number
    r                restart
    q                quit
    left click digs, right click flags
"""

import curses
import random
import sys
import time

LEVELS = {
    "easy": (9, 9, 10),
    "medium": (16, 16, 40),
    "hard": (16, 30, 99),
}

HIDDEN, REVEALED, FLAGGED = 0, 1, 2


class Board:
    def __init__(self, rows, cols, mines):
        self.rows, self.cols, self.mines = rows, cols, mines
        self.state = [[HIDDEN] * cols for _ in range(rows)]
        self.mine = [[False] * cols for _ in range(rows)]
        self.count = [[0] * cols for _ in range(rows)]
        self.placed = False
        self.dead = False
        self.revealed_n = 0
        self.boom = None  # 踩中的那颗雷

    def neighbors(self, r, c):
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if dr or dc:
                    nr, nc = r + dr, c + dc
                    if 0 <= nr < self.rows and 0 <= nc < self.cols:
                        yield nr, nc

    def _place(self, safe_r, safe_c):
        """首次挖开保证安全：光标及其八邻域都不布雷。"""
        forbidden = {(safe_r, safe_c)} | set(self.neighbors(safe_r, safe_c))
        cells = [
            (r, c)
            for r in range(self.rows)
            for c in range(self.cols)
            if (r, c) not in forbidden
        ]
        # 雷太多时退化为只保护落点本身
        if len(cells) < self.mines:
            cells = [
                (r, c)
                for r in range(self.rows)
                for c in range(self.cols)
                if (r, c) != (safe_r, safe_c)
            ]
        for r, c in random.sample(cells, self.mines):
            self.mine[r][c] = True
        for r in range(self.rows):
            for c in range(self.cols):
                self.count[r][c] = sum(
                    1 for nr, nc in self.neighbors(r, c) if self.mine[nr][nc]
                )
        self.placed = True

    @property
    def flags(self):
        return sum(row.count(FLAGGED) for row in self.state)

    @property
    def won(self):
        return not self.dead and self.revealed_n == self.rows * self.cols - self.mines

    def toggle_flag(self, r, c):
        if self.state[r][c] == HIDDEN:
            self.state[r][c] = FLAGGED
        elif self.state[r][c] == FLAGGED:
            self.state[r][c] = HIDDEN

    def reveal(self, r, c):
        if not self.placed:
            self._place(r, c)
        if self.state[r][c] != HIDDEN:
            return
        if self.mine[r][c]:
            self.dead = True
            self.boom = (r, c)
            self.state[r][c] = REVEALED
            return
        # 迭代式洪水填充
        stack = [(r, c)]
        while stack:
            cr, cc = stack.pop()
            if self.state[cr][cc] != HIDDEN:
                continue
            self.state[cr][cc] = REVEALED
            self.revealed_n += 1
            if self.count[cr][cc] == 0:
                for nr, nc in self.neighbors(cr, cc):
                    if self.state[nr][nc] == HIDDEN and not self.mine[nr][nc]:
                        stack.append((nr, nc))

    def chord(self, r, c):
        """已翻开的数字格，若周围旗数等于数字，则挖开其余邻格。"""
        if self.state[r][c] != REVEALED or self.count[r][c] == 0:
            return
        nb = list(self.neighbors(r, c))
        if sum(1 for nr, nc in nb if self.state[nr][nc] == FLAGGED) != self.count[r][c]:
            return
        for nr, nc in nb:
            if self.state[nr][nc] == HIDDEN:
                self.reveal(nr, nc)
                if self.dead:
                    return


NUM_COLOR = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8}
C_HIDDEN, C_MINE, C_FLAG, C_CURSOR, C_TEXT = 9, 10, 11, 12, 13


def init_colors():
    curses.start_color()
    curses.use_default_colors()
    pairs = {
        1: (curses.COLOR_CYAN, -1),
        2: (curses.COLOR_GREEN, -1),
        3: (curses.COLOR_RED, -1),
        4: (curses.COLOR_BLUE, -1),
        5: (curses.COLOR_MAGENTA, -1),
        6: (curses.COLOR_CYAN, -1),
        7: (curses.COLOR_YELLOW, -1),
        8: (curses.COLOR_WHITE, -1),
        C_HIDDEN: (curses.COLOR_BLUE, -1),
        C_MINE: (curses.COLOR_WHITE, curses.COLOR_RED),
        C_FLAG: (curses.COLOR_RED, -1),
        C_CURSOR: (curses.COLOR_BLACK, curses.COLOR_YELLOW),
        C_TEXT: (curses.COLOR_YELLOW, -1),
    }
    for idx, (fg, bg) in pairs.items():
        try:
            curses.init_pair(idx, fg, bg)
        except curses.error:
            pass


TOP, LEFT = 3, 2


def put(win, y, x, s, attr=0):
    """越界写入在 curses 里会抛异常（右下角末格、窗口被缩小），按窗口宽度截断后再吞掉异常。"""
    h, w = win.getmaxyx()
    if not 0 <= y < h or x >= w:
        return
    if x + len(s) >= w:
        s = s[: max(0, w - x - 1)]
    try:
        win.addstr(y, x, s, attr)
    except curses.error:
        pass


def cell_glyph(b, r, c):
    """返回 (字符, 颜色对编号, 额外属性)。"""
    st = b.state[r][c]
    if st == FLAGGED:
        if b.dead and not b.mine[r][c]:
            return "X", C_FLAG, 0  # 标错了
        return "F", C_FLAG, curses.A_BOLD
    if st == HIDDEN:
        if b.dead and b.mine[r][c]:
            return "*", C_MINE, 0  # 游戏结束显示所有雷
        return ".", C_HIDDEN, curses.A_DIM
    if b.mine[r][c]:
        return "*", C_MINE, curses.A_BOLD
    n = b.count[r][c]
    if n == 0:
        return " ", C_TEXT, 0
    return str(n), NUM_COLOR[n], curses.A_BOLD


def draw(stdscr, b, cur, elapsed, msg):
    stdscr.erase()
    h, w = stdscr.getmaxyx()
    need_h, need_w = TOP + b.rows + 3, LEFT + b.cols * 2 + 2
    if h < need_h or w < need_w:
        put(stdscr, 0, 0, f"Window too small: need {need_w}x{need_h}, got {w}x{h}")
        put(stdscr, 1, 0, "Enlarge the window, or start a smaller board.")
        stdscr.refresh()
        return

    left = b.mines - b.flags
    header = f"  Mines {left:>3}   Time {int(elapsed):>4}s   {b.rows}x{b.cols}/{b.mines}"
    put(stdscr, 0, 0, header, curses.color_pair(C_TEXT) | curses.A_BOLD)

    # 列标尺
    put(
        stdscr,
        TOP - 1,
        LEFT,
        "".join(f"{c % 10} " for c in range(b.cols)),
        curses.color_pair(C_HIDDEN) | curses.A_DIM,
    )

    for r in range(b.rows):
        put(stdscr, TOP + r, 0, f"{r % 10} ", curses.color_pair(C_HIDDEN) | curses.A_DIM)
        for c in range(b.cols):
            ch, pair, attr = cell_glyph(b, r, c)
            if (r, c) == cur and not (b.dead or b.won):
                pair, attr = C_CURSOR, curses.A_BOLD
            put(stdscr, TOP + r, LEFT + c * 2, ch, curses.color_pair(pair) | attr)

    if msg:
        put(stdscr, TOP + b.rows + 1, 0, msg, curses.color_pair(C_TEXT) | curses.A_BOLD)
    else:
        put(
            stdscr,
            TOP + b.rows + 1,
            0,
            "hjkl move | space dig | f flag | a chord | r restart | q quit",
            curses.A_DIM,
        )
    stdscr.refresh()


def new_board(rows, cols, mines):
    return Board(rows, cols, mines)


def main(stdscr, rows, cols, mines):
    curses.curs_set(0)
    stdscr.keypad(True)
    init_colors()
    try:
        curses.mousemask(curses.ALL_MOUSE_EVENTS)
    except curses.error:
        pass

    b = new_board(rows, cols, mines)
    cur = (rows // 2, cols // 2)
    start = None
    frozen = 0.0

    while True:
        if b.dead or b.won:
            elapsed = frozen
            msg = (
                "  BOOM! You hit a mine.  r restart | q quit"
                if b.dead
                else f"  Cleared in {int(frozen)}s!  r restart | q quit"
            )
        else:
            elapsed = time.monotonic() - start if start else 0.0
            frozen = elapsed
            msg = ""

        draw(stdscr, b, cur, elapsed, msg)

        # 计时中让 getch 超时刷新，未开局则阻塞等待
        stdscr.timeout(200 if (start and not (b.dead or b.won)) else -1)
        try:
            key = stdscr.getch()
        except KeyboardInterrupt:
            return
        if key == -1:
            continue

        r, c = cur
        if key in (ord("q"), 27):
            return
        if key == ord("r"):
            b = new_board(rows, cols, mines)
            cur = (rows // 2, cols // 2)
            start, frozen = None, 0.0
            continue
        if b.dead or b.won:
            continue

        if key in (curses.KEY_UP, ord("k")):
            cur = (max(0, r - 1), c)
        elif key in (curses.KEY_DOWN, ord("j")):
            cur = (min(rows - 1, r + 1), c)
        elif key in (curses.KEY_LEFT, ord("h")):
            cur = (r, max(0, c - 1))
        elif key in (curses.KEY_RIGHT, ord("l")):
            cur = (r, min(cols - 1, c + 1))
        elif key in (ord(" "), 10, 13, curses.KEY_ENTER):
            if start is None:
                start = time.monotonic()
            if b.state[r][c] == REVEALED:
                b.chord(r, c)
            else:
                b.reveal(r, c)
        elif key == ord("f"):
            if start is None:
                start = time.monotonic()
            b.toggle_flag(r, c)
        elif key == ord("a"):
            b.chord(r, c)
        elif key == curses.KEY_MOUSE:
            try:
                _, mx, my, _, bstate = curses.getmouse()
            except curses.error:
                continue
            mr, mc = my - TOP, (mx - LEFT) // 2
            if 0 <= mr < rows and 0 <= mc < cols and (mx - LEFT) % 2 == 0:
                cur = (mr, mc)
                if start is None:
                    start = time.monotonic()
                if bstate & curses.BUTTON3_CLICKED:
                    b.toggle_flag(mr, mc)
                elif bstate & curses.BUTTON1_CLICKED:
                    if b.state[mr][mc] == REVEALED:
                        b.chord(mr, mc)
                    else:
                        b.reveal(mr, mc)


def parse_args(argv):
    if not argv:
        return LEVELS["easy"]
    if len(argv) == 1:
        key = argv[0].lower()
        if key in LEVELS:
            return LEVELS[key]
        sys.exit(
            f"Unknown level {argv[0]!r}. Choose from: {', '.join(LEVELS)}, "
            "or pass ROWS COLS MINES."
        )
    if len(argv) == 3:
        try:
            rows, cols, mines = (int(x) for x in argv)
        except ValueError:
            sys.exit("ROWS, COLS and MINES must be integers.")
        if rows < 2 or cols < 2:
            sys.exit("Board must be at least 2x2.")
        if not 1 <= mines < rows * cols:
            sys.exit(f"MINES must be between 1 and {rows * cols - 1}.")
        return rows, cols, mines
    sys.exit(__doc__)


if __name__ == "__main__":
    curses.wrapper(main, *parse_args(sys.argv[1:]))
