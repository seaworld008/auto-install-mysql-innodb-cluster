# ADR-001: Documentation Site and Blocking Lint

## Status

Accepted, amended for blocking lint

## Date

2026-07-03; amended 2026-08-28

## Context

The repository is Chinese-first and has a converged operational mainline for
MySQL InnoDB Cluster automation. Documentation must support global discovery,
staging validation, failure drills, restore drills, and contributor quality
without creating a second deployment flow or runtime configuration source.

The initial decision introduced Markdown and YAML lint as advisory because the
existing documentation had not yet been cleaned under a strict policy. That
migration has now been completed, so leaving lint advisory would allow future
documentation and YAML drift to merge without a quality gate.

## Decision

Keep the lightweight GitHub Pages site sourced from `docs/` and the standalone
`README_EN.md` entrypoint.

Keep reusable evidence templates under `docs/templates/` for:

- staging validation
- failover drills
- isolated restore drills

Run Markdown and YAML lint as a blocking GitHub Actions job:

- pin `markdownlint-cli2` to the repository-selected version
- constrain `yamllint` to an explicit supported range
- fail the job when either linter fails
- pin workflow Actions to full commit SHAs

Lint is a required repository-quality signal, but it is not deployment,
failover, backup, restore, or production-readiness evidence.

## Alternatives Considered

### Build a full documentation framework

- Pros: richer navigation, versioning, search, and themes
- Cons: additional dependencies and maintenance weight
- Rejected: the current GitHub Pages Jekyll site is sufficient for this
  repository

### Keep lint advisory

- Pros: no merge friction from documentation style failures
- Cons: allows known formatting and YAML quality regressions to merge
- Rejected: the migration period is complete and current files pass the chosen
  rules

### Combine lint with the Ansible runtime job

- Pros: fewer visible workflow jobs
- Cons: obscures whether a failure is documentation quality or Ansible
  correctness
- Rejected: separate blocking jobs give clearer diagnosis and ownership

### Keep only the root README

- Pros: lowest maintenance
- Cons: poor discoverability for runbooks, templates, evidence records, and
  global users
- Rejected: the project needs a navigable documentation map

## Consequences

- `README.md` remains the primary Chinese entrypoint.
- `README_EN.md` supports global discovery.
- `docs/index.md` remains the GitHub Pages landing page.
- Markdown or YAML lint failures block the quality workflow.
- Lint configuration and tool versions must be reviewed as dependencies.
- Passing lint cannot be used to claim Ansible correctness or real environment
  validation.
- Runtime configuration remains `inventory/group_vars/all.yml`; no new runtime
  config copies are introduced.
