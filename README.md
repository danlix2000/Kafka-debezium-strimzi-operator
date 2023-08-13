# Kafka  Deploy using the Strimzi operator in multiple namespaces

Kafka , debezium connect and related services will deploy in the below namespaces

- Dev env namespace - kafka-dev

- QA env  namespace - kafka-qa


This environment is deployed in a specific node pool

So we used

 - Taints and Tolerations ,nodeAffinity , nodeSelector to deploy all Strimzi operators and Kafka & all other related apps in node pool.


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
helm install strimzi-operator  strimzi/strimzi-kafka-operator --namespace strimzi --set watchNamespaces="{kafka-dev,kafka-qa}" -f values.yaml
```

Deploy Kafka and related apps in kafka-dev namespace

```
kubectl create -f kafka-zookeeper.yml -n kafka-dev

kubectl create -f schema-registry-deployment.yml  -n kafka-dev

kubectl create -f schema-registry-service.yml -n kafka-dev

kubectl create -f  kafdrop-deployment.yml -n kafka-dev

kubectl create -f  kafdrop-service.yml -n kafka-dev

```



**Build Docker image for kafka debezium connect**

- In this setup used Azure MS Sql database. So used debezium-connector-sqlserver plugin

- First, Download jar files  and save

Eg:- 

```
ls newjar

avro-1.10.1.jar          common-utils-6.2.0.jar        kafka-avro-serializer-6.2.0.jar         kafka-connect-avro-data-6.2.0.jar       kafka-schema-serializer-6.2.0.jar
common-config-6.2.0.jar  debezium-connector-sqlserver  kafka-connect-avro-converter-6.2.0.jar  kafka-schema-registry-client-6.2.0.jar

ls sqljar/

debezium-connector-sqlserver

```

- Create a Docker file and build. Then push to a private or public repository according to your requirement. 

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


The KafkaConnector resource offers a Kubernetes-native approach to the management of connectors by the Cluster Operator. To manage connectors with KafkaConnector resources, you must specify an annotation in your KafkaConnect custom resource.

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


**Create connector using KafkaConnector resource**

If you do not want to create connectors using Rest API create them using KafkaConnector resource

-  enable strimzi.io/use-connector-resources: "true"

```
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  name: debezium-connect-cluster
  annotations:
    strimzi.io/use-connector-resources: "true"
spec:
  version: 3.3.1
  image: xxxxxxxxxxxxx.azurecr.io/debezium/strimzi/strimzi-kafka-connect-av:0.35.1-kafka-3.4.0 # update Container repo and image
  replicas: 1
  bootstrapServers: debezium-cluster-kafka-bootstrap:9092
  config:
    config.providers: secrets
    config.providers.secrets.class: io.strimzi.kafka.KubernetesSecretConfigProvider
    group.id: connect-cluster
    offset.storage.topic: connect-cluster-offsets
    config.storage.topic: connect-cluster-configs
    status.storage.topic: connect-cluster-status
    # -1 means it will use the default replication factor configured in the broker
    config.storage.replication.factor: -1
    offset.storage.replication.factor: -1
    status.storage.replication.factor: -1
  template:
      pod:
        tolerations:
          - key: "sku"
            operator: "Equal"
            value: "generalvm"
            effect: "NoSchedule"
        affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: agentpool
                  operator: In
                  values:
                  - customgen
```


**Create KafkaConnector yml file and apply**

Eg : kubectl create -f  kafkaconnector.yml -n kafka-dev

```
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: mssql-azure-sql-connector
  #namespace: kafka-dev
  labels:
    strimzi.io/cluster: debezium-connect-cluster
spec:
  class: io.debezium.connector.sqlserver.SqlServerConnector
  tasksMax: 1
  config:
    database.hostname: xxxxxxxxxxxxxxxx.database.windows.net
    database.port: 1433
    database.user: dbzqausr
    database.password: xxxxxxxxxxxxxxxx
    database.dbname: dbztest
    database.server.name: xxxxxxxxxxxx-sql01
    table.include.list: dbo.MEMBER_POINT
    database.history.kafka.bootstrap.servers: debezium-cluster-kafka-bootstrap:9092
    database.history.kafka.topic: event.MEMBER_POINT
    key.converter: io.confluent.connect.avro.AvroConverter
    key.converter.schema.registry.url: http://schema-registry:8081
    value.converter: io.confluent.connect.avro.AvroConverter
    value.converter.schema.registry.url: http://schema-registry:8081
  template:
      pod:
        tolerations:
          - key: "sku"
            operator: "Equal"
            value: "generalvm"
            effect: "NoSchedule"
        affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: agentpool
                  operator: In
                  values:
                  - customgen
```

**Similar to dev environment we can deploy QA in qa namespace**

Eg:

```
kubectl create -f kafka-zookeeper.yml -n kafka-qa

kubectl create -f schema-registry-deployment.yml  -n kafka-qa

kubectl create -f schema-registry-service.yml -n kafka-qa

kubectl create -f  kafdrop-deployment.yml -n kafka-qa

kubectl create -f  kafdrop-service.yml -n kafka-qa

.........

```