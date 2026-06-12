# README header options — preview

Three full README variants to compare. Open each on GitHub (or any Markdown
previewer) to see the rendered header. Pick one — or mix-and-match — and I'll set
it as the repo `README.md` on the `docs/readme-security-rebrand` branch.

| Option | File | Header treatment | Best when |
| ------ | ---- | ---------------- | --------- |
| **A** | [option-A-badge-bar.md](option-A-badge-bar.md) | Banner art + `for-the-badge` pill bar + slim stack-badge row | You want a polished, project-page look and the at-a-glance stack |
| **B** | [option-B-typographic.md](option-B-typographic.md) | Banner art + `# th0th` wordmark + monospace `·`-separated tagline | The banner is **art only** (no wordmark baked in) |
| **C** | [option-C-terminal.md](option-C-terminal.md) | ASCII figlet wordmark + `console` intro block (no painterly banner) | You want to lean into the terminal / hacker identity |

All three keep the same body (build-status table, capabilities, **safety & scope**,
getting-started) — they differ only in the header so you can judge the visual.

Notes:
- Links in these files use `../` paths because they live in `_docs/readme-options/`.
  When promoted to the repo-root `README.md`, those become `_docs/...` /
  `.claude/...` again — I'll fix the paths on promotion.
- The banner image is your private `user-attachments` URL: it renders on GitHub
  while you're logged in, but a plain local Markdown viewer may show a broken image
  (that's expected — not a problem with the variant).
