FROM ubuntu:latest

# Set container labels
LABEL maintainer="Cloud Operations Team" \
      description="Container for cloud workflows with AWS and GCP support"

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    git \
    python3 \
    python3-pip \
    vim \
    wget \
    jq \
    netcat-openbsd \
    iputils-ping \
    dnsutils \
    sudo \
    locales \
    less \
    && rm -rf /var/lib/apt/lists/*

# Set up locales
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Update the package index and install necessary packages
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine, CLI, and Docker Compose
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin

# Enable Docker to start on boot (optional)
RUN systemctl enable docker

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install Google Cloud CLI
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y --no-install-recommends terraform \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -m -s /bin/bash cloud-user && \
    echo "cloud-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/cloud-user

# Create directories for AWS and GCP credentials
RUN mkdir -p /home/cloud-user/.aws /home/cloud-user/.config/gcloud && \
    chown -R cloud-user:cloud-user /home/cloud-user

# Create directory for terraform projects
RUN mkdir -p /home/cloud-user/terraform && \
    chown -R cloud-user:cloud-user /home/cloud-user/terraform

# Set working directory
WORKDIR /home/cloud-user

# Switch to cloud-user
USER cloud-user

# Create shell initialization scripts
RUN echo 'export PS1="\[\033[01;32m\]cloud-connected\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /home/cloud-user/.bashrc && \
    echo 'echo "Cloud Connected Container - Ready for AWS and GCP workflows"' >> /home/cloud-user/.bashrc

# Create alias for terraform
RUN echo 'alias tf="terraform"' >> /home/cloud-user/.bashrc
# Create and set the entrypoint script
USER root
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Set default command
CMD ["/bin/bash"]