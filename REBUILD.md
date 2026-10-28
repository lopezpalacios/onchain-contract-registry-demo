# Rebuild the platform

This is a static platform. The browser needs only HTML, CSS, and JavaScript.

SQLite is the source of truth at build time. The browser reads `web/data.js`, which is generated from the SQLite database. The browser stores demo changes in localStorage.

---

## 1. Build the SQLite source

The gist contains `registry.sql`. It combines the schema, views, and seed data.

```bash
mkdir -p data
sqlite3 data/registry.db < registry.sql
```

Check the database:

```bash
sqlite3 data/registry.db "PRAGMA integrity_check;"
```

You must get `ok`.

---

## 2. Get the source files

Use one of these methods:

- Clone the repository:
  ```bash
  git clone https://github.com/lopezpalacios/onchain-contract-registry-demo.git
  cd onchain-contract-registry-demo
  ```
- Or use `STACK.md` in the gist. It contains the source files and their paths.
- Or copy the `web/` directory from the repository.

---

## 3. Generate the static data bundle

The repository includes `scripts/export_static.py`. The script reads the SQLite database and writes `web/data.js`.

```bash
python3 scripts/export_static.py
```

The script needs Python only at build time. The browser does not need Python.

If you use the prebuilt `web/data.js`, skip this step.

---

## 4. Open the platform

Open this file in a browser:

```text
web/index.html
```

You can also serve the `web` directory with any static file server:

```bash
python3 -m http.server 8765 --directory web
```

Then open:

```text
http://127.0.0.1:8765/
```

The platform has no API calls. It does not need a backend.

---

## 5. Reset the demo

The browser stores changes in localStorage.

To reset the demo, open the browser console and run:

```javascript
localStorage.removeItem("onchain-registry-static-v1");
localStorage.removeItem("onchain-tour-seen");
location.reload();
```

---

## 6. File map

| File | Purpose |
|---|---|
| `web/index.html` | The platform shell. |
| `web/style.css` | The design system. |
| `web/app.js` | Views, forms, approvals, modals, tour and the animated Flow view. |
| `web/static-api.js` | Browser-only data API. Uses localStorage for writes. |
| `web/data.js` | Generated SQLite snapshot. Do not edit by hand. |
| `registry.sql` | SQLite schema, views, and seed data. |
| `web/tour` content | In `app.js`; the Platform tour button starts it. |
| `docs/platform-guide.md` | Why, what, and how. Uses ASD-STE100. |
| `docs/firefly-kaleido-integration.md` | Deployment hand-off logic. |

---

## 7. Rebuild rules

Use these rules when you change the platform:

1. Keep the runtime static. Do not add a server call.
2. Keep SQLite as the build-time source.
3. Regenerate `data.js` after a database change.
4. Keep the tutorial cutout on four shade panels, not a large box-shadow. Large shadows show artefacts at browser zoom.
5. Use short sentences. Use active voice.
6. Use one term for one idea.
7. Do not use bank names.
8. Do not add real customer data, personal data, keys, or secrets.
9. Keep the FireFly and Kaleido boundary. The platform does not sign transactions.
10. Keep the pre-chain and on-chain states separate.
11. Show evidence gaps. Do not hide them.

---

## 8. Rebuild prompt

Use this prompt with a coding agent:

> Rebuild a static smart contract registry. Use SQLite at build time. Generate `data.js` from the database. Use only HTML, CSS, and JavaScript at runtime. Keep templates, deployment requests, approvals, evidence, on-chain instances, and discovery separate. Link a deployment request to an on-chain instance by request ID, address, transaction, block, and runtime code hash. Add a four-step onboarding wizard. Add a platform tour with arrows. Use ASD-STE100 for all UI text. Do not name a specific bank. Do not add a backend. Test with a static file server and with `file://`.
