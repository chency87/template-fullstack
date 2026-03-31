# `template-fullstack`

A Copier template for bootstrapping two kinds of projects with a consistent developer experience:

- `fullstack`: a Python project starter with docs, tests, devcontainer support, optional Node.js tooling, and optional GPU runtime support
- `agents`: a ZeroClaw-oriented agent deployment workspace with docs, devcontainer support, and optional GPU runtime support

The goal of this repo is to make it easy to generate a clean, ready-to-work-in repository with sensible defaults for local development, documentation, and CI.

## Objective

This template is designed to:

- standardize new project setup across multiple project shapes
- provide a reproducible VS Code devcontainer workflow
- keep generated repos update-friendly through Copier answers tracking
- support both CPU and GPU development environments
- optionally add Node.js and pnpm tooling to the fullstack stack without forcing a frontend scaffold

## What It Generates

### Fullstack

Generates a Python package layout with:

- `src/<package_name>/`
- `tests/`
- `docs/`
- `pyproject.toml`
- `.devcontainer/`
- optional GitHub Actions CI
- optional Node.js, `nvm`, and `pnpm` inside the devcontainer

### Agents

Generates a ZeroClaw-oriented workspace with:

- `workspace/`
- `.config/agents.toml`
- `.config/mkdocs.yml`
- `docs/`
- `.devcontainer/`
- optional GitHub Actions CI

## Project Structure

Top-level files and directories in this template repo:

- [`copier.yml`](/home/chunyu/workspace/template-fullstack/copier.yml): template questions, defaults, and derived values
- [`template/`](/home/chunyu/workspace/template-fullstack/template): the actual project skeleton rendered by Copier
- [`test.sh`](/home/chunyu/workspace/template-fullstack/test.sh): smoke test matrix for generated outputs
- [`.github/workflows/template-ci.yml`](/home/chunyu/workspace/template-fullstack/.github/workflows/template-ci.yml): CI for validating the template itself
- [`.github/workflows/release-template.yml`](/home/chunyu/workspace/template-fullstack/.github/workflows/release-template.yml): manual release workflow for tagging the template
- [`RELEASING.md`](/home/chunyu/workspace/template-fullstack/RELEASING.md): release instructions

Inside [`template/`](/home/chunyu/workspace/template-fullstack/template):

- `.devcontainer/` templates define the development environment
- stack-specific files are conditionally rendered with Jinja
- generated projects include a `.copier-answers.yml` file so `copier update` can track the template source and chosen answers

## How To Use

### Prerequisites

You should have:

- `uv`
- `git`
- Docker, if you want to validate devcontainer-related output locally

### Generate a project

Run:

```sh
copier copy https://github.com/<your-org-or-user>/template-fullstack path/to/output
```

Or generate from the local checkout:

```sh
copier copy . path/to/output
```

Copier will ask for:

- project name and slug
- project description
- stack choice: `fullstack` or `agents`
- CI choice
- Python version
- GPU support
- optional Node.js tooling for `fullstack`

### Open the generated repo

After generation:

1. Open the generated project in VS Code.
2. Run `Dev Containers: Reopen in Container`.
3. Start working inside the prepared environment.

### Update a generated project later

Inside a generated repo:

```sh
copier update
```

This works because the generated project stores its template metadata in `.copier-answers.yml`.

## Local Template Development

### Run the template test matrix

```sh
bash test.sh
```

This script renders multiple combinations, including:

- fullstack CPU
- fullstack CPU + Node.js
- fullstack GPU
- fullstack GPU + Node.js
- agents CPU
- agents GPU
- fullstack without CI

It also validates generated files, checks for unresolved Jinja markers, verifies stack-specific behavior, and runs additional Docker-based checks when Docker is available.

### Keep test output for debugging

```sh
KEEP_TEST_OUTPUT=1 bash test.sh
```

## Release Flow

To publish a stable template ref:

1. Run `bash test.sh`
2. Create an annotated git tag such as `v0.1.0`
3. Push the branch and tag

See [`RELEASING.md`](/home/chunyu/workspace/template-fullstack/RELEASING.md) for the full local and GitHub Actions release flow.

## Notes

- Generated projects may warn about missing git tags if you scaffold from an untagged local checkout.
- The template is intentionally opinionated about devcontainers, docs, and repository layout.
- The `agents` stack keeps a ZeroClaw-specific runtime layout even though the Unix username is normalized to `user` for consistency with the fullstack stack.
