from kitty.boss import Boss


def main(args: list[str]) -> str:
    pass


from kittens.tui.handler import result_handler


@result_handler(no_ui=True)
def handle_result(
    args: list[str],
    answer: str,
    target_window_id: int,
    boss: Boss,
) -> None:
    tab = boss.active_tab
    if tab is None:
        return

    if len(tab.windows) <= 1:
        return

    if tab.current_layout.name == "stack":
        tab.last_used_layout()
    else:
        tab.goto_layout("stack")
