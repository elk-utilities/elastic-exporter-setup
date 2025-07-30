# syntax=docker/dockerfile:1
FROM ubuntu:latest

# Define architecture
ARG TARGETARCH
ENV ARCH=$TARGETARCH

RUN apt-get update && apt-get install -y supervisor wget curl jq dnsutils

# Elasticsearch Exporter
ENV ES_EXPORTER_VERSION=1.9.0
RUN wget https://github.com/prometheus-community/elasticsearch_exporter/releases/download/v${ES_EXPORTER_VERSION}/elasticsearch_exporter-${ES_EXPORTER_VERSION}.linux-${ARCH}.tar.gz && \
    tar -xzf elasticsearch_exporter-${ES_EXPORTER_VERSION}.linux-${ARCH}.tar.gz && \
    mv elasticsearch_exporter-*/elasticsearch_exporter /bin

# PushProx
ENV PUSHPROX_VERSION=0.2.0
RUN wget https://github.com/prometheus-community/PushProx/releases/download/v${PUSHPROX_VERSION}/PushProx-${PUSHPROX_VERSION}.linux-${ARCH}.tar.gz && \
    tar -xzf PushProx-${PUSHPROX_VERSION}.linux-${ARCH}.tar.gz && \
    mv PushProx-${PUSHPROX_VERSION}.linux-${ARCH}/pushprox-client /bin

COPY supervisord.conf /etc/supervisor/conf.d/
COPY run_exporter.sh /bin/
RUN chmod +x /bin/run_exporter.sh

EXPOSE 8080
CMD ["/bin/run_exporter.sh"]
