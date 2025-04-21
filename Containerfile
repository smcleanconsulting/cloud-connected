FROM ubuntu:latest

# Set container labels
LABEL maintainer="Cloud Operations Team" \
      description="Container for cloud workflows with AWS and GCP support"

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

# Install necessary packages
RUN apt-get update && apt-get install -y \
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
    && rm -rf /var/lib/apt/lists/*

# Set up locales
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Install Podman using the official Ubuntu repository
# Alternative Podman installation
RUN apt-get update && \
    apt-get install -y podman && \
    rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install Google Cloud SDK
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | \
    tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && \
    apt-get install -y google-cloud-sdk && \
    rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && \
    apt-get install -y terraform && \
    rm -rf /var/lib/apt/lists/*

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