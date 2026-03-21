FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG WEBUI_REF=master

RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3 python3-venv python3-pip ca-certificates \
    libglib2.0-0 libsm6 libxrender1 libxext6 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
WORKDIR /opt/stable-diffusion-webui
RUN git checkout ${WEBUI_REF}

ENV COMMANDLINE_ARGS="--listen --port 7860"

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 7860
ENTRYPOINT ["/start.sh"]
