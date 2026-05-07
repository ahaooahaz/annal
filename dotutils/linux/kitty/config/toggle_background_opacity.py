#!/usr/bin/env python3
from kitty.boss import Boss


def main(args):
    pass


from kittens.tui.handler import result_handler


@result_handler(no_ui=True)
def handle_result(
    args: list[str], answer: str, target_window_id: int, boss: Boss
) -> None:
    import kitty.fast_data_types as f

    os_window_id = f.current_focused_os_window_id()
    current_opacity = f.background_opacity_of(os_window_id)
    boss.set_background_opacity(
        "{}".format(f.get_options().background_opacity)
        if current_opacity == 1.0
        else "1"
    )
