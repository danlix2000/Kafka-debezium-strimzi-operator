# Kafka  Deploy using the Strimzi operator in multiple namespaces

Kafka , debezium connect and related services will deploy in the below namespaces

- Dev env namespace - kafka-dev

- QA env  namespace - kafka-qa

**Below apps going to use and deploy below apps/plugins/dependencies**

- Strimzi operator
- Kafka With ZooKeeper
- Confluent Schema Registry
- Kafdrop - web UI for viewing Kafka
- Debezium and relevent dependencies 
- Avro converter and relevent dependencies


This environment is deployed in a specific node pool

So we used

- Taints and Tolerations ,nodeAffinity , nodeSelector to deploy all Strimzi operators and Kafka & all other related apps in node pool.

In this environment

- taint key is  "sku".
- taint value is "generalvm"
- nodeSelector - the label is agentpool with a value of customgen

## This deployed and tested on AKS

**1. Namespace creation and strimzi operator deploying using Helm**

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

**2. Deploy strimzi-operator (it will watch dev and qa namespaces)**

```
helm install strimzi-operator  strimzi/strimzi-kafka-operator --namespace strimzi --set watchNamespaces="{kafka-dev,kafka-qa}" -f values.yaml
```


**3. Deploy Kafka and related apps in kafka-dev namespace**

```
kubectl create -f kafka-zookeeper.yml -n kafka-dev

kubectl create -f schema-registry-deployment.yml  -n kafka-dev

kubectl create -f schema-registry-service.yml -n kafka-dev

kubectl create -f  kafdrop-deployment.yml -n kafka-dev

kubectl create -f  kafdrop-service.yml -n kafka-dev

```

- We can use ingress for kafdrop 


**4. Build Docker image for kafka debezium connect**


- In this setup used Azure MS Sql database. So used debezium-connector-sqlserver plugin

- First, Download jar files  and save

Eg:-

```
https://repo1.maven.org/maven2/io/debezium/debezium-connector-sqlserver/1.9.7.Final/debezium-connector-sqlserver-1.9.7.Final-plugin.zip

https://repo1.maven.org/maven2/org/apache/avro/avro/1.10.1/avro-1.10.1.jar

https://packages.confluent.io/maven/io/confluent/kafka-connect-avro-converter/6.2.0/kafka-connect-avro-converter-6.2.0.jar

https://packages.confluent.io/maven/io/confluent/kafka-connect-avro-data/6.2.0/kafka-connect-avro-data-6.2.0.jar

https://packages.confluent.io/maven/io/confluent/kafka-avro-serializer/6.2.0/kafka-avro-serializer-6.2.0.jar

https://packages.confluent.io/maven/io/confluent/kafka-schema-serializer/6.2.0/kafka-schema-serializer-6.2.0.jar

https://packages.confluent.io/maven/io/confluent/kafka-schema-registry-client/6.2.0/kafka-schema-registry-client-6.2.0.jar

https://packages.confluent.io/maven/io/confluent/common-config/6.2.0/common-config-6.2.0.jar

https://packages.confluent.io/maven/io/confluent/common-utils/6.2.0/common-utils-6.2.0.jar

```

Eg:- 

```
ls newjar

avro-1.10.1.jar          common-utils-6.2.0.jar        kafka-avro-serializer-6.2.0.jar         kafka-connect-avro-data-6.2.0.jar       kafka-schema-serializer-6.2.0.jar
common-config-6.2.0.jar  debezium-connector-sqlserver  kafka-connect-avro-converter-6.2.0.jar  kafka-schema-registry-client-6.2.0.jar

ls sqljar/

debezium-connector-sqlserver

```

- Create a Docker file and build. Then push to a private or public repository according to your requirement. 

- Dockerfile content

```
FROM quay.io/strimzi/kafka:0.35.1-kafka-3.4.0
USER root:root
COPY ./newjar/ /opt/kafka/libs/
COPY ./sqljar/ /opt/kafka/plugins/
USER 1001
```


**5. Build and push strimzi Kafkaconenct image with needed libraries and plugins**


- Pushed image to Azure container registry in this environment (you can use any registry)

