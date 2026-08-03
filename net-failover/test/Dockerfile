# Reproducible environment for the net-failover test suite.
#
# This image is for VERIFYING the daemon, not for running it: net-failover
# drives the host's NetworkManager and real radios, so it is installed on the
# host by linux/bootstrap.sh (see the repo's platform strategy in README.md).
# Here the daemon runs against mock nmcli/curl/ping/ip binaries instead.
#
#   docker build -f test/Dockerfile -t net-failover-test .
#   docker run --rm net-failover-test
FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash coreutils sed gawk grep shellcheck \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /project
COPY linux/ /project/linux/
COPY test/  /project/test/

RUN chmod +x /project/linux/net-failover /project/linux/*.sh \
             /project/test/run-tests.sh /project/test/bin/*

ENTRYPOINT ["/project/test/run-tests.sh"]
