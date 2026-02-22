# DataOps DMS Cluster Deployment Plan

This document provides a step-by-step plan for creating a Kubernetes cluster from scratch and deploying all DataOps DMS components using ArgoCD.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Infrastructure Setup](#infrastructure-setup)
3. [Cluster Configuration](#cluster-configuration)
4. [ArgoCD Installation](#argocd-installation)
5. [Application Deployment](#application-deployment)
6. [Verification Steps](#verification-steps)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
- **AWS CLI** v2.x installed and configured
- **kubectl** v1.28+ (matching EKS cluster version)
- **Terraform** v1.5+
- **Helm** v3.12+
- **ArgoCD CLI** (optional but recommended)
- **Git** with SSH access to `git@github.com:moneYOUnion/dataops-dms.git`

### AWS Requirements
- AWS account with appropriate permissions
- IAM permissions for:
  - EKS cluster creation
  - VPC/Networking resources
  - EC2 instances
  - IAM role creation
- AWS credentials configured (`aws configure`)

### Access Requirements
- SSH key configured for GitHub access
- Access to the repository: `moneYOUnion/dataops-dms`
- Required Helm chart repositories:
  - `https://charts.external-secrets.io`
  - `https://charts.bitnami.com/bitnami`
  - `https://prometheus-community.github.io/helm-charts`
  - `https://kubernetes.github.io/autoscaler`

### Resource Requirements
- **Minimum Node Size**: t3.small (2 vCPU, 2GB RAM)
- **Recommended**: t3.medium or larger for production workloads
- **Storage**: EBS volumes for persistent storage (Kafka, monitoring)
- **Network**: VPC with public/private subnets across 2+ AZs

---

## Infrastructure Setup

### Step 1: Configure Terraform Variables

Navigate to the infrastructure directory:
```bash
cd /Users/elissianashaat/Documents/demos/demo-env/infra
```

Review and update `terraform.tfvars` if needed:
```hcl
environment         = "dataops-dms"
aws_region          = "eu-central-1"  # Change if needed
vpc_cidr            = "10.30.0.0/16"
eks_instance_type   = "t3.medium"    # Recommended: t3.medium or larger
eks_min_size        = 2              # Minimum 2 for HA
eks_max_size        = 5
eks_desired_size    = 2
eks_cluster_version = "1.28"         # Update to latest stable if needed
```

**Note**: For Kafka workloads, consider:
- `t3.medium` or `t3.large` instances (Kafka is resource-intensive)
- Minimum 2 nodes for high availability
- Ensure sufficient storage for Kafka data retention

### Step 2: Initialize and Plan Terraform

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Verify the plan shows:
# - VPC with public/private subnets
# - Internet Gateway and NAT Gateway
# - EKS cluster
# - EKS node group
# - Required IAM roles and policies
```

### Step 3: Apply Infrastructure

```bash
# Create the infrastructure
terraform apply

# This will take 15-20 minutes. Wait for completion.
# Save the outputs (cluster name, VPC ID, etc.)
```

### Step 4: Configure kubectl Access

```bash
# Update kubeconfig to access the cluster
aws eks update-kubeconfig \
  --name <environment>-eks \
  --region <aws_region>

# Verify cluster access
kubectl get nodes
kubectl get namespaces
```

**Expected Output:**
```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-30-x-x.ec2.internal    Ready    <none>   5m    v1.28.x
ip-10-30-x-x.ec2.internal    Ready    <none>   5m    v1.28.x
```

---

## Cluster Configuration

### Step 1: Install AWS Load Balancer Controller (Required for Ingress)

The AWS Load Balancer Controller is needed for Ingress resources and ALB creation.

```bash
# Add the EKS Helm chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<environment>-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

**Note**: You may need to create the IAM service account and attach policies. See AWS documentation for details.

### Step 2: Install Cluster Autoscaler (Optional but Recommended)

If you want automatic node scaling, install the cluster autoscaler. However, this will also be deployed via ArgoCD later.

### Step 3: Verify Storage Classes

Check available storage classes:
```bash
kubectl get storageclass
```

You should see `gp2` or `gp3` as default. The ArgoCD applications will create additional storage classes if needed.

---

## ArgoCD Installation

### Step 1: Create ArgoCD Namespace

```bash
kubectl create namespace argocd
```

### Step 2: Install ArgoCD

```bash
# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods to be ready (this may take 2-3 minutes)
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/name=argocd-server -n argocd
```

### Step 3: Access ArgoCD

**Option A: Port Forward (Quick Access)**
```bash
# Port forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at: https://localhost:8080
# Username: admin
# Password: (get from below command)
```

**Option B: Ingress (Production)**
Configure an Ingress resource to expose ArgoCD via ALB (requires AWS Load Balancer Controller).

**Get Admin Password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### Step 4: Install ArgoCD CLI (Optional)

```bash
# macOS
brew install argocd

# Or download from: https://github.com/argoproj/argo-cd/releases
```

**Login via CLI:**
```bash
argocd login localhost:8080 --username admin --password <password-from-step-3>
```

### Step 5: Configure ArgoCD Repository Access

ArgoCD needs access to your Git repository. You have two options:

**Option A: SSH Key (Recommended)**
1. Create a Kubernetes secret with your SSH private key:
```bash
kubectl create secret generic argocd-repo-credentials \
  --from-file=sshPrivateKey=<path-to-your-ssh-private-key> \
  -n argocd
```

2. Update ArgoCD to use this secret (via UI or CLI)

**Option B: HTTPS with Token**
Configure repository access via ArgoCD UI: Settings → Repositories → Connect Repo

---

## Application Deployment

### Deployment Order (Based on Sync Waves)

Applications are deployed in order based on `argocd.argoproj.io/sync-wave` annotations:

| Wave | Application | Namespace | Purpose |
|------|-------------|-----------|---------|
| 1 | namespaces | default | Create required namespaces |
| 2 | external-secrets | external-secrets | External Secrets Operator |
| 3 | secrets | default | Secrets and ExternalSecret resources |
| 4 | storage-class | default | Storage classes for persistent volumes |
| 5 | strimzi-operator | kafka | Strimzi Kafka Operator |
| 6 | kafka-cluster | kafka | Kafka cluster deployment |
| 7 | schema-registry | kafka | Schema Registry (Helm chart) |
| 8 | kafka-connect | default | Kafka Connect deployment |
| 9 | debezium-schema-topics | default | Schema topics for Debezium |
| 10 | monitoring-addons | default | Monitoring components |
| 11 | monitoring (kube-prometheus) | monitoring | Prometheus stack |
| 12 | cluster-autoscaler | monitoring | Cluster autoscaler |
| 13 | kafka-connectors | default | Kafka connectors |

### Step 1: Deploy App-of-Apps Pattern

The `app-of-apps.yaml` file uses the App-of-Apps pattern to deploy all applications:

```bash
# Apply the app-of-apps configuration
kubectl apply -f /Users/elissianashaat/Documents/demos/dataops-dms2/app-of-apps.yaml

# Verify the application is created
kubectl get application -n argocd
```

**Note**: The app-of-apps references the Git repository. Ensure:
- Repository URL is correct: `git@github.com:moneYOUnion/dataops-dms.git`
- Branch is correct: `master` (or update to your branch)
- ArgoCD has access to the repository

### Step 2: Monitor Deployment Progress

**Via ArgoCD UI:**
1. Open ArgoCD UI (https://localhost:8080)
2. Navigate to Applications
3. Click on "cluster" application
4. Monitor sync status and health

**Via CLI:**
```bash
# Watch application status
watch kubectl get applications -n argocd

# Check specific application
argocd app get <application-name>

# View application sync status
argocd app list
```

**Via kubectl:**
```bash
# Get all applications
kubectl get applications -n argocd

# Describe specific application
kubectl describe application <app-name> -n argocd

# Check application sync status
kubectl get application <app-name> -n argocd -o jsonpath='{.status.sync.status}'
```

### Step 3: Manual Sync (If Needed)

If applications don't sync automatically, manually trigger sync:

**Via UI:**
- Click "Sync" button on the application

**Via CLI:**
```bash
argocd app sync <application-name>
```

**Via kubectl:**
```bash
# Annotate application to trigger sync
kubectl patch application <app-name> -n argocd \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"master"}}}' \
  --type merge
```

### Step 4: Troubleshoot Failed Applications

If an application fails to sync:

1. **Check Application Status:**
```bash
kubectl describe application <app-name> -n argocd
```

2. **Check Pod Status:**
```bash
kubectl get pods -n <target-namespace>
kubectl describe pod <pod-name> -n <target-namespace>
kubectl logs <pod-name> -n <target-namespace>
```

3. **Check Events:**
```bash
kubectl get events -n <target-namespace> --sort-by='.lastTimestamp'
```

4. **Common Issues:**
   - **Repository Access**: Ensure ArgoCD can access the Git repository
   - **Helm Chart Issues**: Verify Helm chart repositories are accessible
   - **Resource Quotas**: Check if resource quotas are limiting deployments
   - **Storage**: Ensure storage classes are available
   - **Dependencies**: Some applications depend on others (check sync waves)

---

## Verification Steps

### Step 1: Verify Namespaces

```bash
kubectl get namespaces

# Expected namespaces:
# - argocd
# - kafka
# - external-secrets
# - monitoring
# - default (with applications)
```

### Step 2: Verify Core Components

**External Secrets Operator:**
```bash
kubectl get pods -n external-secrets
kubectl get externalsecrets -A
```

**Strimzi Operator:**
```bash
kubectl get pods -n kafka
kubectl get kafka -n kafka
```

**Kafka Cluster:**
```bash
kubectl get kafka -n kafka
kubectl get pods -n kafka | grep kafka
# Wait for all Kafka pods to be Running (3 brokers typically)
```

**Schema Registry:**
```bash
kubectl get pods -n kafka | grep schema-registry
kubectl get svc -n kafka | grep schema-registry
```

**Kafka Connect:**
```bash
kubectl get pods | grep kafka-connect
kubectl get svc | grep kafka-connect
```

### Step 3: Verify Monitoring Stack

```bash
# Prometheus
kubectl get pods -n monitoring | grep prometheus

# Grafana (if included)
kubectl get pods -n monitoring | grep grafana

# Access Grafana (if exposed)
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Access at: http://localhost:3000
# Default username: admin
# Password: (check secret or values file)
```

### Step 4: Verify Kafka Connectors

```bash
kubectl get kafkaconnectors -A
kubectl get pods | grep connector
```

### Step 5: Test Kafka Connectivity

```bash
# Get Kafka bootstrap servers
kubectl get kafka -n kafka -o jsonpath='{.items[0].status.listeners[0].bootstrapServers}'

# Test with kafka-console-producer/consumer (if available)
# Or use kubectl exec into a Kafka pod
```

### Step 6: Verify Storage

```bash
# Check persistent volumes
kubectl get pv
kubectl get pvc -A

# Verify storage classes
kubectl get storageclass
```

---

## Troubleshooting

### Issue: ArgoCD Cannot Access Git Repository

**Symptoms:**
- Applications show "Unknown" or "Error" status
- Repository connection errors in ArgoCD UI

**Solutions:**
1. Verify SSH key is configured in ArgoCD
2. Test repository access:
```bash
kubectl exec -it deployment/argocd-repo-server -n argocd -- git ls-remote git@github.com:moneYOUnion/dataops-dms.git
```
3. Check repository credentials in ArgoCD UI: Settings → Repositories

### Issue: Helm Chart Installation Fails

**Symptoms:**
- Application stuck in "Progressing" or "Error" state
- Helm chart repository not found

**Solutions:**
1. Verify Helm repositories are accessible:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update
```

2. Check if ArgoCD can access these repositories (may need network policies)

### Issue: Kafka Pods Not Starting

**Symptoms:**
- Kafka pods in Pending or CrashLoopBackOff state
- Storage issues

**Solutions:**
1. Check storage classes:
```bash
kubectl get storageclass
kubectl get pvc -n kafka
```

2. Check resource quotas:
```bash
kubectl describe quota -n kafka
```

3. Check node resources:
```bash
kubectl describe nodes
kubectl top nodes
```

4. Review Kafka configuration in the repository

### Issue: External Secrets Not Working

**Symptoms:**
- ExternalSecret resources not syncing
- Secrets not created in target namespaces

**Solutions:**
1. Verify External Secrets Operator is running:
```bash
kubectl get pods -n external-secrets
```

2. Check ExternalSecret status:
```bash
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>
```

3. Verify AWS Secrets Manager access (if using AWS):
   - Check IAM roles and policies
   - Verify secrets exist in AWS Secrets Manager

### Issue: Cluster Autoscaler Not Working

**Symptoms:**
- Nodes not scaling up/down
- Pods stuck in Pending state

**Solutions:**
1. Verify cluster autoscaler pod is running:
```bash
kubectl get pods -n monitoring | grep cluster-autoscaler
```

2. Check autoscaler logs:
```bash
kubectl logs -n monitoring deployment/cluster-autoscaler
```

3. Verify IAM permissions for autoscaler
4. Check node group autoscaling is enabled in Terraform

### Issue: Monitoring Stack Not Accessible

**Symptoms:**
- Cannot access Grafana/Prometheus
- Services not exposed

**Solutions:**
1. Check service types:
```bash
kubectl get svc -n monitoring
```

2. Use port-forward for local access:
```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090
```

3. Configure Ingress for external access (requires AWS Load Balancer Controller)

### General Debugging Commands

```bash
# Check all ArgoCD applications
kubectl get applications -n argocd -o wide

# Check application details
kubectl describe application <app-name> -n argocd

# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Check ArgoCD repo server logs
kubectl logs -n argocd deployment/argocd-repo-server

# Check all pods across namespaces
kubectl get pods -A

# Check events across namespaces
kubectl get events -A --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

---

## Post-Deployment Checklist

- [ ] All namespaces created
- [ ] External Secrets Operator running
- [ ] Secrets created in target namespaces
- [ ] Storage classes available
- [ ] Strimzi Operator running
- [ ] Kafka cluster healthy (all brokers Running)
- [ ] Schema Registry accessible
- [ ] Kafka Connect deployed
- [ ] Schema topics created
- [ ] Kafka connectors deployed and running
- [ ] Monitoring stack operational
- [ ] Prometheus scraping metrics
- [ ] Grafana accessible (if configured)
- [ ] Cluster autoscaler running
- [ ] All ArgoCD applications in "Synced" and "Healthy" state
- [ ] Persistent volumes created and bound
- [ ] Network policies configured (if required)
- [ ] Ingress resources working (if configured)

---

## Next Steps

After successful deployment:

1. **Configure Monitoring Dashboards**: Set up Grafana dashboards for Kafka, applications
2. **Set Up Alerts**: Configure Prometheus alerts for critical metrics
3. **Configure Backup**: Set up backup strategies for Kafka data
4. **Security Hardening**: Review and apply security best practices
5. **Performance Tuning**: Optimize Kafka, monitoring, and application configurations
6. **Documentation**: Document environment-specific configurations

---

## Additional Resources

- **ArgoCD Documentation**: https://argo-cd.readthedocs.io/
- **Strimzi Kafka Operator**: https://strimzi.io/
- **External Secrets Operator**: https://external-secrets.io/
- **Kube-Prometheus-Stack**: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- **AWS EKS Best Practices**: https://aws.github.io/aws-eks-best-practices/

---

## Support

For issues or questions:
1. Check application logs and events
2. Review ArgoCD application status
3. Consult component-specific documentation
4. Review troubleshooting section above
