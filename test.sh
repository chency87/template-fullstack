#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
KEEP_TEST_OUTPUT="${KEEP_TEST_OUTPUT:-0}"

cleanup() {
  if [[ "${KEEP_TEST_OUTPUT}" != "1" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

assert_not_contains() {
  local pattern="$1"
  local file="$2"

  if rg -q --fixed-strings "${pattern}" "${file}"; then
    echo "Unexpected content '${pattern}' found in ${file}" >&2
    exit 1
  fi
}

run_case() {
  local name="$1"
  local stack_choice="$2"
  local with_gpu="$3"
  local with_node="${4:-false}"
  local ci="${5:-github}"

  local target_dir="${TMP_DIR}/${name}"
  local out_dir="${target_dir}/my-project"

  echo "==> Rendering ${name}"
  uvx copier copy "${ROOT_DIR}" "${target_dir}" --defaults --overwrite \
    --data project_name="My Project" \
    --data project_slug="my-project" \
    --data project_description="A generated project for ${name}." \
    --data stack_choice="${stack_choice}" \
    --data ci="${ci}" \
    --data python_version="3.12" \
    --data with_gpu="${with_gpu}" \
    --data pytorch_cuda_tag="2.4.1-cuda12.1-cudnn9-runtime" \
    --data with_node="${with_node}" \
    --data node_version="24" \
    --data nvm_version="0.40.3" \
    --data pnpm_version="latest"

  test -f "${out_dir}/README.md"
  test -f "${out_dir}/.devcontainer/devcontainer.json"
  test -f "${out_dir}/.devcontainer/Dockerfile"
  test -f "${out_dir}/.devcontainer/docker-compose.yml"
  test -f "${out_dir}/.copier-answers.yml"
  test -f "${out_dir}/docs/index.md"
  grep -q '`ci`: `' "${out_dir}/README.md"
  grep -q "_src_path: \"${ROOT_DIR}\"" "${out_dir}/.copier-answers.yml"
  grep -q 'python_version: "3.12"' "${out_dir}/.copier-answers.yml"

  if rg -n '\{\{|\{%|\{#' "${out_dir}"; then
    echo "Unresolved template markers found in ${name}" >&2
    exit 1
  fi

  if [[ "${stack_choice}" == "fullstack" ]]; then
    test -f "${out_dir}/mkdocs.yml"
    test -f "${out_dir}/pyproject.toml"
    test -f "${out_dir}/src/my_project/__init__.py"
    test -f "${out_dir}/src/my_project/__main__.py"
    test -f "${out_dir}/tests/test_smoke.py"
    grep -q "\"workspaceFolder\": \"/workspaces/my-project\"" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q "\"remoteUser\": \"user\"" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q "\"updateRemoteUserUID\": false" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q 'working_dir: /workspaces/my-project' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q '\- \.\.:/workspaces/my-project:cached' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'HOME=/home/user' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'UV_CACHE_DIR=/home/user/.cache/uv' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'build-backend = "uv_build"' "${out_dir}/pyproject.toml"
    grep -q 'requires = \["uv_build>=0.7.19,<0.8.0"\]' "${out_dir}/pyproject.toml"
    grep -q '"mkdocs>=1.6.0"' "${out_dir}/pyproject.toml"
    grep -q 'theme:' "${out_dir}/mkdocs.yml"
    grep -q 'starship' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'Run `uv sync`.' "${out_dir}/docs/index.md"
    grep -q 'Run `uv run mkdocs serve` to preview the docs.' "${out_dir}/docs/index.md"
    if [[ -d "${out_dir}/.config" || -d "${out_dir}/workspace" ]]; then
      echo "Unexpected agents layout in ${name}" >&2
      exit 1
    fi
  else
    test -f "${out_dir}/.config/mkdocs.yml"
    test -f "${out_dir}/.config/agents.toml"
    test -f "${out_dir}/workspace/README.md"
    grep -q "\"workspaceFolder\": \"/zeroclaw-data\"" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q "\"remoteUser\": \"user\"" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q "\"updateRemoteUserUID\": false" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q 'ZEROCLAW_WORKSPACE' "${out_dir}/.devcontainer/devcontainer.json"
    grep -q 'working_dir: /zeroclaw-data' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q '\- \.\.:/zeroclaw-data:cached' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q '\- dev_history:/zeroclaw-data/.history' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'HOME=/zeroclaw-data' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'UV_CACHE_DIR=/zeroclaw-data/.cache/uv' "${out_dir}/.devcontainer/docker-compose.yml"
    if [[ -f "${out_dir}/pyproject.toml" || -d "${out_dir}/src" || -d "${out_dir}/tests" ]]; then
      echo "Unexpected fullstack package layout in ${name}" >&2
      exit 1
    fi
    grep -q 'docs_dir: ../docs' "${out_dir}/.config/mkdocs.yml"
    grep -q 'Stack: `ZeroClaw workspace`' "${out_dir}/docs/index.md"
    grep -q 'Docs config: `.config/mkdocs.yml`' "${out_dir}/docs/index.md"
    grep -q 'uvx mkdocs serve -f .config/mkdocs.yml' "${out_dir}/docs/index.md"
    grep -q 'ZeroClaw-oriented deployment workspace' "${out_dir}/README.md"
    assert_not_contains 'uv sync' "${out_dir}/docs/index.md"
    assert_not_contains 'package-ecosystem: "uv"' "${out_dir}/.github/dependabot.yml"
  fi

  if [[ "${with_gpu}" == "true" ]]; then
    grep -q 'driver: nvidia' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'capabilities: \[gpu\]' "${out_dir}/.devcontainer/docker-compose.yml"
  else
    if rg -q 'driver: nvidia|capabilities: \[gpu\]' "${out_dir}/.devcontainer/docker-compose.yml"; then
      echo "Unexpected GPU config in ${name}" >&2
      exit 1
    fi
  fi

  if [[ "${stack_choice}" == "fullstack" ]]; then
    if [[ "${with_gpu}" == "true" ]]; then
      grep -q 'FROM pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime' "${out_dir}/.devcontainer/Dockerfile"
    else
      grep -q 'FROM ghcr.io/astral-sh/uv:python3.12-trixie' "${out_dir}/.devcontainer/Dockerfile"
    fi
    grep -q 'USER user' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV HOME=/home/user' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV UV_TOOL_BIN_DIR=/home/user/.local/bin' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV PATH=$VIRTUAL_ENV/bin:$UV_TOOL_BIN_DIR:$PATH' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'RUN printf '\''export PATH="%s:$PATH"\\n'\'' "$VIRTUAL_ENV/bin:$UV_TOOL_BIN_DIR" > /etc/profile.d/devcontainer-path.sh' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'RUN mkdir -p "$HOME/.local/bin" "$HOME/.local/share"' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'RUN uv venv "${VIRTUAL_ENV}"' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'export PATH=$VIRTUAL_ENV/bin:$UV_TOOL_BIN_DIR:$PATH' "${out_dir}/.devcontainer/Dockerfile"

    if [[ "${with_node}" == "true" ]]; then
      grep -q 'ARG NODE_VERSION="24"' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'ARG NVM_VERSION="0.40.3"' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'ARG PNPM_VERSION="latest"' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'ENV NVM_DIR=/home/user/.nvm' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'ENV NVM_SYMLINK_CURRENT=true' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'nvm install "$NODE_VERSION"' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'corepack prepare pnpm@${PNPM_VERSION} --activate' "${out_dir}/.devcontainer/Dockerfile"
      grep -Fq 'if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'export PATH=$VIRTUAL_ENV/bin:$UV_TOOL_BIN_DIR:$NVM_DIR/current/bin:$PATH' "${out_dir}/.devcontainer/Dockerfile"
      assert_not_contains '/etc/profile.d/node.sh' "${out_dir}/.devcontainer/Dockerfile"
      grep -q '`nvm_version`: `0.40.3`' "${out_dir}/README.md"
      grep -q '`pnpm_version`: `latest`' "${out_dir}/README.md"
      grep -q '`package_manager`: `pnpm`' "${out_dir}/README.md"
      grep -q 'nvm_version: "0.40.3"' "${out_dir}/.copier-answers.yml"
      grep -q 'pnpm_version: "latest"' "${out_dir}/.copier-answers.yml"
      grep -q 'This adds Node and pnpm to the environment, but it does not scaffold a frontend app.' "${out_dir}/README.md"
      assert_not_contains '/usr/local/bin/node' "${out_dir}/.devcontainer/Dockerfile"
      assert_not_contains 'PNPM_HOME=/home/user/.local/share/pnpm' "${out_dir}/.devcontainer/docker-compose.yml"
    else
      if rg -q 'ARG NODE_VERSION=' "${out_dir}/.devcontainer/Dockerfile"; then
        echo "Unexpected Node install config in ${name}" >&2
        exit 1
      fi
    fi
  else
    grep -q 'ARG ZEROCLAW_VERSION=latest' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'FROM ghcr.io/zeroclaw-labs/zeroclaw:${ZEROCLAW_VERSION} AS zeroclaw-binary' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'COPY --from=uv-binary /uv /uvx /usr/local/bin/' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'RUN uv venv "${VIRTUAL_ENV}"' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV UV_TOOL_BIN_DIR=/zeroclaw-data/.local/bin' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'sudo' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'starship' "${out_dir}/.devcontainer/Dockerfile"
    grep -q "user ALL=(root) NOPASSWD:ALL" "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'USER user:user' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENTRYPOINT \["zeroclaw"\]' "${out_dir}/.devcontainer/Dockerfile"
  fi

  if [[ "${ci}" == "github" ]]; then
    test -f "${out_dir}/.github/workflows/ci.yml"
    test -f "${out_dir}/.github/dependabot.yml"
    grep -q 'uses: astral-sh/setup-uv@v5' "${out_dir}/.github/workflows/ci.yml"
    if [[ "${stack_choice}" == "fullstack" && "${with_node}" == "true" ]]; then
      grep -q 'uses: actions/setup-node@v4' "${out_dir}/.github/workflows/ci.yml"
      grep -q 'uv run pytest' "${out_dir}/.github/workflows/ci.yml"
      grep -q 'package-ecosystem: "uv"' "${out_dir}/.github/dependabot.yml"
    elif [[ "${stack_choice}" == "fullstack" ]]; then
      grep -q 'uv run pytest' "${out_dir}/.github/workflows/ci.yml"
      grep -q 'package-ecosystem: "uv"' "${out_dir}/.github/dependabot.yml"
    else
      if rg -q 'setup-node' "${out_dir}/.github/workflows/ci.yml"; then
        echo "Unexpected Node CI setup in ${name}" >&2
        exit 1
      fi
      grep -q 'uvx mkdocs build -f .config/mkdocs.yml' "${out_dir}/.github/workflows/ci.yml"
      grep -q 'Build docs site' "${out_dir}/.github/workflows/ci.yml"
    fi
  else
    if [[ -d "${out_dir}/.github" ]]; then
      echo "Unexpected .github directory in ${name}" >&2
      exit 1
    fi
  fi

  if command -v docker >/dev/null 2>&1; then
    docker compose -f "${out_dir}/.devcontainer/docker-compose.yml" config >/dev/null
    if [[ "${stack_choice}" == "fullstack" && "${with_node}" == "true" && "${with_gpu}" == "false" ]]; then
      docker build -f "${out_dir}/.devcontainer/Dockerfile" "${out_dir}" >/dev/null
    fi
  fi

  echo "==> Verifying copier update metadata for ${name}"
  local stored_commit
  stored_commit="$(sed -n 's/^_commit: "\(.*\)"/\1/p' "${out_dir}/.copier-answers.yml")"

  if [[ -n "${stored_commit}" ]] && git -C "${ROOT_DIR}" rev-parse --verify "${stored_commit}^{commit}" >/dev/null 2>&1; then
    (
      cd "${out_dir}"
      uvx copier update --defaults
    ) >/dev/null
  else
    echo "Skipping copier update for ${name}: stored _commit '${stored_commit}' is not resolvable in the local template repo."
  fi
}

run_case "fullstack-cpu" "fullstack" "false" "false"
run_case "fullstack-cpu-node" "fullstack" "false" "true"
run_case "fullstack-gpu" "fullstack" "true" "false"
run_case "fullstack-gpu-node" "fullstack" "true" "true"
run_case "agents-cpu" "agents" "false" "false"
run_case "agents-gpu" "agents" "true" "false"
run_case "fullstack-cpu-no-ci" "fullstack" "false" "false" "none"

if command -v devcontainer >/dev/null 2>&1; then
  echo "==> Deep validation with devcontainer"
  devcontainer up --workspace-folder "${TMP_DIR}/fullstack-cpu/my-project" >/dev/null
  if command -v nvidia-smi >/dev/null 2>&1; then
    devcontainer up --workspace-folder "${TMP_DIR}/agents-gpu/my-project" >/dev/null
  fi
fi

echo "All template smoke tests passed."
