# Terraform Infrastructure Explained - DataOps DMS Kafka Cluster

This document provides a detailed explanation of the Terraform infrastructure in `environments/production/` and its modules. This is a **production-grade** setup that can be significantly simplified for demos.

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Module Breakdown](#module-breakdown)
4. [Complexity Analysis](#complexity-analysis)
5. [Simplification Recommendations for Demo](#simplification-recommendations-for-demo)
6. [Cost Implications](#cost-implications)

---

## Overview

The infrastructure creates a **production-ready EKS cluster** specifically designed for Kafka workloads with:
- **3 separate node groups** for workload isolation
- **Bastion host** for secure access
- **ECR repository** for custom Kafka Connect images
- **Outpost support** (AWS Outpost integration)
- **Multiple EKS addons** for production features
- **IAM roles** for service accounts (IRSA)
- **S3 backend** for Terraform state management

**Location**: `dataops-dms2/environments/production/`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Account                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  VPC (10.240.0.0/16)                                      │ │
│  │  ├── Public Subnets (2 AZs)                               │ │
│  │  │   ├── eu-central-1a: 10.240.1.0/24                    │ │
│  │  │   └── eu-central-1b: 10.240.2.0/24                    │ │
│  │  ├── Private Subnets (2 AZs)                              │ │
│  │  │   ├── eu-central-1a: 10.240.3.0/24                    │ │
│  │  │   └── eu-central-1b: 10.240.4.0/24                    │ │
│  │  └── Outpost Private Subnets (2)                           │ │
│  │      ├── 10.240.100.0/24                                  │ │
│  │      └── 10.240.101.0/24                                  │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │  EKS Cluster: production-kafka-cluster              │ │ │
│  │  │  Version: 1.31                                     │ │ │
│  │  │  Endpoint: Private only (endpoint_public_access=false)│ │
│  │  │                                                    │ │ │
│  │  │  Node Groups:                                      │ │ │
│  │  │  ├── kafka-cluster (3-4 nodes, m5.xlarge)         │ │ │
│  │  │  ├── kafka-connect (2 nodes, m5.xlarge)           │ │ │
│  │  │  └── admin-tools (1-2 nodes, m5.large)             │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │  Bastion Host (t3.micro)                             │ │ │
│  │  │  - SSH access from allowed IPs                        │ │ │
│  │  │  - EKS admin access                                   │ │ │
│  │  │  - Pre-installed: kubectl, k9s, terraform, docker     │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │  ECR Repository: kafka-cluster                        │ │ │
│  │  │  - Stores Kafka Connect custom image                  │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  Internet Gateway ──┐                                      │ │
│  │  NAT Gateway ───────┘                                      │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  S3 Backend: moneyfellows-prod-dms-statefiles            │ │
│  │  - Terraform state storage                                │ │
│  │  - KMS encryption                                          │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Breakdown

### 1. VPC Module (`modules/vpc/`)

**Purpose**: Creates the network foundation for the cluster.

**Resources Created**:
- **VPC**: `10.240.0.0/16` with DNS support enabled
- **Internet Gateway**: For public subnet internet access
- **NAT Gateway**: Single NAT gateway in public subnet[1] for private subnet internet access
- **Public Subnets**: 2 subnets across 2 AZs (10.240.1.0/24, 10.240.2.0/24)
- **Private Subnets**: 2 subnets across 2 AZs (10.240.3.0/24, 10.240.4.0/24)
- **Outpost Private Subnets**: 2 subnets on AWS Outpost (10.240.100.0/24, 10.240.101.0/24)
- **Route Tables**: Public and private route tables
- **Security Group**: EKS security group allowing all traffic within VPC

**Key Features**:
- Kubernetes-specific tags on subnets for ALB integration
- Outpost support (on-premises AWS infrastructure)
- Single NAT gateway (cost optimization)

**For Demo**: Can be simplified to basic VPC with 2 public + 2 private subnets, no Outpost.

---

### 2. EKS Module (`modules/eks/`)

**Purpose**: Creates the EKS cluster with multiple node groups for workload isolation.

#### 2.1 EKS Cluster

**Configuration**:
- **Name**: `production-kafka-cluster` (from `var.env-var.eks_name`)
- **Version**: 1.31 (latest)
- **Endpoint Access**: 
  - Private: `true` (only accessible from within VPC)
  - Public: `false` (no public API endpoint)
- **Authentication**: API mode with bootstrap cluster creator admin permissions
- **Logging**: All cluster log types enabled (api, audit, authenticator, controllerManager, scheduler)

**Why Private Endpoint Only?**
- Security: Cluster API not exposed to internet
- Access via: Bastion host or VPN
- Production best practice

#### 2.2 Node Groups (3 Separate Groups)

**A. Kafka Cluster Node Group**
```hcl
name: "kafka-cluster"
instance_type: m5.xlarge (4 vCPU, 16GB RAM)
min_size: 3
max_size: 4
desired_size: 3
subnet: private_subnet_ids[0] (single subnet)
node_labels: kafka-cluster-role=kafka-cluster
storage: 20GB gp2 per node
```

**Purpose**: Dedicated nodes for Kafka brokers
- High memory for Kafka's JVM
- Multiple nodes for replication (min 3 for HA)
- Isolated from other workloads

**B. Kafka Connect Node Group**
```hcl
name: "kafka-connect"
instance_type: m5.xlarge (4 vCPU, 16GB RAM)
min_size: 2
max_size: 2
desired_size: 2
subnet: private_subnet_ids[0]
node_labels: kafka-cluster-role=kafka-connect
storage: 20GB gp2 per node
```

**Purpose**: Dedicated nodes for Kafka Connect workers
- Separate from Kafka brokers for resource isolation
- Fixed size (2 nodes) for predictable performance

**C. Admin Tools Node Group**
```hcl
name: "admin-tools"
instance_type: m5.large (2 vCPU, 8GB RAM)
min_size: 1
max_size: 2
desired_size: 1
subnet: private_subnet_ids[0]
node_labels: kafka-cluster-role=admin-tools
storage: 20GB gp2 per node
```

**Purpose**: Nodes for monitoring, ArgoCD, and other admin tools
- Smaller instances (cost optimization)
- Can scale to 2 if needed

**Why Separate Node Groups?**
1. **Resource Isolation**: Kafka brokers don't compete with Connect workers
2. **Cost Optimization**: Right-size instances for each workload
3. **Scaling**: Independent scaling per workload type
4. **Node Affinity**: Pods can be scheduled on specific node groups using labels

#### 2.3 EKS Addons

The module installs several EKS addons:

1. **CoreDNS**: DNS resolution for pods
2. **VPC CNI**: Networking (required)
3. **kube-proxy**: Network proxy (required)
4. **aws-ebs-csi-driver**: EBS volume provisioning for persistent volumes
5. **snapshot-controller**: Volume snapshot management
6. **amazon-cloudwatch-observability**: CloudWatch integration
7. **eks-pod-identity-agent**: Pod identity (IRSA alternative)

**For Demo**: Only CoreDNS, VPC CNI, kube-proxy, and EBS CSI driver are essential.

#### 2.4 IAM Roles and Policies

**A. Cluster Autoscaler IAM Role**
- IRSA (IAM Roles for Service Accounts) setup
- Allows cluster autoscaler to modify ASG sizes
- Service account: `monitoring:cluster-autoscaler`

**B. External Secrets IAM Role**
- IRSA for External Secrets Operator
- Permissions to read/write AWS Secrets Manager
- Service account: `external-secrets:external-secrets`

**C. Node Group IAM Roles**
- Standard EKS worker node policies
- EBS CSI driver policy
- CloudWatch agent policy

---

### 3. Bastion Module (`modules/bastion/`)

**Purpose**: Secure jump host for accessing the private EKS cluster.

**Resources**:
- **EC2 Instance**: t3.micro in public subnet
- **Security Group**: SSH access from specific IP ranges only
- **IAM Role**: EKS admin access + SSM access
- **SSH Key**: Auto-generated and stored in S3
- **Pre-installed Tools**: kubectl, k9s, terraform, docker, AWS CLI

**Configuration**:
```hcl
instance_type: t3.micro
ami: ami-0e54671bdf3c8ed8d (Amazon Linux 2023)
allowed_ips: [
  "41.187.108.120/29",
  "41.33.74.216/29",
  "41.187.93.208/29",
  "41.33.73.8/29",
  "35.235.240.0/20",
  "154.178.35.29/32"
]
```

**User Data Script**:
- Installs: kubectl, k9s, terraform, docker, AWS CLI v2
- Sets up SSM agent
- Configures Docker

**Why Needed?**
- EKS endpoint is private-only
- Need bastion to access cluster from outside VPC
- Provides secure access point

**For Demo**: Can be optional if you enable public endpoint or use VPN.

---

### 4. EKS-Bastion Association Module (`modules/eks-bastion-association/`)

**Purpose**: Grants the bastion host IAM role access to the EKS cluster.

**Resources**:
- IAM role for bastion with EKS admin policy
- EKS access entry for the bastion role
- EKS access policy association (cluster admin)

**How It Works**:
1. Creates IAM role with EKS admin permissions
2. Creates EKS access entry linking IAM role to cluster
3. Associates cluster admin policy with the role
4. Bastion can use `aws eks update-kubeconfig` to access cluster

---

### 5. ECR Module (`modules/ecr/`)

**Purpose**: Creates ECR repository and builds/pushes Kafka Connect custom image.

**Resources**:
- ECR repository: `kafka-cluster`
- Docker image build and push (via null_resource)

**Process**:
1. Creates ECR repository with image scanning enabled
2. Builds Docker image from `kafka-connect-cluster/dockerfile`
3. Authenticates to ECR
4. Tags and pushes image to ECR
5. Image available for Kafka Connect deployment

**For Demo**: Can be skipped if using standard Kafka Connect image.

---

### 6. VPC Peering Module (`modules/vpc-peering/` - Commented Out)

**Purpose**: Would connect this VPC to another VPC (e.g., RDS VPC).

**Status**: Currently commented out in `main.tf`

**Why Commented?**
- Not needed if RDS is in same VPC or publicly accessible
- Can be enabled when needed

---

## Complexity Analysis

### Production Features (Current Setup)

| Feature | Complexity | Cost Impact | Demo Needed? |
|---------|-----------|-------------|--------------|
| 3 Separate Node Groups | High | High | No - Use 1 node group |
| Outpost Subnets | High | Very High | No |
| Private EKS Endpoint | Medium | Low | Optional |
| Bastion Host | Medium | Low | Optional |
| ECR Repository | Low | Low | Optional |
| Multiple EKS Addons | Medium | Low | Partial - Core only |
| IRSA for Services | Medium | Low | Yes - For External Secrets |
| S3 Backend | Low | Low | Yes |
| VPC Peering | Medium | Low | No |

### Current Resource Count

- **EC2 Instances**: 6-8 nodes (3+2+1) + 1 bastion = **7-9 instances**
- **Instance Types**: m5.xlarge (5), m5.large (1), t3.micro (1)
- **Estimated Monthly Cost**: ~$500-700/month (depending on usage)

---

## Simplification Recommendations for Demo

### Option 1: Minimal Demo Setup (Recommended)

**Changes**:
1. **Single Node Group**: Combine all workloads into one node group = agree
2. **Smaller Instances**: Use t3.medium or t3.large instead of m5.xlarge = agree
3. **Fewer Nodes**: 2-3 nodes total instead of 6-8 = maybe less if possible 
4. **Remove Outpost**: No outpost subnets = yes
5. **Public EKS Endpoint**: Enable public endpoint (or use port-forward) = public endpoint
6. **Optional Bastion**: Remove or make optional =remove
7. **Remove ECR**: Use public images or skip custom Kafka Connect =first we will use public image, understand the commonly used then why did he chose to make custom image
8. **Core Addons Only**: CoreDNS, VPC CNI, kube-proxy, EBS CSI driver 

**Estimated Cost**: ~$100-150/month

**Modified `terraform.tfvars`**:
```hcl
# Simplified for demo
env              = "demo"
eks_name         = "kafka-demo"
eks_version      = "1.28"  # Use stable version
vpc_cidr         = "10.30.0.0/16"
public_subnets   = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnets  = ["10.30.3.0/24", "10.30.4.0/24"]
outpost_private_subnets = []  # Remove outpost
azs              = ["eu-central-1a", "eu-central-1b"]
region           = "eu-central-1"

# Remove bastion (or make optional)
# bastion_ami = ""
# bastion_key_name = ""
# allowed_ips = []
```

**Modified EKS Module**:
- Single node group with t3.medium or t3.large
- 2-3 nodes total
- Remove node labels or use single label

### Option 2: Use Existing `demo-env/infra/` (Simplest) ## i also recommend this so it's general env we can use for diff demos -- but regardless of this terraform we will need to also create 2 dbs to test the setup on them we might do that in dataops-dms2/db_infra/main.tf

**Recommendation**: Use the simpler Terraform in `demo-env/infra/` which already has:
- Basic VPC setup
- Single EKS cluster
- Simple node group
- No bastion
- No outpost
- Public endpoint enabled

**Then**: Apply ArgoCD applications from `dataops-dms2/argocd/`

**Pros**:
- Already simplified
- Works for demos
- Lower cost
- Faster to deploy

**Cons**:
- Less production-like
- No workload isolation

---

## Cost Implications

### Current Production Setup (Monthly Estimate)

| Resource | Count | Instance Type | Cost/Month |
|----------|-------|---------------|------------|
| Kafka Cluster Nodes | 3 | m5.xlarge | ~$300 |
| Kafka Connect Nodes | 2 | m5.xlarge | ~$200 |
| Admin Tools Nodes | 1 | m5.large | ~$70 |
| Bastion | 1 | t3.micro | ~$8 |
| NAT Gateway | 1 | - | ~$32 |
| EBS Volumes | 6 | 20GB gp2 | ~$12 |
| **Total** | | | **~$622/month** |

### Simplified Demo Setup (Monthly Estimate)

| Resource | Count | Instance Type | Cost/Month |
|----------|-------|---------------|------------|
| EKS Nodes | 2-3 | t3.medium | ~$60-90 |
| NAT Gateway | 1 | - | ~$32 |
| EBS Volumes | 2-3 | 20GB gp2 | ~$4-6 |
| **Total** | | | **~$96-128/month** |

**Savings**: ~$500/month (80% reduction)

---

## Key Differences: Production vs Demo

| Aspect | Production (Current) | Demo (Recommended) |
|--------|---------------------|-------------------|
| Node Groups | 3 separate groups | 1 unified group |
| Instance Types | m5.xlarge, m5.large | t3.medium or t3.large |
| Node Count | 6-8 nodes | 2-3 nodes |
| EKS Endpoint | Private only | Public enabled |
| Bastion | Required | Optional |
| Outpost | Yes | No |
| ECR | Custom images | Public images |
| Addons | All production addons | Core addons only |
| Cost | ~$600/month | ~$100/month |

---

## Migration Path: Production → Demo

### Step 1: Create Simplified Version

1. Copy `environments/production/` to `environments/demo/`
2. Modify `terraform.tfvars` with demo values
3. Modify EKS module to use single node group
4. Comment out bastion module (or make optional)
5. Remove outpost subnets
6. Simplify EKS addons

### Step 2: Update Main.tf

```hcl
# Simplified main.tf for demo
module "vpc" {
  # Remove outpost_private_subnets
  outpost_private_subnets = []
}

module "eks" {
  # Use single node group instead of 3
  # Smaller instances
  # Fewer nodes
}

# Comment out or make optional
# module "bastion" { ... }
# module "ecr" { ... }
```

### Step 3: Update Backend

Change S3 backend to demo bucket or use local backend:
```hcl
backend "local" {
  path = "terraform.tfstate"
}
```

---

## Recommendations

### For Demo Environment

1. **Use `demo-env/infra/`** - Already simplified, works well
2. **OR** Create simplified version of `environments/production/` with:
   - Single node group (t3.medium, 2-3 nodes)
   - Public EKS endpoint
   - No bastion (or optional)
   - No outpost
   - Core addons only

### For Production Environment

1. **Keep current setup** - It's well-designed for production
2. **Consider**:
   - Adding more nodes for Kafka cluster (4-5 for better HA)
   - Using larger instances if needed (m5.2xlarge for high throughput)
   - Adding monitoring node group if needed
   - Enabling VPC peering if connecting to other VPCs

---

## Conclusion

The current Terraform setup is **production-grade** with:
- ✅ Workload isolation (3 node groups)
- ✅ Security (private endpoint, bastion)
- ✅ High availability (multiple nodes, multiple AZs)
- ✅ Production features (all addons, IRSA, etc.)

**For demos**, this is **overkill**. Use:
- ✅ Simplified version (single node group, smaller instances)
- ✅ OR use `demo-env/infra/` which is already simplified
- ✅ Estimated 80% cost reduction
- ✅ Faster deployment time
- ✅ Easier to understand and maintain

The ArgoCD applications in `dataops-dms2/argocd/` will work with either setup - they deploy Kubernetes resources, not infrastructure.
