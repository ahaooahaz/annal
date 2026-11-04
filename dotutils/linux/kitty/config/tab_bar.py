from kitty.tab_bar import draw_tab_with_powerline, as_rgb
from kitty.fast_data_types import Screen, Color

# ---- Catppuccin Mocha --------------------------------------------------
BASE = 0x1E1E2E
CRUST = 0x11111B
TEXT = 0x364153
BLACK = 0x000000

PALETTE = [
    0xF38BA8,  # red
    0xFAB387,  # peach
    0xF9E2AF,  # yellow
    0xA6E3A1,  # green
    0x94E2D5,  # teal
    0x89DCEB,  # sky
    0x89B4FA,  # blue
    0xCBA6F7,  # mauve
    0xF5C2E7,  # pink
    0xB4BEFE,  # lavender
]
# -------------------------------------------------------------------------


def hexcolor(h):
    return Color((h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF)


def draw_tab(
    draw_data,
    screen: Screen,
    tab,
    before,
    max_title_length,
    index,
    is_last,
    extra_data,
):
    cur_color = PALETTE[(index - 1) % len(PALETTE)]
    next_color = PALETTE[index % len(PALETTE)] if not is_last else BASE
    fg_color = BASE if not tab.is_active else CRUST

    # Plain text logo before first tab
    if index == 1:
        screen.cursor.bg = as_rgb(cur_color)
        screen.cursor.fg = as_rgb(TEXT)
        screen.cursor.bold = True
        screen.draw(" 󰄛 ")

    screen.cursor.bg = as_rgb(cur_color)
    screen.cursor.fg = as_rgb(fg_color)
    screen.cursor.bold = tab.is_active

    draw_data = draw_data._replace(
        active_bg=hexcolor(next_color),
        inactive_bg=hexcolor(next_color),
    )
    return draw_tab_with_powerline(
        draw_data,
        screen,
        tab,
        before,
        max_title_length,
        index,
        is_last,
        extra_data,
    )
