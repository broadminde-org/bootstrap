"""Console metadata only; bootstrap local repair, 2026-11-23.

Adapted from ComposioHQ/awesome-claude-skills; original licenses retained.
Raw console text/arguments are never read, printed, or retained.
"""

from _support import arguments, exercise, run, save_counts


def main() -> None:
    args = arguments(__doc__)
    from playwright.sync_api import sync_playwright

    counts = {"console_messages_suppressed": 0}
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            page = browser.new_page()

            def handle_console_message(_message: object) -> None:
                counts["console_messages_suppressed"] = min(
                    1_000_000, counts["console_messages_suppressed"] + 1
                )

            page.on("console", handle_console_message)
            exercise(page, args)
        finally:
            browser.close()
    save_counts(args.output, counts)


if __name__ == "__main__":
    run(main)