```
docker build -t strimzi-kafka-connect-av:0.35.1-kafka-3.4.0 .


docker tag strimzi-kafka-connect-av:0.35.1-kafka-3.4.0 xxxxxxxxxxxxxx.azurecr.io/debezium/strimzi/strimzi-kafka-connect-av:0.35.1-kafka-3.4.0


az acr login --name xxxxxxxxxregistry


docker push xxxxxxxxxxxxxxxxxxxxxx.azurecr.io/debezium/strimzi/strimzi-kafka-connect-av:0.35.1-kafka-3.4.0

```


**6. deploy debezium kafka connect**


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


**7. Create Debezium Kafka connector using Rest API**

- The Kafka Connect REST API is available as a service running on <connect_cluster_name>-connect-api:8083

we can use private ingress for  Connect REST API 

- cURL command to create connector

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


## Another way to create KafkaConnector

**1. Create KafkaConnect first**

If you do not want to create connectors using Rest API create them using KafkaConnector resource

-  enable strimzi.io/use-connector-resources: "true"

- YAML content to create connector using KafkaConnector resource

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


**2. Create KafkaConnector yml file and apply**

Eg : kubectl create -f  kafka-connector.yml -n kafka-dev

- YAML definition for KafkaConnector

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


## Deploy QA environment

**1. Similar to dev environment we can deploy QA in qa namespace**

Eg:

```
kubectl create -f kafka-zookeeper.yml -n kafka-qa

kubectl create -f schema-registry-deployment.yml  -n kafka-qa

kubectl create -f schema-registry-service.yml -n kafka-qa

kubectl create -f  kafdrop-deployment.yml -n kafka-qa

kubectl create -f  kafdrop-service.yml -n kafka-qa

kubectl create -f kafka-debezium-connect.yml -n kafka-qa

.........  Create connector using REST API or KafkaConnector resource (Follow above guide)

```


## Check deployed pods and services

- you will see something similar below

```
kubectl get pods,svc -n kafka-qa -o wide
NAME                                                    READY   STATUS    RESTARTS   AGE    IP             NODE                                NOMINATED NODE   READINESS GATES
pod/debezium-cluster-entity-operator-6c545f48dc-vzfr6   3/3     Running   0          103m   10.10.16.140   aks-customgen-33281223-vmss000001   <none>           <none>
pod/debezium-cluster-kafka-0                            1/1     Running   0          103m   10.10.16.128   aks-customgen-33281223-vmss000001   <none>           <none>
pod/debezium-cluster-kafka-1                            1/1     Running   0          103m   10.10.16.136   aks-customgen-33281223-vmss000001   <none>           <none>
pod/debezium-cluster-kafka-2                            1/1     Running   0          103m   10.10.16.38    aks-customgen-33281223-vmss000000   <none>           <none>
pod/debezium-cluster-zookeeper-0                        1/1     Running   0          104m   10.10.16.113   aks-customgen-33281223-vmss000001   <none>           <none>
pod/debezium-cluster-zookeeper-1                        1/1     Running   0          104m   10.10.16.35    aks-customgen-33281223-vmss000000   <none>           <none>
pod/debezium-cluster-zookeeper-2                        1/1     Running   0          104m   10.10.16.107   aks-customgen-33281223-vmss000001   <none>           <none>
pod/debezium-connect-cluster-connect-796f74cd79-cm766   1/1     Running   0          96m    10.10.16.87    aks-customgen-33281223-vmss000000   <none>           <none>
pod/kafka-kafdrop-deployment-57895c74cd-rb9sn           1/1     Running   0          53m    10.10.16.91    aks-customgen-33281223-vmss000000   <none>           <none>
pod/schema-registry-8468c4b65c-kczsf                    1/1     Running   0          61m    10.10.16.61    aks-customgen-33281223-vmss000000   <none>           <none>
pod/strimzi-cluster-operator-889bd964f-75tm9            1/1     Running   0          25h    10.10.16.85    aks-customgen-33281223-vmss000000   <none>           <none>

NAME                                                TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                               AGE    SELECTOR
service/debezium-cluster-kafka-0                    NodePort    10.0.81.168    <none>        9094:31721/TCP                        103m   statefulset.kubernetes.io/pod-name=debezium-cluster-kafka-0,strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-kafka
service/debezium-cluster-kafka-1                    NodePort    10.0.101.140   <none>        9094:30077/TCP                        103m   statefulset.kubernetes.io/pod-name=debezium-cluster-kafka-1,strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-kafka
service/debezium-cluster-kafka-2                    NodePort    10.0.147.58    <none>        9094:31149/TCP                        103m   statefulset.kubernetes.io/pod-name=debezium-cluster-kafka-2,strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-kafka
service/debezium-cluster-kafka-bootstrap            ClusterIP   10.0.125.50    <none>        9091/TCP,9092/TCP,9093/TCP            103m   strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-kafka
service/debezium-cluster-kafka-brokers              ClusterIP   None           <none>        9090/TCP,9091/TCP,9092/TCP,9093/TCP   103m   strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-kafka
service/debezium-cluster-kafka-external-bootstrap   NodePort    10.0.5.118     <none>        9094:32211/TCP                        103m   strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-kafka
service/debezium-cluster-zookeeper-client           ClusterIP   10.0.93.147    <none>        2181/TCP                              104m   strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-zookeeper
service/debezium-cluster-zookeeper-nodes            ClusterIP   None           <none>        2181/TCP,2888/TCP,3888/TCP            104m   strimzi.io/cluster=debezium-cluster,strimzi.io/kind=Kafka,strimzi.io/name=debezium-cluster-zookeeper
service/debezium-connect-cluster-connect-api        ClusterIP   10.0.252.178   <none>        8083/TCP                              96m    strimzi.io/cluster=debezium-connect-cluster,strimzi.io/kind=KafkaConnect,strimzi.io/name=debezium-connect-cluster-connect
service/kafka-kafdrop-service                       NodePort    10.0.229.70    <none>        9000:31400/TCP                        13m    app=kafka-kafdrop
service/schema-registry                             ClusterIP   10.0.96.174    <none>        8081/TCP                              100m   app=schema-registry
```

