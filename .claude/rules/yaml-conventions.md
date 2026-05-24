## YAML conventions

- 2-space indentation
- Max line length 300 (Kubernetes manifests with long annotations/URLs)
- Multiple documents per file allowed (`---` separator)
- `document-start: disable` (leading `---` optional)
- `comments-indentation: disable` (Flux-generated files have inconsistent comment indentation)
