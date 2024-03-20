# syntax=docker/dockerfile:1
# Dockerfile for combining multiple services
FROM ubuntu:latest
RUN apt-get update && apt-get install -y supervisor wget curl jq

# Elasticsearch Exporter
RUN wget https://github.com/prometheus-community/elasticsearch_exporter/releases/download/v1.7.0/elasticsearch_exporter-1.7.0.linux-amd64.tar.gz
RUN tar -xzf elasticsearch_exporter-1.7.0.linux-amd64.tar.gz
RUN mv elasticsearch_exporter-*/elasticsearch_exporter /bin

# PushProx
RUN wget https://github.com/prometheus-community/PushProx/releases/download/v0.1.0/PushProx-0.1.0.linux-amd64.tar.gz
RUN tar -xzf PushProx-0.1.0.linux-amd64.tar.gz
RUN mv PushProx-0.1.0.linux-amd64/pushprox-client /bin

# Copy supervisord configuration file
COPY supervisord.conf /etc/supervisor/conf.d/

COPY run_exporter.sh /bin

RUN chmod +x /bin/run_exporter.sh

EXPOSE 8080/tcp

# Start supervisord
CMD ["/bin/run_exporter.sh"]