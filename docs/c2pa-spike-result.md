# Archived Note

This document is retained only as historical archive context.

The active Zoe iOS implementation does **not** use a C2PA-based end-to-end proof path.

The current app signs canonical `zoe.media.v1` payloads locally and uploads detached proof bundles to the Zoe server.
