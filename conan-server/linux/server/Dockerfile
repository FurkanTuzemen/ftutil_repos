# Generic, credential-free image: python + a pinned conan-server. All config
# (users, secrets, public hostname) is rendered at container start by
# entrypoint.py from environment variables.
#
# Both versions come from conan-server/versions.env (via .env and the compose build args).
ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}-slim

ARG CONAN_SERVER_VERSION
# Transitive dependencies are locked per conan-server version
# (constraints/conan-server-<version>.txt, written by linux/lock-deps.sh) so
# a rebuild months later installs the exact same packages.
COPY constraints/ /tmp/constraints/
RUN set -eu; \
    test -n "${CONAN_SERVER_VERSION}" || { echo "CONAN_SERVER_VERSION build arg is required" >&2; exit 1; }; \
    lock="/tmp/constraints/conan-server-${CONAN_SERVER_VERSION}.txt"; \
    if [ -f "$lock" ]; then \
        echo "Installing conan-server ${CONAN_SERVER_VERSION} with locked deps from $(basename "$lock")"; \
        pip install --no-cache-dir --root-user-action=ignore -c "$lock" "conan-server==${CONAN_SERVER_VERSION}"; \
    else \
        echo "WARNING: no lock file for conan-server ${CONAN_SERVER_VERSION} - deps are unpinned; run linux/lock-deps.sh" >&2; \
        pip install --no-cache-dir --root-user-action=ignore "conan-server==${CONAN_SERVER_VERSION}"; \
    fi; \
    rm -rf /tmp/constraints

COPY entrypoint.py server.conf.template /opt/conan-server/

EXPOSE 9300
ENTRYPOINT ["python", "/opt/conan-server/entrypoint.py"]
