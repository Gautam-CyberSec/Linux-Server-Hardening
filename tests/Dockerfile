# Integration target: a real Ubuntu with a real sshd, so the generated
# configuration is validated by the daemon that would actually read it rather
# than by a regex that agrees with itself.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        openssh-server \
        ufw \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/hardening
COPY . .

RUN chmod +x harden.sh tests/*.sh

CMD ["bash", "tests/integration.sh"]
