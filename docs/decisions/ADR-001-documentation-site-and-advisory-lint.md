# ADR-001: Documentation Site and Advisory Lint

## Status

Accepted

## Date

2026-07-03

## Context

The repository is Chinese-first and already has a converged operational mainline for MySQL InnoDB Cluster automation. The next documentation improvements need to help global discovery, staging validation, failure drills, restore drills, and contributor quality without creating a second deployment flow or a second runtime configuration source.

The repository also benefits from Markdown and YAML linting, but existing documents were not authored under a strict lint policy. Turning lint on as a hard gate immediately would create avoidable friction.

## Decision

Add a lightweight GitHub Pages documentation site sourced from `docs/`, plus a standalone `README_EN.md` for English discovery.

Add reusable templates under `docs/templates/` for:

- staging validation records
- failover drill records
- isolated restore drill records

Add advisory Markdown and YAML lint workflow configuration. The lint workflow is intentionally optional at this stage and can be promoted to a required gate after the current documentation set is cleaned up under the selected rules.

## Alternatives Considered

### Build a full documentation framework

- Pros: Better navigation, versioning, search, and theming.
- Cons: Adds dependency and maintenance weight that is not justified for the current repository size.
- Rejected: A simple GitHub Pages Jekyll site is enough for the current docs.

### Make lint blocking immediately

- Pros: Stronger consistency from day one.
- Cons: Existing docs may fail on style rules unrelated to deploy correctness.
- Rejected: Advisory lint gives maintainers signal without blocking urgent operational fixes.

### Keep only the root README

- Pros: Lowest maintenance.
- Cons: Poor discoverability for global users and difficult indexing of runbooks, templates, and evidence records.
- Rejected: The project now needs a documentation map and reusable operational templates.

## Consequences

- `README.md` remains the primary Chinese entrypoint.
- `README_EN.md` improves search and evaluation for global users.
- `docs/index.md` becomes the GitHub Pages landing page.
- Documentation lint starts as advisory and should not be used to claim deploy correctness.
- Runtime configuration remains `inventory/group_vars/all.yml`; no new runtime config copies are introduced.
