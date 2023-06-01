FROM python:3.9-alpine

# Set environment variables.
ENV TERM=xterm-color
ENV SHELL=/bin/bash

RUN \
        mkdir /mosquitto && \
        mkdir /mosquitto/log && \
        mkdir /mosquitto/conf && \
        apk update && \
        apk upgrade && \
        apk add \
                bash \
                coreutils \
                nano \
                ca-certificates \
                certbot \
                mosquitto \
                mosquitto-clients && \
        rm -f /var/cache/apk/* && \
        pip install --upgrade pip

COPY run.sh /run.sh
COPY certbot.sh /certbot.sh
COPY restart.sh /restart.sh
COPY croncert.sh /etc/periodic/weekly/croncert.sh
RUN \
        chmod +x /run.sh && \
        chmod +x /certbot.sh && \
        chmod +x /restart.sh && \
        chmod +x /etc/periodic/weekly/croncert.sh

EXPOSE 1883
EXPOSE 8883
EXPOSE 80

# This will run any scripts found in /scripts/*.sh
# then start Apache
CMD ["/bin/bash","-c","/run.sh"]
