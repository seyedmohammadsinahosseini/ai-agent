"""Captures README screenshots by driving the real Flutter web UI live.

The UI talks to the real local FastAPI server (http://127.0.0.1:8765) with the
native C++ engine built, using the scripted OpenAI-compatible demo provider
(docs/demo/mock_provider.py). Saved chats were created through the app's own
HTTP API (docs/demo/run_demo_flows.py); the build-mode chat below is
conducted entirely inside the UI - folder selection, mode switch, typing,
confirmation dialog and execution all happen through the app itself, and the
command really runs through the native engine.
"""
import os
import time
from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8765"
OUT = "/home/user/ai-terminal/docs/images"
os.makedirs(OUT, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch(args=["--force-color-profile=srgb"])
    page = browser.new_page(viewport={"width": 1520, "height": 950}, device_scale_factor=2)
    page.goto(URL, wait_until="load")
    time.sleep(12)  # Flutter web boot (main.dart.js + CanvasKit)

    # Enable the accessibility/semantics tree so controls are clickable by name.
    page.evaluate(
        "document.querySelector('flt-semantics-placeholder') && "
        "document.querySelector('flt-semantics-placeholder').click()"
    )
    time.sleep(3)

    def shot(name):
        path = os.path.join(OUT, name)
        page.screenshot(path=path)
        print("saved", path)

    def click_button(name_part, **kw):
        page.get_by_role("button", name=name_part, **kw).first.click()
        time.sleep(1.2)

    # 0 - App overview (empty chat, model panel with the demo provider).
    shot("00-overview.png")

    # 1 - Plan mode: SAFE read-only commands auto-executed with real output.
    click_button("Show me what's inside my project workspace")
    time.sleep(1.5)
    shot("01-plan-mode-auto-execution.png")

    # 2 - Catastrophic command permanently blocked by the native risk engine.
    click_button("Actually, just format my C drive")
    time.sleep(1.5)
    shot("03-blocked-catastrophic-command.png")

    # 3 - Live build-mode flow, entirely inside the UI.
    click_button("New Chat")
    click_button("No folder selected")
    click_button("ai-terminal")
    click_button("demo_workspace")
    click_button("Use this folder")
    click_button("Build", exact=True)
    page.get_by_role("textbox").click()
    page.keyboard.type("Create a reports folder and save a status file with today's date inside it.")
    page.keyboard.press("Enter")
    time.sleep(4)  # provider round-trip + render
    shot("04-pending-confirmation-banner.png")

    click_button("Review & confirm")
    time.sleep(1.5)
    shot("05-confirmation-dialog.png")

    click_button("Run it")
    time.sleep(4)  # native engine executes through the PTY and streams output
    shot("02-build-mode-confirmed-execution.png")

    browser.close()
print("done")
