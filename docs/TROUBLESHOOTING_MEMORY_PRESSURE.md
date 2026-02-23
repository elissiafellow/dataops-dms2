# Troubleshooting: Memory Pressure and Node Termination

## Incident Summary

**Date:** [Date of incident]  
**Cluster:** demo-env  
**Issue:** Node became NotReady due to memory pressure, causing pod evictions and potential cluster instability.

## Symptoms Observed

1. **Node Status:** `ip-10-30-2-183.eu-central-1.compute.internal` went to `NotReady` state
2. **Events Timeline:**
   - `EvictionThresholdMet` - Memory pressure detected
   - `NodeHasInsufficientMemory` - Node ran out of memory
   - Pods were evicted to reclaim memory
   - Node transitioned to `NotReady` after 34 minutes

## Root Cause Analysis

### Primary Cause: Insufficient Node Resources

The cluster is running a **production-grade Kafka setup** with:
- **3 Kafka Controllers** (each requesting 1GB memory, limit 1.5GB)
- **3 Kafka Brokers** (each requesting 3GB memory, limit 10GB)
- **Monitoring stack** (Prometheus, Grafana, etc.)
- **Kafka Connect**
- **Other supporting services**

**Total Memory Requirements:**
- Controllers: 3 × 1.5GB = 4.5GB
- Brokers: 3 × 10GB = 30GB
- System + Monitoring: ~5-10GB
- **Total: ~40-45GB minimum**

**Node Capacity:** The nodes in the cluster likely have insufficient memory to handle this workload, causing:
1. Memory pressure on nodes
2. Kubernetes evicting pods to free memory
3. Node becoming unhealthy
4. Cluster autoscaler potentially trying to replace the node

### Secondary Factors

1. **Cluster Autoscaler Behavior:** If configured, may attempt to scale down unhealthy nodes
2. **Resource Limits:** High memory limits (10GB per broker) may cause scheduling issues
3. **Replication Factor:** Production settings (replication factor 3, min ISR 2) require multiple nodes

## Investigation Steps

### 1. Check Node Status
```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

### 2. Check Memory Usage
```bash
kubectl top nodes
kubectl top pods --all-namespaces
```

### 3. Check Pod Evictions
```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i evict
kubectl get pods --all-namespaces | grep -E "Evicted|Terminating"
```

### 4. Check Cluster Autoscaler
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=cluster-autoscaler
kubectl logs -n monitoring -l app.kubernetes.io/name=cluster-autoscaler --tail=100
```

### 5. Check AWS Auto Scaling Group
```bash
aws autoscaling describe-auto-scaling-groups --region eu-central-1
aws autoscaling describe-scaling-activities --region eu-central-1 --max-records 10
```

### 6. Check Node Instance Type
```bash
aws ec2 describe-instances --region eu-central-1 \
  --filters "Name=private-ip-address,Values=<node-ip>" \
  --query "Instances[*].[InstanceType,InstanceLifecycle]"
```

## Solutions

### Immediate Actions

1. **Pause Cluster Autoscaler** (if causing issues):
   ```bash
   kubectl scale deployment cluster-autoscaler -n monitoring --replicas=0
   ```

2. **Cordon Unhealthy Node** (prevent new pods):
   ```bash
   kubectl cordon <node-name>
   ```

3. **Check if Node Can Recover**:
   ```bash
   kubectl get node <node-name> -w
   ```

### Short-term Solutions

1. **Reduce Replicas** (for learning/development):
   - Controllers: 3 → 1
   - Brokers: 3 → 1
   - This reduces memory requirements significantly

2. **Reduce Resource Limits**:
   - Broker memory limit: 10GB → 4GB
   - Controller memory limit: 1.5GB → 1GB

3. **Adjust Kafka Configuration**:
   - Replication factor: 3 → 1
   - Min ISR: 2 → 1
   - **Note:** This reduces high availability but acceptable for learning

### Long-term Solutions

1. **Increase Node Instance Size** (Terraform):
   - Use larger instance types (e.g., `m5.xlarge` or `m5.2xlarge`)
   - Ensure nodes have at least 16-32GB RAM

2. **Optimize Resource Requests/Limits**:
   - Right-size based on actual usage
   - Use resource quotas to prevent over-allocation

3. **Add Cluster Autoscaler Protection**:
   ```yaml
   extraArgs:
     scale-down-delay-after-add: 10m
     scale-down-unneeded-time: 10m
     skip-nodes-with-system-pods: true
     nodes-min: 1
   ```

4. **Monitor Resource Usage**:
   - Set up alerts for memory pressure
   - Monitor node capacity vs. requests

## Prevention

### 1. Resource Planning
- Calculate total resource requirements before deployment
- Ensure nodes have sufficient capacity (at least 20% headroom)

### 2. Monitoring
- Set up alerts for:
  - Node memory pressure
  - Pod evictions
  - Node NotReady status

### 3. Testing
- Test resource requirements in a smaller environment first
- Gradually scale up while monitoring

### 4. Documentation
- Document resource requirements for each component
- Keep track of node capacity vs. workload

## Lessons Learned

1. **Production vs. Learning Setup:** Production-grade configurations (3 replicas, high memory) require significant resources
2. **Resource Planning:** Always calculate total resource requirements before deployment
3. **Right-sizing:** Match instance types to workload requirements
4. **Monitoring:** Early detection of memory pressure can prevent node failures

## Related Files

- Kafka Configuration: `kubernetes/production/kafka-raft/kafka-seperate/main/kafka.yaml`
- Cluster Autoscaler: `kubernetes/argocd-helmcharts/values/cluster-autoscaler-values.yaml`
- Monitoring: `kubernetes/production/monitoring/`

## References

- [Kubernetes Node Pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
- [Strimzi Resource Requirements](https://strimzi.io/docs/operators/latest/deploying.html#proc-resource-planning-str)
- [Cluster Autoscaler Best Practices](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
