FROM quay.io/strimzi/kafka:0.35.1-kafka-3.4.0
USER root:root
COPY ./newjar/ /opt/kafka/libs/
COPY ./sqljar/ /opt/kafka/plugins/
USER 1001