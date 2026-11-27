"""Exercise reviewed local HTML with supplied action/result locators.

Bootstrap local repair, 2026-11-23, of ComposioHQ/awesome-claude-skills;
original licenses retained. Local HTML may run scripts and issue network calls.
"""

from _support import arguments, exercise, run, save_counts


def main() -> None:
    args = arguments(__doc__, local=True)
    if not args.action_selector:
        raise ValueError("static interaction requires action/result selectors")
    from playwright.sync_api import sync_playwright

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            page = browser.new_page()
            exercise(page, args)
        finally:
            browser.close()
    save_counts(args.output, {"interaction_verified": 1})


if __name__ == "__main__":
    run(main)
