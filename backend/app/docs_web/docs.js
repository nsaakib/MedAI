"use strict";
window.Docs = (() => {
  const el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  };
  const button = (text, action, cls = "") => {
    const n = el("button", cls, text);
    n.type = "button";
    n.addEventListener("click", action);
    return n;
  };
  const date = (t) =>
    new Date(t * 1000).toLocaleString(undefined, { timeZoneName: "short" });
  async function api(path, options = {}) {
    const r = await fetch(path, { cache: "no-store", ...options });
    const type = r.headers.get("content-type") || "";
    const data = type.includes("json") ? await r.json() : await r.text();
    if (!r.ok) {
      const detail = data.detail;
      throw Object.assign(
        new Error(
          typeof detail === "string"
            ? detail
            : r.status === 422
              ? "Check required fields, unique sections, email addresses and date offsets."
              : `Request failed (${r.status})`,
        ),
        { status: r.status },
      );
    }
    return data;
  }
  function badge(text) {
    return el(
      "span",
      "badge" +
        (/planned|sandbox|disabled|required|not configured/i.test(text)
          ? " warn"
          : ""),
      text,
    );
  }
  function table(headers, rows) {
    const wrap = el("div", "table-wrap");
    const t = el("table");
    const head = el("thead"),
      tr = el("tr");
    for (const h of headers) tr.append(el("th", "", h));
    head.append(tr);
    const body = el("tbody");
    for (const row of rows) {
      const tr = el("tr");
      for (const value of row) {
        const td = el("td");
        td.append(
          value instanceof Node
            ? value
            : document.createTextNode(String(value ?? "Not configured")),
        );
        tr.append(td);
      }
      body.append(tr);
    }
    t.append(head, body);
    wrap.append(t);
    return wrap;
  }
  function diagram(data, title) {
    const ns = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(ns, "svg"),
      count = data.nodes.length;
    svg.setAttribute("viewBox", `0 0 760 ${count * 104 + 16}`);
    svg.setAttribute("class", "diagram");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", title);
    const def = document.createElementNS(ns, "defs"),
      marker = document.createElementNS(ns, "marker");
    const id = "arrow-" + Math.random().toString(36).slice(2);
    marker.setAttribute("id", id);
    marker.setAttribute("viewBox", "0 0 10 10");
    marker.setAttribute("refX", "8");
    marker.setAttribute("refY", "5");
    marker.setAttribute("markerWidth", "7");
    marker.setAttribute("markerHeight", "7");
    marker.setAttribute("orient", "auto-start-reverse");
    const arrow = document.createElementNS(ns, "path");
    arrow.setAttribute("d", "M 0 0 L 10 5 L 0 10 z");
    arrow.setAttribute("fill", "#5086dc");
    marker.append(arrow);
    def.append(marker);
    svg.append(def);
    for (const [a, b] of data.edges) {
      const path = document.createElementNS(ns, "path");
      const side = a + 1 === b ? 380 : 700;
      path.setAttribute(
        "d",
        a + 1 === b
          ? `M 380 ${a * 104 + 82} L 380 ${b * 104 + 16}`
          : `M 650 ${a * 104 + 49} H ${side} V ${b * 104 + 49} H 650`,
      );
      path.setAttribute("marker-end", `url(#${id})`);
      svg.append(path);
    }
    data.nodes.forEach((label, i) => {
      const rect = document.createElementNS(ns, "rect");
      for (const [k, v] of Object.entries({
        x: 80,
        y: i * 104 + 16,
        width: 600,
        height: 66,
        rx: 15,
      }))
        rect.setAttribute(k, v);
      const text = document.createElementNS(ns, "text");
      text.setAttribute("x", "380");
      text.setAttribute("y", i * 104 + 54);
      text.setAttribute("text-anchor", "middle");
      text.textContent = label;
      svg.append(rect, text);
    });
    return svg;
  }
  function team(doc) {
    const grid = el("div", "team-grid");
    if (!doc.members.length)
      return el("p", "notice", "Team profiles have not been published yet.");
    for (const m of doc.members) {
      const card = el("article", "team-card");
      let avatar;
      if (m.avatar) {
        avatar = el("img", "avatar");
        avatar.src = "/docs/team/" + m.avatar;
        avatar.alt = m.name;
        avatar.loading = "lazy";
        avatar.width = 96;
        avatar.height = 96;
        avatar.addEventListener(
          "error",
          () => {
            avatar.replaceWith(
              el(
                "div",
                "avatar",
                m.name
                  .split(" ")
                  .map((n) => n[0])
                  .slice(0, 2)
                  .join(""),
              ),
            );
          },
          { once: true },
        );
      } else
        avatar = el(
          "div",
          "avatar",
          m.name
            .split(" ")
            .map((n) => n[0])
            .slice(0, 2)
            .join(""),
        );
      const email = el("a", "", m.email);
      email.href = "mailto:" + m.email;
      card.append(
        avatar,
        el("h3", "", m.name),
        el("p", "muted", m.role),
        email,
      );
      grid.append(card);
    }
    return grid;
  }
  function metrics(live) {
    const box = el("div");
    const cards = el("div", "cards");
    const values = {
      "Product API operations": live.system.api_endpoints,
      "Dispatch mode": live.system.dispatch_mode,
      "AI configuration": live.system.ai_configured
        ? "Configured"
        : "Not configured",
    };
    for (const [label, value] of Object.entries(values)) {
      const card = el("div", "metric");
      card.append(el("strong", "", String(value)), el("span", "", label));
      cards.append(card);
    }
    box.append(cards);
    if (live.metrics) {
      box.append(
        table(["Record count", "Value"], Object.entries(live.metrics)),
      );
      box.append(
        el(
          "p",
          "muted",
          "Counts are database records, not validated active users, outcomes or confirmed ambulance availability. Sandbox counts include test data.",
        ),
      );
    } else
      box.append(
        el("p", "notice", "Private record-count analytics are not published."),
      );
    box.append(
      el(
        "small",
        "",
        `Server sample: ${date(live.system.sampled_at)} · ${live.system.docs_revision}`,
      ),
    );
    return box;
  }
  function sectionView(section, doc, live, index) {
    const node = el("section", "section");
    node.id = section.id;
    node.dataset.title = section.title.toLowerCase();
    node.append(
      el(
        "div",
        "number",
        `${section.group} / ${String(index + 1).padStart(2, "0")}`,
      ),
    );
    const heading = el("h2"),
      anchor = el("a", "", section.title);
    anchor.href = "#" + section.id;
    heading.append(anchor);
    node.append(heading);
    const body = el("div", "rich");
    body.innerHTML = section.body;
    node.append(body);
    if (section.id === "demo" && doc.demo_url) {
      const link = el("a", "button primary", "Watch the product demo");
      link.href = doc.demo_url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      node.append(link);
    }
    switch (section.source) {
      case "features":
        node.append(
          table(
            ["Capability", "State", "Evidence / limitation"],
            live.features.map((f) => [f.name, badge(f.status), f.basis]),
          ),
        );
        break;
      case "apis":
        node.append(
          table(
            ["Method", "Endpoint", "Access", "Contract"],
            live.apis.map((a) => {
              const details = el("details");
              details.append(
                el("summary", "", "Parameters & schema"),
                el(
                  "pre",
                  "",
                  JSON.stringify(
                    {
                      parameters: a.parameters,
                      request: a.request_schema,
                      responses: a.responses,
                    },
                    null,
                    2,
                  ),
                ),
              );
              return [
                badge(a.method),
                el("code", "", a.path),
                a.access,
                details,
              ];
            }),
          ),
        );
        break;
      case "stack":
        node.append(
          table(
            ["Layer", "Technology / configuration"],
            Object.entries(live.stack),
          ),
        );
        break;
      case "analytics":
        node.append(metrics(live));
        break;
      case "team":
        node.append(team(doc));
        break;
      case "architecture":
      case "data-flow":
        if (section.diagram)
          node.append(diagram(section.diagram, section.title));
        break;
    }
    return node;
  }
  function renderSections(target, data) {
    target.replaceChildren(
      ...data.document.sections.map((s, i) =>
        sectionView(s, data.document, data.live, i),
      ),
    );
  }
  function shell(data) {
    const app = document.querySelector("#app");
    app.replaceChildren();
    const header = el("header", "topbar"),
      brand = el("a", "brand");
    brand.href = "/docs";
    brand.append(
      document.createTextNode("Med"),
      el("b", "", ".ai"),
      el("small", "", "Product dossier"),
    );
    const actions = el("div", "top-actions");
    const exportLink = el("a", "button", "Markdown");
    exportLink.href = "/api/docs/export";
    actions.append(
      button("Save PDF", () => window.print()),
      exportLink,
      button("Copy link", async () => {
        try {
          await navigator.clipboard.writeText(location.origin + "/docs");
        } catch {
          window.prompt("Copy documentation link", location.origin + "/docs");
        }
      }),
    );
    header.append(brand, actions);
    const layout = el("div", "layout"),
      aside = el("aside", "sidebar"),
      nav = el("nav"),
      search = el("input");
    search.type = "search";
    search.placeholder = "Search documentation";
    search.setAttribute("aria-label", "Search documentation");
    aside.append(
      button(
        "Browse sections",
        () => aside.classList.toggle("open"),
        "mobile-nav",
      ),
      search,
      nav,
    );
    let group = "";
    for (const s of data.document.sections) {
      if (s.group !== group) {
        group = s.group;
        nav.append(el("div", "nav-group", group));
      }
      const a = el("a", "", s.title);
      a.href = "#" + s.id;
      nav.append(a);
    }
    const main = el("main"),
      hero = el("div", "hero");
    hero.append(
      el("div", "eyebrow", "Bangladesh · Connected care"),
      el("h1", "", data.document.title),
      el("p", "", data.document.tagline),
    );
    const cta = el("div", "top-actions"),
      overview = el("a", "button", "Explore the product"),
      architecture = el("a", "button", "Inspect the architecture");
    overview.href = "#overview";
    architecture.href = "#architecture";
    cta.append(overview, architecture);
    hero.append(
      cta,
      el(
        "p",
        "live-status",
        `Live server snapshot · ${data.live.system.dispatch_mode} dispatch · no clinical outcome claim`,
      ),
    );
    const status = el(
        "div",
        "statusbar",
        `Content revision ${data.revision} · sampled ${date(data.live.system.sampled_at)} · refreshes every 5 seconds`,
      ),
      sections = el("div");
    renderSections(sections, data);
    main.append(
      hero,
      status,
      sections,
      el(
        "footer",
        "footer",
        "Med.ai supports understanding and care coordination. It does not replace professional medical assessment. Access depends on this server’s publishing settings and network reachability.",
      ),
    );
    layout.append(aside, main);
    app.append(header, layout);
    function filter() {
      const q = search.value.trim().toLowerCase();
      for (const s of sections.children)
        s.hidden = q && !s.textContent.toLowerCase().includes(q);
    }
    search.addEventListener("input", filter);
    return { sections, status, filter, hero };
  }
  async function publicPage() {
    let current = null,
      view = null,
      busy = false,
      previous = null;
    async function refresh() {
      if (busy) return;
      busy = true;
      try {
        const data = await api("/api/docs/public");
        if (!view || data.revision !== current) {
          view = shell(data);
          current = data.revision;
        } else {
          for (const [i, section] of data.document.sections.entries()) {
            const field = {
              features: "features",
              apis: "apis",
              stack: "stack",
              analytics: "system",
            }[section.source];
            if (
              field &&
              (section.source === "analytics" ||
                JSON.stringify(data.live[field]) !==
                  JSON.stringify(previous?.[field]))
            ) {
              const old = document.getElementById(section.id);
              if (old)
                old.replaceWith(
                  sectionView(section, data.document, data.live, i),
                );
            }
          }
          view.filter();
          view.status.textContent = `Content revision ${data.revision} · sampled ${date(data.live.system.sampled_at)} · refreshes every 5 seconds`;
        }
        previous = data.live;
      } catch (e) {
        if (e.status === 403 || !view) {
          document
            .querySelector("#app")
            .replaceChildren(
              el(
                "div",
                "unavailable",
                e.status === 403
                  ? "Documentation is not available in the current publishing window."
                  : "Could not load documentation. Check the server connection.",
              ),
            );
          view = null;
          current = null;
        } else
          view.status.textContent =
            "Connection lost. Displayed data is stale; reconnecting…";
      } finally {
        busy = false;
      }
    }
    await refresh();
    setInterval(refresh, 5000);
  }
  return { el, button, api, table, date, renderSections, publicPage };
})();
if (!location.pathname.startsWith("/docs/admin")) window.Docs.publicPage();
