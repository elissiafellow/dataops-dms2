# Quick Start Checklist - DataOps DMS Cluster Deployment

Use this checklist to track your deployment progress.

## Prerequisites ✅

- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] kubectl installed (v1.28+)
- [ ] Terraform installed (v1.5+)
- [ ] Helm installed (v3.12+)
- [ ] ArgoCD CLI installed (optional)
- [ ] SSH access to `git@github.com:moneYOUnion/dataops-dms.git`
- [ ] AWS account with EKS permissions
- [ ] Sufficient AWS quota for EC2 instances

## Phase 1: Infrastructure Setup

- [ ] Navigate to `demo-env/infra/`
- [ ] Review/update `terraform.tfvars`:
  - [ ] Set `environment = "dataops-dms"`
  - [ ] Set appropriate `eks_instance_type` (t3.medium+ recommended)
  - [ ] Set `eks_min_size = 2` (for HA)
  - [ ] Set `eks_desired_size = 2`
- [ ] Run `terraform init`
- [ ] Run `terraform plan` (review output)
- [ ] Run `terraform apply` (wait 15-20 minutes)
- [ ] Save Terraform outputs (cluster name, VPC ID)
- [ ] Configure kubectl: `aws eks update-kubeconfig --name <cluster-name> --region <region>`
- [ ] Verify cluster access: `kubectl get nodes` (should show 2+ nodes)

## Phase 2: Cluster Configuration

- [ ] Install AWS Load Balancer Controller:
  ```bash
  helm repo add eks https://aws.github.io/eks-charts
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=<cluster-name>
  ```
- [ ] Verify Load Balancer Controller: `kubectl get deployment -n kube-system aws-load-balancer-controller`
- [ ] Check storage classes: `kubectl get storageclass`

## Phase 3: ArgoCD Installation

- [ ] Create namespace: `kubectl create namespace argocd`
- [ ] Install ArgoCD: `kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
- [ ] Wait for ArgoCD to be ready: `kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd`
- [ ] Get admin password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- [ ] Port forward ArgoCD: `kubectl port-forward svc/argocd-server -n argocd 8080:443`
- [ ] Access ArgoCD UI: https://localhost:8080 (username: admin)
- [ ] Configure Git repository access in ArgoCD UI (Settings → Repositories)

## Phase 4: Application Deployment

- [ ] Apply app-of-apps: `kubectl apply -f dataops-dms2/app-of-apps.yaml`
- [ ] Verify application created: `kubectl get application -n argocd`
- [ ] Monitor deployment in ArgoCD UI or CLI

### Application Sync Wave Verification

- [ ] **Wave 1**: Namespaces created (`kubectl get namespaces`)
- [ ] **Wave 2**: External Secrets Operator running (`kubectl get pods -n external-secrets`)
- [ ] **Wave 3**: Secrets created (`kubectl get externalsecrets -A`)
- [ ] **Wave 4**: Storage classes available (`kubectl get storageclass`)
- [ ] **Wave 5**: Strimzi Operator running (`kubectl get pods -n kafka`)
- [ ] **Wave 6**: Kafka cluster healthy (`kubectl get kafka -n kafka`, `kubectl get pods -n kafka`)
- [ ] **Wave 7**: Schema Registry running (`kubectl get pods -n kafka | grep schema-registry`)
- [ ] **Wave 8**: Kafka Connect running (`kubectl get pods | grep kafka-connect`)
- [ ] **Wave 9**: Schema topics created (`kubectl get kafkatopics -A`)
- [ ] **Wave 10**: Monitoring addons deployed
- [ ] **Wave 11**: Prometheus stack running (`kubectl get pods -n monitoring`)
- [ ] **Wave 12**: Cluster autoscaler running (`kubectl get pods -n monitoring | grep cluster-autoscaler`)
- [ ] **Wave 13**: Kafka connectors deployed (`kubectl get kafkaconnectors -A`)

## Phase 5: Verification

- [ ] All namespaces exist: `kubectl get namespaces`
- [ ] All ArgoCD applications show "Synced" and "Healthy": `kubectl get applications -n argocd`
- [ ] Kafka cluster has 3 brokers running: `kubectl get pods -n kafka | grep kafka`
- [ ] Schema Registry accessible: `kubectl get svc -n kafka | grep schema-registry`
- [ ] Kafka Connect accessible: `kubectl get svc | grep kafka-connect`
- [ ] Monitoring stack operational: `kubectl get pods -n monitoring`
- [ ] Persistent volumes created: `kubectl get pv`
- [ ] No pods in Error/CrashLoopBackOff: `kubectl get pods -A | grep -E "Error|CrashLoopBackOff"`

## Phase 6: Access & Testing

- [ ] Access Grafana (if configured): `kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80`
- [ ] Access Prometheus: `kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090`
- [ ] Test Kafka connectivity (get bootstrap servers from Kafka resource)
- [ ] Verify connectors are running: `kubectl get pods | grep connector`
- [ ] Check application logs for errors: `kubectl logs -n <namespace> <pod-name>`

## Troubleshooting (If Issues Occur)

- [ ] Check ArgoCD application status: `kubectl describe application <app-name> -n argocd`
- [ ] Check pod status: `kubectl get pods -A`
- [ ] Check events: `kubectl get events -A --sort-by='.lastTimestamp'`
- [ ] Check ArgoCD logs: `kubectl logs -n argocd deployment/argocd-server`
- [ ] Verify repository access: Test Git access from ArgoCD repo server
- [ ] Check resource quotas: `kubectl describe quota -A`
- [ ] Check node resources: `kubectl top nodes`

## Post-Deployment

- [ ] Document cluster endpoints and access methods
- [ ] Configure monitoring dashboards
- [ ] Set up alerts
- [ ] Review security settings
- [ ] Plan backup strategy
- [ ] Document any custom configurations

---

## Quick Commands Reference

```bash
# Cluster access
aws eks update-kubeconfig --name <cluster-name> --region <region>
kubectl get nodes

# ArgoCD access
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Application status
kubectl get applications -n argocd
argocd app list  # if CLI installed

# Component status
kubectl get pods -A
kubectl get kafka -n kafka
kubectl get pods -n kafka
kubectl get pods -n monitoring

# Troubleshooting
kubectl describe application <app-name> -n argocd
kubectl logs -n <namespace> <pod-name>
kubectl get events -A --sort-by='.lastTimestamp'
```

---

**Estimated Total Time**: 30-45 minutes (depending on cluster creation time)

**Critical Path**: Infrastructure → ArgoCD → App-of-Apps → Monitor Sync Waves
