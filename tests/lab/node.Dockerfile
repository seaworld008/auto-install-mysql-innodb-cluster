FROM --platform=linux/amd64 rockylinux:9
ENV container=docker
RUN dnf -y install systemd openssh-server python3 sudo iproute hostname procps-ng which openssl diffutils findutils tar gzip util-linux && dnf clean all \
    && systemctl enable sshd \
    && mkdir -p /root/.ssh /etc/ssh/sshd_config.d \
    && chmod 700 /root/.ssh \
    && printf '%s\n' 'PermitRootLogin prohibit-password' 'PasswordAuthentication no' 'UsePAM no' > /etc/ssh/sshd_config.d/90-lab.conf \
    && truncate -s 0 /etc/machine-id
COPY --chmod=600 authorized_keys /root/.ssh/authorized_keys
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
