FROM debian:stable-slim

RUN  apt-get update && \
    apt-get -y install nvme-cli mdadm && \
    apt-get -y clean && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

COPY aks-nvme-ssd-provisioner.sh /usr/local/bin/

ENTRYPOINT ["aks-nvme-ssd-provisioner.sh"]