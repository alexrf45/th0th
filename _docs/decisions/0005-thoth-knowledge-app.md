# ADR-0005: Thoth — unified knowledge app + service-mesh anchor

- **Status:** **Descoped (2026-05-22)** — not building the full app. Scope reduced to utilities/scripts on top of existing infra; effort redirected to iterating and hardening what's already deployed. Original pre-decision design retained below as historical record.
- **Date:** 2026-05-03 (drafted); descoped 2026-05-22
- **Deciders:** fr3d
- **Related:** [ADR-0004](0004-gpu-vfio-passthrough.md) (AI layer wants a GPU); retrospectives for the apps Thoth would replace — [journey.md](../journey.md#retired-apps).

## Update — 2026-05-22: Descoped

Thoth will **not** be built as a full unified knowledge application. The honest pushbacks below held up: 18+ months of part-time work for ~80% of what existing tools already do, a hard GPU dependency for a credible AI layer, and a separate iOS project. Decision (user): **no full app — build small utilities/scripts where useful and keep iterating the existing lab infrastructure** instead. The service-mesh phase is no longer gated on Thoth as its anchor app; if a mesh is adopted it will be justified on its own terms. The design thinking below is preserved for reference, not as a plan of record.

## Context

Three self-hosted apps cover overlapping "personal knowledge" ground: Wallabag (read-it-later), FreshRSS (feeds), Syncthing (notes file-sync). The idea: replace the trio with one cohesive system — a single library for articles, feed items, and notes, with cross-cutting tags, full-text + semantic search, and an AI layer (summarize, auto-tag, similarity, Q&A). iOS native client is a long-term goal.

Thoth is also the **anchor application that justifies the service-mesh decision** (deferred from observability Phase 0) — a multi-service custom app is the strongest case for a mesh, and exercises CNPG, ESO, Cilium Gateway, External DNS, and the observability stack end-to-end.

## Decision (provisional)

No build commitment. Provisional directions captured:

- **Mesh:** **Istio Ambient** when the mesh phase begins (user-preferred for production references; ambient sidesteps per-pod sidecars). Cilium Service Mesh and Linkerd considered and set aside. Adopt at **step 3** of the phased build, after 1–2 bare services exist, so the before/after is felt. Mesh is east-west; Cilium Gateway stays north-south.
- **Architecture:** start as a Go monolith, split into services (`bff`, `auth`, `content`, `search`, `ai`, `sync`, `notify` + NATS workers) only when the mesh enters. A polymorphic `item` row unifies article/note/feed; `body_ref` → MinIO blobs.
- **Languages:** Go everywhere except `ai` (Python, for the ML ecosystem).
- **Sync model:** filesystem-with-arbiter (markdown in MinIO, conflict files) as the starting point; CRDTs only if collaborative editing becomes a real requirement.
- **AI hosting:** hybrid — embedding/tagging always-on, summarization/Q&A on-demand; local (Ollama) for cheap/sensitive, external (Claude/OpenAI) for heavy Q&A with per-query opt-in.

## Honest pushbacks (recorded during design)

- This is **18+ months of part-time work** for what Wallabag + a reader + Obsidian Sync (or Logseq/Anytype) already do ~80% of. Be clear whether the goal is *product value* or *platform-engineering value* — they point at different scopes.
- A serious AI layer pulls in a **GPU node** (see ADR-0004); CPU-only LLM Q&A feels broken.
- The **iOS native app is its own project**, not a bolt-on.
- **Decommissioning means migration** — each source needs a one-shot importer.
- **Don't pre-split into microservices** — a monolith you split later beats a distributed system you debug from day one.

## Consequences / what it would require

Net-new infra beyond what's built: MinIO (blobs), Meilisearch (keyword search), NATS (worker queue), Ollama (LLM), Istio Ambient, optional GPU node. The storage strategy in [ADR-0003](0003-cnpg-local-snapshots.md) intersects Thoth's "DR for MinIO-backed notes" open question — revisit it there.

## Open questions to research before next session

Sync model deep-dive (iOS File Provider ↔ MinIO); article-extraction parser quality (Go vs. wallabag's `graby`); CRDT escape-hatch migration path; GPU node feasibility/cost; Istio Ambient with long-lived gRPC LLM streams; auth (roll-your-own vs. reuse Authentik per [ADR-0001](0001-sso-authentik.md)); Swift gRPC vs REST; external-AI cost ceiling; backup/DR for MinIO-resident notes.

## References

- Full design essay (archived): `archive/source-docs/thoth-knowledge-app-decision.md`
