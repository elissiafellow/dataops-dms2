# Kafka/Strimzi Monitoring Setup - Complete Guide

Welcome! This document explains the complete monitoring setup for your Kafka infrastructure. This is a production-grade monitoring solution that will help you keep track of your Kafka clusters, detect issues early, and maintain system health.

## Table of Contents

1. [What is Monitoring and Why Do We Need It?](#what-is-monitoring-and-why-do-we-need-it)
2. [Architecture Overview](#architecture-overview)
3. [File-by-File Breakdown](#file-by-file-breakdown)
4. [How Everything Works Together](#how-everything-works-together)
5. [Key Concepts Explained](#key-concepts-explained)
6. [How to Use This Setup](#how-to-use-this-setup)
7. [Troubleshooting](#troubleshooting)
8. [Next Steps](#next-steps)

---

## What is Monitoring and Why Do We Need It?

### What is Monitoring?

Monitoring is like having a health checkup system for your Kafka infrastructure. It continuously watches your system and collects information about:
- **Performance**: How fast messages are being processed
- **Health**: Are all components running properly?
- **Resources**: Are we running out of disk space or memory?
- **Errors**: Are there any failures or issues?

### Why Do We Need It?

Without monitoring, you're "flying blind". You won't know:
- ❌ If Kafka is running out of disk space (until it crashes)
- ❌ If messages are piling up (consumer lag)
- ❌ If brokers are down or unhealthy
- ❌ If connectors are failing
- ❌ If certificates are about to expire

With monitoring, you get:
- ✅ **Early warnings** before problems become critical
- ✅ **Visibility** into what's happening in your cluster
- ✅ **Historical data** to understand trends
- ✅ **Alerts** when something goes wrong
- ✅ **Dashboards** to visualize your system

### The Monitoring Stack

This setup uses:
- **Prometheus**: Collects and stores metrics (time-series database)
- **Prometheus Operator**: Manages Prometheus automatically
- **Alertmanager**: Handles alert routing and notifications
- **Grafana**: Creates beautiful dashboards (optional, but recommended)
- **Kafka UI**: Web interface for Kafka management

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kafka/Strimzi Components                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Kafka        │  │ Cluster      │  │ Entity        │          │
│  │ Brokers      │  │ Operator     │  │ Operator      │          │
│  │              │  │              │  │              │          │
│  │ Expose       │  │ Exposes      │  │ Exposes      │          │
│  │ metrics on   │  │ metrics on   │  │ metrics on   │          │
│  │ port 9404   │  │ port 8080      │  │ port 8080    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Metrics exposed via HTTP endpoints
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              PodMonitors (strimzi-pod-monitor.yaml)             │
│                                                                   │
│  These are "instructions" that tell Prometheus:                  │
│  - Which pods to scrape                                           │
│  - Which ports to use                                             │
│  - What labels to add                                             │
│                                                                   │
│  PodMonitors use label selectors to find pods:                   │
│  - cluster-operator-metrics: Finds Cluster Operator              │
│  - entity-operator-metrics: Finds Entity Operator                │
│  - kafka-resources-metrics: Finds all Kafka pods                  │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Prometheus Operator watches PodMonitors
                            │ and configures Prometheus automatically
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              Prometheus (from kube-prometheus-stack)             │
│                                                                   │
│  Prometheus:                                                      │
│  1. Discovers PodMonitors                                        │
│  2. Scrapes metrics from Kafka pods every 30 seconds             │
│  3. Stores metrics in time-series database                        │
│  4. Evaluates alert rules                                        │
│  5. Fires alerts when conditions are met                         │
│                                                                   │
│  RBAC (prometheus.yaml):                                         │
│  - Gives Prometheus permissions to read Kubernetes resources     │
│  - Allows Prometheus to scrape /metrics endpoints                │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Prometheus evaluates rules
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│           PrometheusRule (strimzi-alerts.yaml)                   │
│                                                                   │
│  Defines alert conditions:                                       │
│  - "Alert if disk space < 35%"                                   │
│  - "Alert if partitions are under-replicated"                   │
│  - "Alert if brokers are down"                                   │
│  - "Alert if connectors are failing"                            │
│                                                                   │
│  When conditions are met, Prometheus fires alerts                │
│  → Alertmanager receives alerts                                  │
│  → Alertmanager can send notifications (Slack, email, etc.)    │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Optional: View in Grafana
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Grafana Dashboards                             │
│  (Optional but recommended - creates beautiful visualizations)  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Kafka UI (kafkaui.yaml)                       │
│                                                                   │
│  Web interface for Kafka management:                             │
│  - View topics and partitions                                    │
│  - Browse messages                                                │
│  - Monitor consumer groups                                        │
│  - Manage connectors                                              │
│  - View schemas                                                   │
│                                                                   │
│  Access: http://kafka-ui.monitoring.svc.cluster.local            │
│  Login: admin / pass                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## File-by-File Breakdown

### 1. `prometheus.yaml` - RBAC Permissions

**What is RBAC?**
RBAC (Role-Based Access Control) defines **who can do what** in Kubernetes. Prometheus needs permissions to:
- Read information about pods, services, endpoints
- Access `/metrics` endpoints on pods
- Discover resources in the cluster

**What this file creates:**

```yaml
ClusterRole: prometheus-server
  - Can read: nodes, services, endpoints, pods, ingresses
  - Can access: /metrics endpoints
  - Purpose: Allows Prometheus to discover and scrape metrics

ServiceAccount: prometheus-server
  - Namespace: monitoring
  - Purpose: Identity for Prometheus (like a user account)

ClusterRoleBinding: prometheus-server
  - Binds: ServiceAccount → ClusterRole
  - Purpose: Gives the ServiceAccount the permissions
```

**Why is this needed?**
Without these permissions, Prometheus can't:
- ❌ Discover which pods exist
- ❌ Read pod labels to find Kafka pods
- ❌ Access `/metrics` endpoints
- ❌ Scrape any metrics

**Think of it like this:**
- Prometheus is like a security guard
- RBAC is like giving the guard a badge that allows them to enter buildings and read information
- Without the badge, the guard can't do their job

---

### 2. `strimzi-pod-monitor.yaml` - Service Discovery

**What is a PodMonitor?**
A PodMonitor is a **Custom Resource** (CRD) that tells Prometheus:
- "Hey, scrape these pods!"
- "Use this port to get metrics"
- "Add these labels to the metrics"

**Why not just configure Prometheus directly?**
- **Automatic discovery**: When new Kafka pods are created, Prometheus automatically starts scraping them
- **No manual configuration**: You don't need to edit Prometheus config
- **Kubernetes-native**: Uses Kubernetes labels and selectors

**What this file creates:**

#### PodMonitor 1: `cluster-operator-metrics`
```yaml
Purpose: Monitor the Strimzi Cluster Operator
Selector: strimzi.io/kind: cluster-operator
Port: http (port 8080)
Namespace: kafka
```

**What it does:**
- Finds pods with label `strimzi.io/kind: cluster-operator`
- Scrapes metrics from port `http` (8080)
- Collects metrics about the operator's health

**Metrics you'll get:**
- Operator uptime
- Number of resources managed
- Reconciliation errors
- Resource creation/deletion events

#### PodMonitor 2: `entity-operator-metrics`
```yaml
Purpose: Monitor the Entity Operator (manages topics and users)
Selector: app.kubernetes.io/name: entity-operator
Port: healthcheck (port 8080)
Namespace: kafka
```

**What it does:**
- Finds Entity Operator pods
- Scrapes metrics from port `healthcheck`
- Monitors topic and user management

**Metrics you'll get:**
- Topic creation/deletion events
- User management operations
- Operator health status

#### PodMonitor 3: `kafka-resources-metrics`
```yaml
Purpose: Monitor ALL Kafka-related pods (brokers, connectors, etc.)
Selector: strimzi.io/kind IN [Kafka, KafkaConnect, KafkaMirrorMaker2, KafkaNodePool]
Port: tcp-prometheus (port 9404)
Namespace: kafka
```

**What it does:**
- Finds ALL pods that are Kafka brokers, connectors, etc.
- Scrapes metrics from port `tcp-prometheus` (9404)
- Adds useful labels to metrics

**Relabeling (lines 58-85):**
This is important! It adds labels to metrics so you can filter and group them:

```yaml
- Adds namespace label: "kafka"
- Adds pod name label: "primary-broker-0"
- Adds node name label: "ip-10-30-2-123"
- Adds node IP label: "10.30.2.123"
- Adds all strimzi.io/* labels from pod
```

**Why relabeling matters:**
Without relabeling, you can't easily:
- Filter metrics by pod name
- Group metrics by namespace
- Identify which node a pod is on
- Correlate metrics with Kubernetes resources

**Metrics you'll get:**
- Message throughput (messages/second)
- Consumer lag
- Partition counts
- Replication status
- Disk usage
- Network I/O
- JVM metrics (memory, GC, threads)

---

### 3. `strimzi-alerts.yaml` - Alerting Rules

**What is a PrometheusRule?**
A PrometheusRule defines **conditions** that, when met, trigger alerts. Think of it like:
- "If disk space < 35%, send alert"
- "If broker is down for 3 minutes, send alert"
- "If consumer lag > 1000, send alert"

**How alerts work:**
1. Prometheus continuously evaluates the rules
2. When a condition is true, it fires an alert
3. Alertmanager receives the alert
4. Alertmanager can send notifications (Slack, email, PagerDuty, etc.)

**Alert Structure:**
```yaml
- alert: AlertName
  expr: PromQL expression  # The condition to check
  for: duration            # How long condition must be true
  labels:                 # Additional labels
    severity: warning/major
  annotations:            # Human-readable messages
    summary: "Short description"
    description: "Detailed description"
```

**Alert Groups Explained:**

#### Group 1: `kafka` - Core Kafka Alerts

**`KafkaRunningOutOfSpace`**
```yaml
Condition: Disk space < 35% on Kafka PVCs
Duration: 10 seconds
Severity: warning
```
**Why it matters:** Kafka stores messages on disk. If disk fills up, Kafka will stop accepting new messages.

**`UnderReplicatedPartitions`**
```yaml
Condition: kafka_server_replicamanager_underreplicatedpartitions > 0
Duration: 10 seconds
Severity: warning
```
**Why it matters:** Partitions should have multiple replicas for high availability. If replicas are missing, you risk data loss if a broker fails.

**`AbnormalControllerState`**
```yaml
Condition: Number of active controllers != 1
Duration: 10 seconds
Severity: warning
```
**Why it matters:** Kafka should have exactly ONE controller. Multiple controllers = split-brain scenario (very bad!).

**`OfflinePartitions`**
```yaml
Condition: Partitions with no leader
Duration: 10 seconds
Severity: warning
```
**Why it matters:** Partitions without leaders can't accept reads/writes. This means data is unavailable.

**`UnderMinIsrPartitionCount`**
```yaml
Condition: Partitions below minimum ISR (In-Sync Replicas)
Duration: 10 seconds
Severity: warning
```
**Why it matters:** ISR = replicas that are in sync with the leader. If ISR < minimum, Kafka may stop accepting writes.

**`OfflineLogDirectoryCount`**
```yaml
Condition: Offline log directories detected
Duration: 10 seconds
Severity: warning
```
**Why it matters:** Log directories store Kafka data. If they're offline, data is inaccessible.

**`ScrapeProblem`**
```yaml
Condition: Prometheus can't scrape metrics for 3+ minutes
Duration: 3 minutes
Severity: major
```
**Why it matters:** If Prometheus can't scrape, you're blind. This could mean:
- Pod is down
- Network issues
- Metrics endpoint is broken

**`ClusterOperatorContainerDown`**
```yaml
Condition: Cluster Operator down for > 90 seconds
Duration: 1 minute
Severity: major
```
**Why it matters:** Cluster Operator manages Kafka resources. If it's down, you can't:
- Create/update Kafka clusters
- Scale clusters
- Update configurations

**`KafkaBrokerContainersDown`**
```yaml
Condition: All broker containers down for 3+ minutes
Duration: 3 minutes
Severity: major
```
**Why it matters:** If all brokers are down, Kafka is completely unavailable. No reads, no writes.

**`KafkaContainerRestartedInTheLast5Minutes`**
```yaml
Condition: Containers restarted too frequently
Duration: 5 minutes
Severity: warning
```
**Why it matters:** Frequent restarts indicate:
- Memory issues (OOM kills)
- Configuration problems
- Resource constraints

#### Group 2: `controller` - Controller-Specific Alerts

**`ControllerContainerRestartedInTheLast5Minutes`**
- Monitors controller pods specifically
- Controllers are critical for cluster coordination

**`ControllerContainersDown`**
- All controller containers are down
- This is critical - controllers manage cluster metadata

#### Group 3: `entityOperator` - Entity Operator Alerts

**`TopicOperatorContainerDown`**
- Topic Operator manages topics
- If down, topic creation/updates won't work

**`UserOperatorContainerDown`**
- User Operator manages Kafka users/ACLs
- If down, user management won't work

#### Group 4: `connect` - Kafka Connect Alerts

**`ConnectContainersDown`**
- All Connect containers are down
- No connectors can run

**`ConnectFailedConnector`**
- Connector in failed state for 5+ minutes
- Data pipeline is broken

**`ConnectFailedTask`**
- Task in failed state for 5+ minutes
- Part of a connector is broken

#### Group 5: `kafkaExporter` - Kafka Exporter Alerts

**`UnderReplicatedPartition`**
- Topic has under-replicated partitions
- Risk of data loss

**`TooLargeConsumerGroupLag`**
- Consumer lag > 1000 messages
- Consumers can't keep up with producers
- Messages are piling up

**`NoMessageForTooLong`**
- No messages for 10+ minutes
- Could indicate:
  - Producers stopped
  - Network issues
  - Topic misconfiguration

#### Group 6: `certificates` - Certificate Expiration

**`CertificateExpiration`**
- Certificate expiring in < 30 days
- Prevents certificate expiration issues
- Strimzi auto-renews, but good to monitor

---

### 4. `kafkaui.yaml` - Kafka UI Deployment

**What is Kafka UI?**
A web-based interface for managing and monitoring Kafka clusters. Think of it as a "control panel" for Kafka.

**What it provides:**
- 📊 **Topics**: View all topics, partitions, messages
- 👥 **Consumer Groups**: Monitor consumer lag, offsets
- 🔌 **Connectors**: View and manage Kafka Connect connectors
- 📝 **Schemas**: Browse Avro/JSON schemas
- 📈 **Metrics**: View cluster metrics
- 🔍 **Message Browser**: Search and view messages

**Configuration Explained:**

```yaml
# Authentication
AUTH_TYPE: LOGIN_FORM
SPRING_SECURITY_USER_NAME: admin
SPRING_SECURITY_USER_PASSWORD: pass
```
**Security Note:** For production, use proper authentication (OAuth, LDAP, etc.)

```yaml
# Primary Kafka Cluster
KAFKA_CLUSTERS_0_NAME: primary
KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: primary-kafka-bootstrap.kafka.svc.cluster.local:9092
```
**What this does:** Connects to your primary Kafka cluster using the bootstrap service.

```yaml
# Metrics Configuration
KAFKA_CLUSTERS_0_METRICS_PORT: 9999
KAFKA_CLUSTERS_0_METRICS_TYPE: jmx
```
**What this does:** Uses JMX metrics on port 9999. Alternative is Prometheus on port 9404.

```yaml
# Kafka Connect Integration
KAFKA_CLUSTERS_0_KAFKACONNECT_0_NAME: kafka-connect-cluster
KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS: http://kafka-connect-cluster-connect-api.kafka.svc.cluster.local:8083
```
**What this does:** Connects to Kafka Connect so you can manage connectors from the UI.

```yaml
# Schema Registry Integration
KAFKA_CLUSTERS_0_SCHEMAREGISTRY: http://schema-registry.kafka.svc.cluster.local:8081
```
**What this does:** Connects to Schema Registry to browse schemas.

**Node Affinity:**
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kafka-cluster-role
              operator: In
              values:
                - "admin-tools"
```
**What this does:** Schedules Kafka UI on nodes with label `kafka-cluster-role=admin-tools`. This is optional - remove if you don't have this label.

**Service:**
```yaml
type: ClusterIP
port: 80
targetPort: 8080
```
**What this does:** Exposes Kafka UI on port 80 (internal cluster access). To access from outside, create an Ingress or use port-forward.

**How to Access:**
```bash
# Port-forward to access from local machine
kubectl port-forward svc/kafka-ui -n monitoring 8080:80

# Then open: http://localhost:8080
# Login: admin / pass
```

---

## How Everything Works Together

### Step-by-Step Flow

1. **Kafka Pods Start**
   - Kafka brokers, operators, connectors start
   - They expose metrics on specific ports (9404, 8080, etc.)

2. **PodMonitors are Created**
   - `strimzi-pod-monitor.yaml` is applied
   - PodMonitors use label selectors to find Kafka pods

3. **Prometheus Operator Watches**
   - Prometheus Operator (part of kube-prometheus-stack) watches for PodMonitors
   - When it sees a PodMonitor, it automatically configures Prometheus

4. **Prometheus Scrapes Metrics**
   - Prometheus reads the PodMonitor configuration
   - It discovers pods matching the selectors
   - Every 30 seconds, it scrapes metrics from those pods
   - Metrics are stored in Prometheus's time-series database

5. **Prometheus Evaluates Alerts**
   - Prometheus continuously evaluates the rules in `strimzi-alerts.yaml`
   - When a condition is true for the specified duration, it fires an alert
   - Alerts are sent to Alertmanager

6. **Alertmanager Routes Alerts**
   - Alertmanager receives alerts
   - It can route them to:
     - Slack channels
     - Email
     - PagerDuty
     - Webhooks
     - etc.

7. **You View Metrics**
   - Use Prometheus UI to query metrics
   - Use Grafana to create dashboards
   - Use Kafka UI to manage Kafka

---

## Key Concepts Explained

### What are Metrics?

**Metrics** are numerical measurements over time. Examples:
- `kafka_server_broker_topic_messages_in_total`: Total messages received
- `kafka_consumer_lag_sum`: Consumer lag in messages
- `kafka_server_replicamanager_underreplicatedpartitions`: Number of under-replicated partitions

**Think of metrics like:**
- Speedometer in a car (shows current speed)
- Thermometer (shows temperature)
- Heart rate monitor (shows beats per minute)

### What is Scraping?

**Scraping** is when Prometheus requests metrics from a pod. The pod responds with metrics in a specific format (Prometheus format).

**Process:**
1. Prometheus sends HTTP GET request to `http://pod-ip:9404/metrics`
2. Pod responds with metrics:
   ```
   kafka_server_broker_topic_messages_in_total{topic="my-topic"} 12345
   kafka_consumer_lag_sum{group="my-consumer"} 100
   ```
3. Prometheus stores these metrics with a timestamp

### What are Labels?

**Labels** are key-value pairs that identify metrics. They allow you to filter and group metrics.

**Example:**
```
kafka_server_broker_topic_messages_in_total{
  topic="orders",
  partition="0",
  pod="primary-broker-0",
  namespace="kafka"
} 12345
```

**Why labels matter:**
- Filter: `kafka_server_broker_topic_messages_in_total{topic="orders"}`
- Group: `sum by (topic) (kafka_server_broker_topic_messages_in_total)`
- Aggregate: `avg(kafka_server_broker_topic_messages_in_total)`

### What is PromQL?

**PromQL** (Prometheus Query Language) is used to query metrics. It's like SQL for metrics.

**Examples:**
```promql
# Get current value
kafka_consumer_lag_sum

# Get value for specific topic
kafka_consumer_lag_sum{topic="orders"}

# Calculate rate (messages per second)
rate(kafka_server_broker_topic_messages_in_total[5m])

# Sum by topic
sum by (topic) (kafka_server_broker_topic_messages_in_total)

# Average across all pods
avg(kafka_consumer_lag_sum)
```

### What are Alerts?

**Alerts** are notifications when something is wrong or about to go wrong.

**Alert Lifecycle:**
1. **Pending**: Condition is true, but duration not met yet
2. **Firing**: Condition is true for the required duration
3. **Resolved**: Condition is no longer true

**Example:**
```yaml
- alert: KafkaRunningOutOfSpace
  expr: disk_space < 35%
  for: 10s
```
- If disk space < 35% for 10 seconds → Alert fires
- If disk space goes back to > 35% → Alert resolves

### What is Service Discovery?

**Service Discovery** is how Prometheus automatically finds pods to scrape.

**Without Service Discovery:**
- You'd have to manually configure each pod's IP address
- When pods restart (new IP), you'd have to update config
- Very manual and error-prone

**With Service Discovery (PodMonitors):**
- Prometheus uses label selectors to find pods
- When new pods are created, they're automatically discovered
- When pods are deleted, scraping stops automatically
- Fully automatic!

---

## How to Use This Setup

### 1. Deploy the Monitoring Components

These files are deployed via ArgoCD. The `10-monitoring.yaml` ArgoCD application will apply:
- `prometheus.yaml` (RBAC)
- `strimzi-pod-monitor.yaml` (Service Discovery)
- `strimzi-alerts.yaml` (Alerting Rules)
- `kafkaui.yaml` (Kafka UI)

### 2. Verify Prometheus is Scraping

**Check if PodMonitors are discovered:**
```bash
kubectl get podmonitors -n kafka
```

**Check Prometheus targets:**
```bash
# Port-forward Prometheus
kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090

# Open http://localhost:9090
# Go to Status → Targets
# Look for targets with "kafka" in the name
# They should all be "UP" (green)
```

### 3. View Metrics in Prometheus

**Query examples:**
```promql
# Consumer lag
kafka_consumer_lag_sum

# Messages per second
rate(kafka_server_broker_topic_messages_in_total[5m])

# Under-replicated partitions
kafka_server_replicamanager_underreplicatedpartitions

# Disk usage
kubelet_volume_stats_available_bytes{persistentvolumeclaim=~"data.*-primary-broker.*"}
```

### 4. View Alerts

**In Prometheus UI:**
- Go to http://localhost:9090/alerts
- See all alerts and their status (pending/firing)

**In Alertmanager:**
```bash
kubectl port-forward svc/alertmanager-operated -n monitoring 9093:9093
# Open http://localhost:9093
```

### 5. Access Kafka UI

```bash
# Port-forward Kafka UI
kubectl port-forward svc/kafka-ui -n monitoring 8080:80

# Open http://localhost:8080
# Login: admin / pass
```

**What you can do:**
- Browse topics and messages
- View consumer groups and lag
- Monitor connectors
- Browse schemas

### 6. Create Grafana Dashboards (Optional)

Grafana can create beautiful dashboards from Prometheus metrics. You can:
- Create custom dashboards
- Use pre-built Kafka dashboards
- Set up alerting rules

---

## Troubleshooting

### Prometheus Not Scraping Metrics

**Symptoms:**
- No metrics in Prometheus
- Targets show as "DOWN"

**Check:**
```bash
# 1. Verify PodMonitors exist
kubectl get podmonitors -n kafka

# 2. Check Prometheus logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus

# 3. Verify pods have correct labels
kubectl get pods -n kafka --show-labels

# 4. Test metrics endpoint manually
kubectl port-forward <kafka-pod> -n kafka 9404:9404
curl http://localhost:9404/metrics
```

**Common Issues:**
- PodMonitors not created
- Wrong label selectors
- Pods not exposing metrics on expected port
- Network policies blocking access

### Alerts Not Firing

**Symptoms:**
- Conditions are met but no alerts

**Check:**
```bash
# 1. Verify PrometheusRule exists
kubectl get prometheusrules -n monitoring

# 2. Check Prometheus alert rules
# In Prometheus UI: Status → Rules
# Verify rules are loaded

# 3. Test PromQL expression
# In Prometheus UI: Go to Graph
# Paste the expression from the alert
# Verify it returns results
```

**Common Issues:**
- PrometheusRule not created
- PromQL expression incorrect
- Duration too short (alert resolves before firing)
- Alertmanager not configured

### Kafka UI Not Connecting

**Symptoms:**
- Kafka UI loads but shows "Connection failed"

**Check:**
```bash
# 1. Verify Kafka bootstrap service exists
kubectl get svc -n kafka | grep bootstrap

# 2. Test connectivity from Kafka UI pod
kubectl exec -it deployment/kafka-ui -n monitoring -- sh
# Inside pod:
nslookup primary-kafka-bootstrap.kafka.svc.cluster.local
telnet primary-kafka-bootstrap.kafka.svc.cluster.local 9092

# 3. Check Kafka UI logs
kubectl logs deployment/kafka-ui -n monitoring
```

**Common Issues:**
- Wrong bootstrap service name
- Network policies blocking access
- Kafka cluster not ready
- Wrong namespace in configuration

### Metrics Missing Labels

**Symptoms:**
- Can't filter metrics by pod name or namespace

**Check:**
```bash
# Verify relabeling in PodMonitor
kubectl get podmonitor kafka-resources-metrics -n kafka -o yaml
# Check the relabelings section
```

**Fix:**
- Ensure relabelings are correctly configured in `strimzi-pod-monitor.yaml`
- Restart Prometheus to pick up changes

---

## Next Steps

### Immediate Next Steps

1. **Deploy Monitoring**: Apply these files via ArgoCD
2. **Verify Scraping**: Check Prometheus targets are UP
3. **Test Alerts**: Trigger a test alert to verify alerting works
4. **Access Kafka UI**: Set up port-forward and explore the UI

### Future Enhancements

1. **Grafana Dashboards**: Create custom dashboards for Kafka metrics
2. **Alert Notifications**: Configure Alertmanager to send alerts to Slack/email
3. **Additional Metrics**: Add custom metrics for your specific use cases
4. **Log Aggregation**: Set up ELK or Loki for log aggregation
5. **Distributed Tracing**: Add Jaeger or Zipkin for request tracing

### Learning Resources

- **Prometheus**: https://prometheus.io/docs/
- **Prometheus Operator**: https://github.com/prometheus-operator/prometheus-operator
- **PromQL**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Strimzi Metrics**: https://strimzi.io/docs/operators/latest/deploying.html#proc-metrics-str
- **Kafka UI**: https://docs.kafka-ui.provectus.io/

---

## Summary

This monitoring setup provides:

✅ **Comprehensive Metrics**: All Kafka components are monitored
✅ **Automatic Discovery**: New pods are automatically discovered
✅ **Proactive Alerting**: Get notified before problems become critical
✅ **Easy Management**: Kafka UI provides web interface
✅ **Production-Ready**: Used in production environments

**Key Takeaways:**
- **PodMonitors** tell Prometheus what to scrape
- **PrometheusRules** define when to alert
- **RBAC** gives Prometheus permissions
- **Kafka UI** provides web interface

You now have a complete monitoring solution for your Kafka infrastructure! 🎉

---

*Happy monitoring! Tomorrow you'll seed the source database and continue setting up the cluster. Exciting times ahead!* 🚀
