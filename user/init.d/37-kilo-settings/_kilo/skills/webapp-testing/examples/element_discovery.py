"""Discover element counts, not sensitive text/attributes or screenshots.

Bootstrap local repair, 2026-11-23, of ComposioHQ/awesome-claude-skills;
original licenses retained. Inspect app content with authorized reviewed tools.
"""

from _support import arguments, exercise, run, save_counts


def main() -> None:
    args = arguments(__doc__)
    from playwright.sync_api import sync_playwright

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            page = browser.new_page()
            exercise(page, args)
            counts = {
                "buttons": min(1_000_000, page.get_by_role("button").count()),
                "links": min(1_000_000, page.get_by_role("link").count()),
                "inputs": min(
                    1_000_000, page.locator("input, textarea, select").count()
                ),
            }
        finally:
            browser.close()
    save_counts(args.output, counts)


if __name__ == "__main__":
    run(main)
