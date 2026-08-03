FROM python:3.13-slim

# Official Conan 2 server, pinned for reproducible builds.
ARG CONAN_SERVER_VERSION=2.31.1
RUN pip install --no-cache-dir --root-user-action=ignore "conan-server==${CONAN_SERVER_VERSION}"

COPY entrypoint.py server.conf.template /opt/conan-server/

EXPOSE 9300
ENTRYPOINT ["python", "/opt/conan-server/entrypoint.py"]
