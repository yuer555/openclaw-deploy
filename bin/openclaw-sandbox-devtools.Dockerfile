ARG OPENCLAW_SANDBOX_BASE_IMAGE=debian:bookworm-slim
FROM ${OPENCLAW_SANDBOX_BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    UV_SYSTEM_PYTHON=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    python3 \
    python3-venv \
    python3-pip \
    git \
    openssh-client \
    tini \
 && ln -sf /usr/bin/python3 /usr/local/bin/python \
 && ln -sf /usr/bin/python3 /usr/local/bin/python3 \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    tmp_script="$(mktemp)"; \
    if curl --http1.1 --retry 5 --retry-delay 2 --retry-all-errors -LsSf \
      https://astral.sh/uv/install.sh -o "$tmp_script" \
      && sh "$tmp_script"; then \
        rm -f "$tmp_script"; \
        test -x /root/.local/bin/uv; \
        ln -sf /root/.local/bin/uv /usr/local/bin/uv; \
    else \
        rm -f "$tmp_script"; \
        echo "uv 官方安装脚本不可用，回退使用 pip3 安装"; \
        pip3 install --no-cache-dir --break-system-packages uv; \
    fi; \
    command -v uv; \
    uv --version

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash", "-lc", "python3 --version && curl --version && git --version && ssh -V && uv --version && sleep infinity"]