## For ingress setup

**1. ingress controller**

- For Azure - [Azure Ingress controller](https://learn.microsoft.com/en-us/azure/aks/ingress-basic?tabs=azure-cli "Azure Ingress controller")

- Follow releveant guides for AWS , GCP 


**2. Nginx ingress resource with basic auth**


- i. Create auth password for user

```
htpasswd -c auth inspire
```

- ii. Create secret

```
kubectl create secret generic basic-auth --from-file=auth -n kafka-dev
```
- iii. Map Domain name for ingress IP


- iv Create Ingress resource

- YAML file for Ingress resource

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: inspire-kafka-ing
  namespace: kafka-dev
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/ssl-redirect: 'false'
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - xxxx-debezium-connect-api-dev.non-prod.internal-xxxx.com
        - xxxxx-kafdrop-dev.non-prod.internal-xxxxx.com
       
      secretName: dev-kafka-tls
  ingressClassName: nginx
  rules:
    - host: xxxxx-debezium-connect-api-dev.non-prod.internal-xxxx.com
      http:
        paths:
          - pathType: Prefix
            path: /
            backend:
              service:
                name: debezium-connect-cluster-connect-api
                port:
                  number: 8083
    - host: xxxx-kafdrop-dev.non-prod.internal-xxxxx.com
      http:
        paths:
          - pathType: Prefix
            path: /
            backend:
              service:
                name: kafka-kafdrop-service
                port:
                  number: 90001
```
 
 ## Create Kafka connector using API with basic auth

- cURL contents

Eg:- 

```
curl --location --request POST 'http://debezium-connect-cluster-connect-api:8083/connectors' \
-u devusr:1Sk39F79BRFD \
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

## Enable CDC in Azure SQL DB

- SQL command to enable CDC

```
USE dbztest;
 

-- Enable CDC for the database
 

EXEC sys.sp_cdc_enable_db;


#############

USE dbztest;


-- Enable CDC for the table
  

EXEC sys.sp_cdc_enable_table
 

  @source_schema = 'dbo',

 
  @source_name = 'MEMBER_POINT',
 

  @role_name = 'cdc_admin',

 
  @supports_net_changes = 1;
```

## Check and verify 

- Update CDC enabled table and check on kafdrop (Kafka Topic)
- check debezium-connect pod logs

Eg:- 

```
kubectl logs -f debezium-connect-cluster-connect-796f74cd79-cm766  -n kafka-dev
```


 *Ref :*

- [Strimzi Operator Documentation](https://strimzi.io/docs/operators/latest/overview "Strimzi Operator Documentation")

- [Debezium Documentation](https://debezium.io/documentation/reference/2.4/tutorial.html "Debezium Documentation")
