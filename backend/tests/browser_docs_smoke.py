"""Optional browser integration check against an isolated synthetic temporary database.
Install Playwright Chromium before running; no existing records or patient data are used.
"""

import sys, tempfile, threading, socket, time, json, io, os
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.main import create_app
from app.live_docs import state, Settings
from cryptography.fernet import Fernet
import uvicorn
from playwright.sync_api import sync_playwright

with tempfile.TemporaryDirectory(prefix="medai-docs-browser-") as folder:
    app = create_app(
        folder, Fernet.generate_key().decode(), ocr_enabled=False, sos_sandbox=False
    )
    store = app.state.store
    user = store.create_user(
        "browser-admin@example.test", "Browser-test-password", "Synthetic Admin"
    )
    with store.db() as db:
        db.execute("INSERT INTO docs_admins VALUES(?,?)", (user, "super_admin"))
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    server = uvicorn.Server(
        uvicorn.Config(app, host="127.0.0.1", port=port, log_level="error")
    )
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    for _ in range(100):
        if server.started:
            break
        time.sleep(0.05)
    origin = f"http://127.0.0.1:{port}"
    with sync_playwright() as p:
        browser = p.chromium.launch(
            executable_path=os.getenv("MEDAI_CHROMIUM_PATH") or None,
            headless=True,
            args=["--no-sandbox"] if sys.platform.startswith("linux") else [],
        )
        context = browser.new_context(viewport={"width": 1440, "height": 1000})
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(origin + "/docs/admin")
        page.get_by_label("Email", exact=True).fill("browser-admin@example.test")
        page.get_by_label("Password", exact=True).fill("Browser-test-password")
        page.get_by_role("button", name="Sign in", exact=True).click()
        page.get_by_role("heading", name="Document identity").wait_for()
        page.get_by_label("Public demo video URL (HTTPS, optional)").fill(
            "https://example.test/medai-demo"
        )
        page.locator(".section-item").first.get_by_role(
            "button", name="↓", exact=True
        ).click()
        page.get_by_label("Title", exact=True).fill("Med.ai — connected care, verified")
        page.get_by_role("button", name="Save draft", exact=True).click()
        page.get_by_text(
            "Draft saved. Public content changes only after Publish draft."
        ).wait_for()
        page.get_by_role("button", name="Publish draft", exact=True).click()
        page.get_by_text(
            "Content published, but access is OFF or outside the scheduled window."
        ).wait_for()
        page.get_by_label("Enable /docs access").check()
        page.get_by_label("Publishing mode").select_option("immediate")
        page.get_by_role("button", name="Apply visibility settings").click()
        page.get_by_text("Public access is enabled now.").wait_for()
        public = context.new_page()
        public.on("pageerror", lambda e: errors.append(str(e)))
        public.goto(origin + "/docs")
        public.get_by_role(
            "heading", name="Med.ai — connected care, verified", exact=True
        ).wait_for()
        assert public.locator("svg.diagram").count() == 2
        assert (
            public.get_by_role("link", name="Watch the product demo").get_attribute(
                "href"
            )
            == "https://example.test/medai-demo"
        )
        page.get_by_role("button", name="Refresh metrics", exact=True).click()
        public.get_by_role("searchbox").fill("kidney")
        public.get_by_role("searchbox").fill("")
        assert public.locator("main section").count() >= 24
        assert public.evaluate("document.documentElement.scrollWidth <= innerWidth")
        contract = public.locator("#apis details").first
        contract.locator("summary").click()
        public.wait_for_timeout(5500)
        assert contract.get_attribute("open") is not None
        public.screenshot(path=str(Path(folder) / "desktop.png"), full_page=False)
        public.pdf(path=str(Path(folder) / "print.pdf"), format="A4")
        # Saved drafts do not replace the public copy until publishing.
        page.get_by_label("Title", exact=True).fill("Draft-only title")
        page.get_by_role("button", name="Save draft", exact=True).click()
        page.get_by_text(
            "Draft saved. Public content changes only after Publish draft."
        ).wait_for()
        assert (
            public.request.get(origin + "/api/docs/public").json()["document"]["title"]
            == "Med.ai — connected care, verified"
        )
        # Team registration and image preprocessing exercise the real browser form.
        page.get_by_role("button", name="Add team member").click()
        page.get_by_label("Full name", exact=True).fill("Synthetic Contributor")
        page.get_by_label("Project role", exact=True).fill("Demo contributor")
        page.get_by_label("Public email", exact=True).fill("demo@example.test")
        from PIL import Image

        image = io.BytesIO()
        Image.new("RGB", (400, 800), "#2562ed").save(image, format="JPEG")
        page.locator("input[type=file]").set_input_files(
            {
                "name": "synthetic.jpg",
                "mimeType": "image/jpeg",
                "buffer": image.getvalue(),
            }
        )
        page.get_by_text(
            "Profile photo resized to 256 × 256. Publish the draft to make it public."
        ).wait_for()
        page.get_by_label("Title", exact=True).fill("Med.ai — connected care, verified")
        page.get_by_role("button", name="Publish draft", exact=True).click()
        page.get_by_text(
            "Published. The public page updates within five seconds."
        ).wait_for()
        public.reload()
        public.get_by_role(
            "heading", name="Synthetic Contributor", exact=True
        ).wait_for()
        assert public.locator(".team-card img").count() == 1
        mobile = context.new_page()
        mobile.set_viewport_size({"width": 390, "height": 844})
        mobile.on("pageerror", lambda e: errors.append(str(e)))
        mobile.goto(origin + "/docs")
        mobile.get_by_role(
            "heading", name="Med.ai — connected care, verified", exact=True
        ).wait_for()
        assert mobile.evaluate("document.documentElement.scrollWidth <= innerWidth")
        mobile.get_by_role("button", name="Browse sections").click()
        assert mobile.locator(".sidebar").evaluate("e=>e.classList.contains('open')")
        mobile.screenshot(path=str(Path(folder) / "mobile.png"), full_page=False)
        mobile.set_viewport_size({"width": 768, "height": 1024})
        assert mobile.evaluate("document.documentElement.scrollWidth <= innerWidth")
        page.set_viewport_size({"width": 390, "height": 844})
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        page.set_viewport_size({"width": 1440, "height": 1000})
        # Turning OFF removes access to feed, exports, images and existing public views.
        page.get_by_label("Enable /docs access").uncheck()
        page.get_by_role("button", name="Apply visibility settings").click()
        page.get_by_text(
            "Public access is OFF or outside its scheduled window."
        ).wait_for()
        public.get_by_text(
            "Documentation is not available in the current publishing window.",
            exact=True,
        ).wait_for(timeout=10000)
        assert public.request.get(origin + "/api/docs/export").status == 403
        assert not errors, errors
        print(
            "Browser checks passed: admin sign-in, save/publish separation, visibility toggle, team/avatar upload, SVG diagrams, search, desktop/mobile widths, polling revocation and PDF generation."
        )
        browser.close()
    server.should_exit = True
    thread.join(timeout=5)
