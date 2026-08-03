# Both versions are synced by bootstrap.sh from the toolchain pinned in
# github.com/FurkanTuzemen/ConanAutomation (ftdeps/model.py) - the server
# always matches the Conan version the automation uses.
ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}-slim

ARG CONAN_SERVER_VERSION=2.7.1
RUN pip install --no-cache-dir --root-user-action=ignore "conan-server==${CONAN_SERVER_VERSION}"

COPY entrypoint.py server.conf.template /opt/conan-server/

EXPOSE 9300
ENTRYPOINT ["python", "/opt/conan-server/entrypoint.py"]
