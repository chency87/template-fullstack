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
  local use_external_network="${6:-false}"
  local external_network_name="${7:-shared-dev-network}"

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
    --data pnpm_version="latest" \
    --data use_external_network="${use_external_network}" \
    --data external_network_name="${external_network_name}"

  test -f "${out_dir}/README.md"
  test -f "${out_dir}/.devcontainer/devcontainer.json"
  test -f "${out_dir}/.devcontainer/Dockerfile"
  test -f "${out_dir}/.devcontainer/docker-compose.yml"
  test -f "${out_dir}/.copier-answers.yml"
  grep -q '`ci`: `' "${out_dir}/README.md"
  grep -q "_src_path: \"${ROOT_DIR}\"" "${out_dir}/.copier-answers.yml"
  grep -q 'python_version: "3.12"' "${out_dir}/.copier-answers.yml"
  local use_external_network_yaml
  if [[ "${use_external_network}" == "true" ]]; then
    use_external_network_yaml="True"
  else
    use_external_network_yaml="False"
  fi
  grep -q "use_external_network: ${use_external_network_yaml}" "${out_dir}/.copier-answers.yml"
  if [[ "${use_external_network}" == "true" ]]; then
    grep -q "external_network_name: \"${external_network_name}\"" "${out_dir}/.copier-answers.yml"
    grep -q 'external-dev' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'external: true' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q "name: ${external_network_name}" "${out_dir}/.devcontainer/docker-compose.yml"
  else
    assert_not_contains 'external-dev' "${out_dir}/.devcontainer/docker-compose.yml"
    assert_not_contains 'external: true' "${out_dir}/.devcontainer/docker-compose.yml"
  fi

  if rg -n '\{\{|\{%|\{#' "${out_dir}"; then
    echo "Unresolved template markers found in ${name}" >&2
    exit 1
  fi

  if [[ "${stack_choice}" == "fullstack" ]]; then
    test -f "${out_dir}/docs/index.md"
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
    if [[ "${with_gpu}" == "true" ]]; then
      grep -q '"VIRTUAL_ENV": "/opt/conda"' "${out_dir}/.devcontainer/devcontainer.json"
      grep -q '"PATH": "/opt/conda/bin:${containerEnv:PATH}"' "${out_dir}/.devcontainer/devcontainer.json"
      grep -q '"UV_PROJECT_ENVIRONMENT": "/opt/conda"' "${out_dir}/.devcontainer/devcontainer.json"
      grep -q '"python.defaultInterpreterPath": "/opt/conda/bin/python"' "${out_dir}/.devcontainer/devcontainer.json"
    else
      grep -q '"VIRTUAL_ENV": "/opt/venv"' "${out_dir}/.devcontainer/devcontainer.json"
      grep -q '"PATH": "/opt/venv/bin:${containerEnv:PATH}"' "${out_dir}/.devcontainer/devcontainer.json"
      grep -q '"UV_PROJECT_ENVIRONMENT": "/opt/venv"' "${out_dir}/.devcontainer/devcontainer.json"
      grep -q '"python.defaultInterpreterPath": "/opt/venv/bin/python"' "${out_dir}/.devcontainer/devcontainer.json"
    fi
    if [[ -d "${out_dir}/.config" || -d "${out_dir}/workspace" ]]; then
      echo "Unexpected agents layout in ${name}" >&2
      exit 1
    fi
  else
    test -f "${out_dir}/src/README.md"
    test -f "${out_dir}/zeroclaw-data/README.md"
    grep -q "\"workspaceFolder\": \"/workspaces/zeroclaw/src\"" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q "\"remoteUser\": \"user\"" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q "\"updateRemoteUserUID\": false" "${out_dir}/.devcontainer/devcontainer.json"
    grep -q '"/workspaces/zeroclaw/zeroclaw-data"' "${out_dir}/.devcontainer/devcontainer.json"
    grep -q 'working_dir: /workspaces/zeroclaw/src' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q '\- \.\./src:/workspaces/zeroclaw/src:cached' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q '\- \.\./zeroclaw-data:/workspaces/zeroclaw/zeroclaw-data:cached' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q '\- dev_history:/home/user/.history' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'HOME=/home/user' "${out_dir}/.devcontainer/docker-compose.yml"
    grep -q 'UV_CACHE_DIR=/home/user/.cache/uv' "${out_dir}/.devcontainer/docker-compose.yml"
    if [[ -f "${out_dir}/pyproject.toml" || -d "${out_dir}/tests" || -d "${out_dir}/.config" || -d "${out_dir}/docs" || -d "${out_dir}/workspace" ]]; then
      echo "Unexpected fullstack package layout in ${name}" >&2
      exit 1
    fi
    grep -q 'ZeroClaw-oriented developer workspace' "${out_dir}/README.md"
    grep -q 'src/' "${out_dir}/README.md"
    grep -q 'zeroclaw-data/' "${out_dir}/README.md"
    grep -q 'mounted as the active workspace' "${out_dir}/README.md"
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
    grep -q 'export PATH=$VIRTUAL_ENV/bin:$UV_TOOL_BIN_DIR:$PATH' "${out_dir}/.devcontainer/Dockerfile"

    if [[ "${with_gpu}" == "true" ]]; then
      grep -q 'ENV VIRTUAL_ENV=/opt/conda' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'ENV UV_PYTHON=/opt/conda/bin/python' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'chown -R user:user /opt/conda' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'RUN "${VIRTUAL_ENV}/bin/conda" init bash' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'RUN test -x "${UV_PYTHON}"' "${out_dir}/.devcontainer/Dockerfile"
      grep -q "echo 'conda activate base'" "${out_dir}/.devcontainer/Dockerfile"
      grep -q '~/.cache/huggingface:/home/user/.cache/huggingface' "${out_dir}/.devcontainer/docker-compose.yml"
      assert_not_contains 'huggingface_cache' "${out_dir}/.devcontainer/docker-compose.yml"
      assert_not_contains 'RUN uv venv "${VIRTUAL_ENV}"' "${out_dir}/.devcontainer/Dockerfile"
    else
      grep -q 'ENV VIRTUAL_ENV=/opt/venv' "${out_dir}/.devcontainer/Dockerfile"
      grep -q 'RUN uv venv "${VIRTUAL_ENV}"' "${out_dir}/.devcontainer/Dockerfile"
      assert_not_contains 'ENV UV_PYTHON=/opt/conda/bin/python' "${out_dir}/.devcontainer/Dockerfile"
    fi

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
    grep -q 'COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ARG NODE_VERSION="24"' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ARG NVM_VERSION="0.40.3"' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ARG PNPM_VERSION="latest"' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'RUN uv venv "${VIRTUAL_ENV}"' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV HOME=/home/user' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV UV_TOOL_BIN_DIR=/home/user/.local/bin' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV CARGO_HOME=/home/user/.cargo' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV RUSTUP_HOME=/home/user/.rustup' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'ENV NVM_DIR=/home/user/.nvm' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'https://sh.rustup.rs' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'rustup default stable' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'cargo --version' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'corepack prepare pnpm@${PNPM_VERSION} --activate' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'npm install -g agent-browser opencode-ai' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'sudo' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'openssh-client' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'tmux' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'pkg-config' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'libssl-dev' "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'starship' "${out_dir}/.devcontainer/Dockerfile"
    grep -q "user ALL=(root) NOPASSWD:ALL" "${out_dir}/.devcontainer/Dockerfile"
    grep -q 'USER $USERNAME' "${out_dir}/.devcontainer/Dockerfile"
    grep -q '`node_manager`: `nvm`' "${out_dir}/README.md"
    grep -q '`rust_toolchain`: `stable`' "${out_dir}/README.md"
    grep -q '`rust_manager`: `rustup`' "${out_dir}/README.md"
    grep -q '`pnpm_version`: `latest`' "${out_dir}/README.md"
    grep -q 'Node.js tooling is installed and managed with `nvm` inside the devcontainer.' "${out_dir}/README.md"
    grep -q 'Rust tooling is installed and managed with `rustup` inside the devcontainer' "${out_dir}/README.md"
    grep -q 'node_version: "24"' "${out_dir}/.copier-answers.yml"
    assert_not_contains 'zeroclaw-${zeroclaw_target}.tar.gz' "${out_dir}/.devcontainer/Dockerfile"
    assert_not_contains 'ARG ZEROCLAW_VERSION=' "${out_dir}/.devcontainer/Dockerfile"
    assert_not_contains 'FROM ghcr.io/zeroclaw-labs/zeroclaw:${ZEROCLAW_VERSION} AS zeroclaw-binary' "${out_dir}/.devcontainer/Dockerfile"
    assert_not_contains 'ENTRYPOINT ["zeroclaw"]' "${out_dir}/.devcontainer/Dockerfile"
    assert_not_contains 'CMD ["daemon"]' "${out_dir}/.devcontainer/Dockerfile"
    assert_not_contains 'HEALTHCHECK' "${out_dir}/.devcontainer/Dockerfile"
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
      assert_not_contains 'mkdocs' "${out_dir}/.github/workflows/ci.yml"
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
run_case "agents-cpu-external-network" "agents" "false" "false" "github" "true" "shared-dev-network"
run_case "fullstack-cpu-no-ci" "fullstack" "false" "false" "none"

if command -v devcontainer >/dev/null 2>&1; then
  echo "==> Deep validation with devcontainer"
  devcontainer up --workspace-folder "${TMP_DIR}/fullstack-cpu/my-project" >/dev/null
fi

echo "All template smoke tests passed."
