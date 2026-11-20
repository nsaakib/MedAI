"use strict";
(() => {
  const { el, button, api, table, date, renderSections } = window.Docs;
  let token = sessionStorage.getItem("medai_docs_session") || "",
    data = null,
    dirty = false,
    drag = null,
    saving = false;
  const app = document.querySelector("#app");
  function auth(path, options = {}) {
    return api(path, {
      ...options,
      headers: { ...options.headers, Authorization: "Bearer " + token },
    });
  }
  function json(method, body) {
    return {
      method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    };
  }
  function mark() {
    dirty = true;
    const n = document.querySelector("#save-status");
    if (n) n.textContent = "Unsaved draft changes";
  }
  function input(label, value, change, type = "text") {
    const box = el("div"),
      l = el("label", "", label),
      n = el("input");
    const id = "f-" + Math.random().toString(36).slice(2);
    l.htmlFor = id;
    n.id = id;
    n.type = type;
    n.value = value ?? "";
    n.addEventListener("input", () => change(n.value));
    box.append(l, n);
    return box;
  }
  function notice(text, error = false) {
    const n =
      document.querySelector("#studio-notice") ||
      document.querySelector("#login-notice");
    if (n) {
      n.textContent = text;
      n.className = "notice" + (error ? " error" : "");
      n.setAttribute("role", "status");
    }
  }
  async function execute(action) {
    if (saving) return;
    saving = true;
    document
      .querySelectorAll("[data-action]")
      .forEach((n) => (n.disabled = true));
    try {
      await action();
    } catch (e) {
      notice(e.message, true);
      if (e.status === 401) logout();
    } finally {
      saving = false;
      document
        .querySelectorAll("[data-action]")
        .forEach((n) => (n.disabled = false));
    }
  }
  function action(text, fn, cls = "") {
    const b = button(text, () => execute(fn), cls);
    b.dataset.action = "1";
    return b;
  }
  function logout() {
    const old = token;
    if (old)
      fetch("/api/auth/logout", {
        method: "POST",
        headers: { Authorization: "Bearer " + old },
      }).catch(() => {});
    token = "";
    sessionStorage.removeItem("medai_docs_session");
    data = null;
    dirty = false;
    login();
  }
  function login() {
    app.replaceChildren();
    const panel = el("main", "login");
    panel.append(
      el("a", "brand", "Med.ai"),
      el("h1", "", "Documentation studio"),
      el(
        "p",
        "muted",
        "Sign in with a locally authorized documentation-admin account. Patient and partner accounts are not automatically administrators.",
      ),
    );
    const form = el("form");
    let email = "",
      password = "";
    const ef = input("Email", "", (v) => (email = v), "email"),
      pf = input("Password", "", (v) => (password = v), "password");
    ef.querySelector("input").required = true;
    ef.querySelector("input").autocomplete = "username";
    pf.querySelector("input").required = true;
    pf.querySelector("input").autocomplete = "current-password";
    const submit = el("button", "primary", "Sign in");
    submit.type = "submit";
    const n = el("p", "notice");
    n.id = "login-notice";
    form.append(
      ef,
      pf,
      el(
        "p",
        "muted",
        "Admin access is granted with SETUP_DOCS_ADMIN.ps1 on the server PC.",
      ),
      submit,
      n,
    );
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      submit.disabled = true;
      try {
        const session = await api(
          "/api/auth/login",
          json("POST", { email, password }),
        );
        token = session.token;
        data = await auth("/api/docs/admin");
        sessionStorage.setItem("medai_docs_session", token);
        password = "";
        studio();
      } catch (error) {
        token = "";
        notice(error.message, true);
      } finally {
        submit.disabled = false;
      }
    });
    panel.append(form);
    app.append(panel);
  }
  async function reload() {
    data = await auth("/api/docs/admin");
    dirty = false;
    studio();
  }
  async function saveDraft() {
    const r = await auth(
      "/api/docs/admin/draft",
      json("PUT", { base_revision: data.revision, document: data.document }),
    );
    data.revision = r.revision;
    dirty = false;
    document.querySelector("#save-status").textContent =
      "Draft saved · revision " + r.revision;
    notice("Draft saved. Public content changes only after Publish draft.");
  }
  function move(index, delta) {
    const next = index + delta;
    if (next < 0 || next >= data.document.sections.length) return;
    const list = data.document.sections;
    [list[index], list[next]] = [list[next], list[index]];
    mark();
    renderEditors();
  }
  function renderEditors() {
    const root = document.querySelector("#section-editors");
    root.replaceChildren();
    data.document.sections.forEach((s, i) => {
      const card = el("section", "section-item");
      card.draggable = true;
      card.dataset.id = s.id;
      const head = el("div", "section-heading"),
        label = el("strong", "", s.title);
      head.append(
        label,
        button("↑", () => move(i, -1)),
        button("↓", () => move(i, 1)),
      );
      if (s.source === "editorial")
        head.append(
          button("Remove", () => {
            if (confirm("Remove this draft section?")) {
              data.document.sections.splice(i, 1);
              mark();
              renderEditors();
            }
          }),
        );
      card.addEventListener("dragstart", (e) => {
        if (e.target.closest("input,textarea,[contenteditable]")) {
          e.preventDefault();
          return;
        }
        drag = s.id;
        card.classList.add("dragging");
        e.dataTransfer.setData("text/plain", s.id);
      });
      card.addEventListener("dragend", () => card.classList.remove("dragging"));
      card.addEventListener("dragover", (e) => e.preventDefault());
      card.addEventListener("drop", (e) => {
        e.preventDefault();
        const from = data.document.sections.findIndex((x) => x.id === drag);
        if (from < 0 || from === i) return;
        const [item] = data.document.sections.splice(from, 1);
        data.document.sections.splice(i, 0, item);
        mark();
        renderEditors();
      });
      card.append(
        head,
        input("Section title", s.title, (v) => {
          s.title = v;
          label.textContent = v;
          mark();
        }),
      );
      const group = el("select");
      group.setAttribute("aria-label", "Section group");
      for (const name of ["Pitch", "Product", "Engineering", "Operations"]) {
        const option = el("option", "", name);
        option.value = name;
        option.selected = name === s.group;
        group.append(option);
      }
      group.addEventListener("change", () => {
        s.group = group.value;
        mark();
      });
      card.append(
        el("label", "", "Navigation group"),
        group,
        el(
          "small",
          "",
          s.source === "editorial"
            ? "Editable narrative"
            : `Live block: ${s.source}. Its data is generated by the server; edit the explanation below.`,
        ),
      );
      const editor = el("div", "wysiwyg");
      editor.contentEditable = "true";
      editor.setAttribute("role", "textbox");
      editor.setAttribute("aria-label", s.title + " content");
      editor.setAttribute("aria-multiline", "true");
      editor.innerHTML = s.body;
      editor.addEventListener("input", () => {
        s.body = editor.innerHTML;
        mark();
      });
      const toolbar = el("div", "toolbar");
      for (const [name, cmd] of [
        ["Bold", "bold"],
        ["Italic", "italic"],
        ["Bullets", "insertUnorderedList"],
        ["Numbered", "insertOrderedList"],
      ]) {
        const b = button(name, () => {
          editor.focus();
          document.execCommand(cmd);
          s.body = editor.innerHTML;
          mark();
        });
        b.addEventListener("mousedown", (e) => e.preventDefault());
        toolbar.append(b);
      }
      card.append(toolbar, editor);
      if (s.source === "architecture" || s.source === "data-flow") {
        const diagram = el("textarea");
        diagram.value = JSON.stringify(s.diagram, null, 2);
        diagram.setAttribute("aria-label", s.title + " diagram JSON");
        diagram.addEventListener("input", () => {
          try {
            s.diagram = JSON.parse(diagram.value);
            diagram.setCustomValidity("");
            mark();
          } catch {
            diagram.setCustomValidity("Enter valid diagram JSON.");
          }
        });
        card.append(
          el("label", "", "SVG diagram: nodes and zero-based edge pairs"),
          diagram,
          el(
            "small",
            "",
            "Edit node text and edges. Up to eight nodes; the preview renders real SVG without a third-party CDN.",
          ),
        );
      }
      root.append(card);
    });
  }
  async function avatarPreview(img, id) {
    if (!id) return;
    try {
      const r = await fetch("/api/docs/admin/avatar/" + id, {
        headers: { Authorization: "Bearer " + token },
        cache: "no-store",
      });
      if (!r.ok) return;
      const src = URL.createObjectURL(await r.blob());
      img.src = src;
      img.addEventListener("load", () => URL.revokeObjectURL(src), {
        once: true,
      });
    } catch {}
  }
  function renderMembers() {
    const list = document.querySelector("#member-editors");
    list.replaceChildren();
    for (const m of data.document.members) {
      const card = el("div", "member-editor");
      const photo = el("img", "avatar");
      photo.alt = m.name + " profile";
      photo.width = 96;
      photo.height = 96;
      if (m.avatar) avatarPreview(photo, m.avatar);
      else photo.classList.add("hidden");
      const fields = el("div");
      fields.append(
        input("Full name", m.name, (v) => {
          m.name = v;
          mark();
        }),
        input("Project role", m.role, (v) => {
          m.role = v;
          mark();
        }),
        input(
          "Public email",
          m.email,
          (v) => {
            m.email = v;
            mark();
          },
          "email",
        ),
      );
      const upload = el("input");
      upload.type = "file";
      upload.accept = "image/jpeg,image/png";
      upload.setAttribute(
        "aria-label",
        "Upload profile image for " + (m.name || "member"),
      );
      upload.addEventListener("change", () =>
        execute(async () => {
          if (!upload.files[0]) return;
          const form = new FormData();
          form.append("file", upload.files[0]);
          const result = await auth("/api/docs/admin/avatar", {
            method: "POST",
            body: form,
          });
          m.avatar = result.id;
          photo.classList.remove("hidden");
          await avatarPreview(photo, m.avatar);
          mark();
          notice(
            "Profile photo resized to 256 × 256. Publish the draft to make it public.",
          );
        }),
      );
      card.append(
        photo,
        fields,
        el("label", "", "Profile photo · JPG / PNG, up to 6 MB"),
        upload,
        button("Remove member", () => {
          data.document.members = data.document.members.filter((x) => x !== m);
          mark();
          renderMembers();
        }),
      );
      list.append(card);
    }
  }
  function dhaka(iso) {
    return new Intl.DateTimeFormat("sv-SE", {
      timeZone: "Asia/Dhaka",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    })
      .format(new Date(iso))
      .replace(" ", "T");
  }
  function studio() {
    app.replaceChildren();
    const header = el("header", "topbar"),
      logo = el("a", "brand", "Med.ai / Studio");
    logo.href = "/docs/admin";
    const actions = el("div", "top-actions");
    actions.append(
      action("Save draft", saveDraft),
      action(
        "Publish draft",
        async () => {
          await saveDraft();
          const r = await auth(
            "/api/docs/admin/publish",
            json("POST", { base_revision: data.revision }),
          );
          data.revision = r.revision;
          notice(
            r.visible
              ? "Published. The public page updates within five seconds."
              : "Content published, but access is OFF or outside the scheduled window.",
          );
        },
        "primary",
      ),
      button("Sign out", logout),
    );
    header.append(logo, actions);
    const root = el("main", "studio"),
      note = el("div", "notice");
    note.id = "studio-notice";
    note.setAttribute("role", "status");
    note.textContent =
      "Drafts and publication are separate. Team names, photos and emails become public only after publishing and enabling access.";
    const status = el(
      "p",
      "statusbar",
      `Revision ${data.revision} · ${data.role} · public view ${data.visible ? "ON" : "OFF / outside window"}`,
    );
    status.id = "save-status";
    const grid = el("div", "studio-grid"),
      left = el("div"),
      right = el("aside");
    const title = el("section", "panel");
    title.append(
      el("h2", "", "Document identity"),
      input("Title", data.document.title, (v) => {
        data.document.title = v;
        mark();
      }),
      input("Tagline", data.document.tagline, (v) => {
        data.document.tagline = v;
        mark();
      }),
      input("Team name", data.document.team_name, (v) => {
        data.document.team_name = v;
        mark();
      }),
      input(
        "Public demo video URL (HTTPS, optional)",
        data.document.demo_url,
        (v) => {
          data.document.demo_url = v || null;
          mark();
        },
        "url",
      ),
    );
    const sections = el("section", "panel");
    sections.append(
      el("h2", "", "Sections"),
      el(
        "p",
        "muted",
        "Edit rich text, reorder with drag and drop or arrow buttons, then save and publish. Live data blocks stay connected to the server.",
      ),
    );
    const editors = el("div");
    editors.id = "section-editors";
    sections.append(
      editors,
      button("Add narrative section", () => {
        data.document.sections.push({
          id: "section-" + Date.now(),
          title: "New section",
          group: "Product",
          body: "<p>Add verified information here.</p>",
          source: "editorial",
          diagram: null,
        });
        mark();
        renderEditors();
      }),
    );
    const team = el("section", "panel");
    team.append(
      el("h2", "", "Team profiles"),
      el(
        "p",
        "muted",
        "Use contact details and photos that each member has agreed to publish. Photos are cropped uniformly and metadata is removed.",
      ),
    );
    const members = el("div");
    members.id = "member-editors";
    team.append(
      members,
      button("Add team member", () => {
        data.document.members.push({
          id: "member-" + Date.now(),
          name: "",
          role: "",
          email: "",
          avatar: null,
        });
        mark();
        renderMembers();
      }),
    );
    left.append(title, team, sections);
    const publishing = el("section", "panel");
    publishing.append(el("h2", "", "Publishing control"));
    const enabled = el("input");
    enabled.type = "checkbox";
    enabled.checked = data.settings.enabled;
    const enabledLabel = el("label");
    enabledLabel.append(
      enabled,
      document.createTextNode(" Enable /docs access"),
    );
    const mode = el("select");
    mode.setAttribute("aria-label", "Publishing mode");
    for (const [v, text] of [
      ["immediate", "Immediately while enabled"],
      ["window", "Scheduled time window"],
      ["duration", "Duration from settings save"],
    ]) {
      const option = el("option", "", text);
      option.value = v;
      option.selected = v === data.settings.mode;
      mode.append(option);
    }
    const start = input(
        "Start · Bangladesh time",
        dhaka(data.settings.start),
        () => {},
        "datetime-local",
      ),
      end = input(
        "End · Bangladesh time",
        dhaka(data.settings.end),
        () => {},
        "datetime-local",
      );
    for (const node of [start, end]) node.querySelector("input").step = "1";
    const duration = input(
      "Duration in minutes",
      data.settings.duration_minutes,
      () => {},
      "number",
    );
    duration.querySelector("input").min = "1";
    duration.querySelector("input").max = "525600";
    const aggregates = el("input");
    aggregates.type = "checkbox";
    aggregates.checked = data.settings.public_analytics;
    const aggregatesLabel = el("label");
    aggregatesLabel.append(
      aggregates,
      document.createTextNode(" Publish aggregate record counts"),
    );
    publishing.append(
      enabledLabel,
      el("label", "", "Access mode"),
      mode,
      start,
      end,
      duration,
      aggregatesLabel,
      action(
        "Apply visibility settings",
        async () => {
          const s = {
            enabled: enabled.checked,
            mode: mode.value,
            start: start.querySelector("input").value + "+06:00",
            end: end.querySelector("input").value + "+06:00",
            duration_minutes: Number(duration.querySelector("input").value),
            public_analytics: aggregates.checked,
          };
          const r = await auth(
            "/api/docs/admin/settings",
            json("PUT", { base_revision: data.revision, settings: s }),
          );
          data.revision = r.revision;
          data.settings = s;
          data.visible = r.visible;
          notice(
            r.visible
              ? "Public access is enabled now."
              : "Public access is OFF or outside its scheduled window.",
          );
        },
        "primary",
      ),
      el(
        "p",
        "muted",
        "Dates use Asia/Dhaka (+06:00). The default June window is 10–14 June 2027. Duration begins when settings are applied. OFF always overrides the schedule.",
      ),
    );
    const tools = el("section", "panel");
    tools.append(
      el("h2", "", "Review and versions"),
      button("Preview draft", () => {
        const modal = el("dialog", "dialog"),
          close = button("Close preview", () => modal.close()),
          content = el("div", "preview-wrap");
        renderSections(content, data);
        modal.append(close, el("h2", "", data.document.title), content);
        modal.addEventListener("close", () => modal.remove());
        document.body.append(modal);
        modal.showModal();
      }),
      action("Load version history", async () => {
        const list = await auth("/api/docs/admin/versions");
        const box = document.querySelector("#version-list");
        box.replaceChildren();
        for (const version of list) {
          const row = el("div");
          row.append(
            el("p", "muted", `${version.kind} · ${date(version.created)}`),
            action("Restore as draft", async () => {
              if (
                !confirm(
                  "Replace the draft with this version? Published content stays unchanged.",
                )
              )
                return;
              await auth(
                "/api/docs/admin/versions/" + version.id + "/restore",
                json("POST", { base_revision: data.revision }),
              );
              await reload();
              notice("Version restored to draft. Review before publishing.");
            }),
          );
          box.append(row);
        }
      }),
      action("Reload from server", async () => {
        if (dirty && !confirm("Discard unsaved edits?")) return;
        await reload();
      }),
    );
    const history = el("div");
    history.id = "version-list";
    const publicLink = el("a", "button", "Open published /docs");
    publicLink.href = "/docs";
    publicLink.target = "_blank";
    publicLink.rel = "noopener";
    tools.append(publicLink, history);
    const live = el("section", "panel");
    const liveTable = el("div");
    liveTable.id = "private-metrics";
    liveTable.append(
      table(["Metric", "Count"], Object.entries(data.live.metrics || {})),
    );
    live.append(
      el("h2", "", "Private live metrics"),
      liveTable,
      action("Refresh metrics", refreshMetrics),
      el(
        "p",
        "muted",
        "These counts are private unless aggregate publishing is enabled. They are not proof of clinical outcomes or active-user traction.",
      ),
    );
    right.append(publishing, tools, live);
    grid.append(left, right);
    root.append(note, status, grid);
    app.append(header, root);
    renderEditors();
    renderMembers();
  }
  async function refreshMetrics() {
    if (!token || !document.querySelector("#private-metrics")) return;
    const latest = await auth("/api/docs/admin");
    data.live = latest.live;
    document
      .querySelector("#private-metrics")
      .replaceChildren(
        table(["Metric", "Count"], Object.entries(data.live.metrics || {})),
      );
  }
  setInterval(() => refreshMetrics().catch(() => {}), 15000);
  window.addEventListener("beforeunload", (e) => {
    if (dirty) {
      e.preventDefault();
      e.returnValue = "";
    }
  });
  if (token) reload().catch(() => logout());
  else login();
})();
