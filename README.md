# Kafka  Deplo uisng Strimzi operator in multiple namespaces

Kafka , debezium connet and releted serices will deploy in below namespaces

- Dev env namespace - kafka-dev

- QA env  namespace - kafka-qa



**Namespace creation and strimzi operator deploying using Helm**

```
kubectl create namespace kafka-dev
kubectl create namespace kafka-qa
kubectl create namespace strimzi

```
- Strimzi Operator

```
helm repo add strimzi https://strimzi.io/charts/
helm repo update
```

**Deploy strimzi-operator (it will watch dev and qa namespaces)**

```
helm install strimzi-operator  strimzi/strimzi-kafka-operator --namespace strimzi --set watchNamespaces="{kafka-dev,kafka-qa}" -f values.yaml
```

Deploy Kafka and releted apps in kafka-dev namespace

```
kubectl create -f kafka-zookeeper.yml -n kafka-dev

kubectl create -f schema-registry-deployment.yml  -n kafka-dev

kubectl create -f schema-registry-service.yml -n kafka-dev

kubectl create -f  kafdrop-deployment.yml -n kafka-dev

kubectl create -f  kafdrop-service.yml -n kafka-dev

```



**Build Docker image for kafka debezium connect**

- In this setup used Azure MS Sql database . So used debezium-connector-sqlserver plugin

- First , Download jar files  and save

Eg:- 

```
ls newjar

avro-1.10.1.jar          common-utils-6.2.0.jar        kafka-avro-serializer-6.2.0.jar         kafka-connect-avro-data-6.2.0.jar       kafka-schema-serializer-6.2.0.jar
common-config-6.2.0.jar  debezium-connector-sqlserver  kafka-connect-avro-converter-6.2.0.jar  kafka-schema-registry-client-6.2.0.jar

ls sqljar/

debezium-connector-sqlserver

```

- Create Docker file and build. Then push to private or public repository according to your requirement. 

```
Docker file

FROM quay.io/strimzi/kafka:0.35.1-kafka-3.4.0
USER root:root
COPY ./newjar/ /opt/kafka/libs/
COPY ./sqljar/ /opt/kafka/plugins/
USER 1001
```

**Build and push strimzi Kafkaconenct image with needed libraries and plugins**

- Here pushed image to Azure container registry

```
docker build -t strimzi-kafka-connect-av:0.35.1-kafka-3.4.0 .


docker tag strimzi-kafka-connect-av:0.35.1-kafka-3.4.0 xxxxxxxxxxxxxx.azurecr.io/debezium/strimzi/strimzi-kafka-connect-av:0.35.1-kafka-3.4.0


az acr login --name xxxxxxxxxregistry


docker push xxxxxxxxxxxxxxxxxxxxxx.azurecr.io/debezium/strimzi/strimzi-kafka-connect-av:0.35.1-kafka-3.4.0

```


**deploy debezium kafka connect**

Here we create kafka connect without ( strimzi.io/use-connector-resources: "true" ) annotations. So we can use Kafka Connect REST API

```
kubectl create -f kafka-debezium-connect.yml -n kafka-dev
```


The KafkaConnector resource offers a Kubernetes-native approach to management of connectors by the Cluster Operator. To manage connectors with KafkaConnector resources, you must specify an annotation in your KafkaConnect custom resource.

- Annotation to enable KafkaConnectors

```
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  name: debezium-connect-cluster
  annotations:
    strimzi.io/use-connector-resources: "true"
```


Setting use-connector-resources to true enables KafkaConnectors to create, delete, and reconfigure connectors.

If use-connector-resources is enabled in your KafkaConnect configuration, you must use the KafkaConnector resource to define and manage connectors


**Create Debezium Kafka connector using Rest API**

- The Kafka Connect REST API is available as a service running on <connect_cluster_name>-connect-api:8083

we can expose Connect REST API as a private ingress etc.

- Create connector

```
curl --location --request POST 'http://debezium-connect-cluster-connect-api:8083/connectors' \
--header 'Content-Type: application/json' \
--data-raw '{
    "name": "mssql-dbz-mssql-connector",
    "config": {
        "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
        "database.hostname": "xxxxxxxxxxxxxxxx.database.windows.net",
        "database.port": "1433",
        "database.user": "dbzqausr",
        "database.password": "xxxxxxxxxxxxxxxxxxxxx",
        "database.dbname": "ztest",
        "database.server.name": "xxxxxxxxxxxx.database.windows.net",
        "table.include.list": "dbo.MEMBER_POINT",
        "database.history.kafka.bootstrap.servers": "debezium-cluster-kafka-bootstrap:9092",
        "database.history.kafka.topic": "actions.MEMBER_POINT",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter.schema.registry.url": "http://schema-registry:8081",
        "key.converter.schema.registry.url": "http://schema-registry:8081"
    }
}'
```


Create 