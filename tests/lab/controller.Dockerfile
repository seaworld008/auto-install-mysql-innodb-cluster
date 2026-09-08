FROM python:3.13-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client bash ca-certificates curl iproute2 \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt collections.yml /opt/lab/
RUN pip install --no-cache-dir -r /opt/lab/requirements.txt PyMySQL \
    && ansible-galaxy collection install --no-cache -r /opt/lab/collections.yml
WORKDIR /workspace
CMD ["sleep", "infinity"]
