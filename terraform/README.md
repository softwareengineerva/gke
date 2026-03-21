# GKE Cluster Terraform Configuration

This Terraform configuration creates a complete Google Kubernetes Engine (GKE) cluster infrastructure with the following components:

## Author
**Jian Ouyang** (jian.ouyang@sapns2.com)

## Components Created

### Networking
- **VPC**: A custom VPC with configurable CIDR block (default: 10.0.0.0/16)
- **Subnets**:
  - 3 Public subnets across 3 availability zones
  - 3 Private subnets across 3 availability zones
  - Properly tagged for GKE load balancer integration
- **Internet Gateway**: For public subnet internet access
- **NAT Gateways**: One per AZ (or single if configured) for private subnet outbound access
- **Route Tables**: Separate route tables for public and private subnets

### Security
- **Security Groups**:
  - GKE cluster control plane security group
  - GKE worker node security group
  - Properly configured ingress/egress rules for cluster-node communication

### IAM
- **GKE Cluster Role**: With required policies (GoogleGKEClusterPolicy, GoogleGKEVPCResourceController)
- **GKE Node Role**: With required policies (GoogleGKEWorkerNodePolicy, GoogleGKE_CNI_Policy, GoogleEC2ContainerRegistryReadOnly)
- **VPC CNI Role**: For IRSA (IAM Roles for Service Accounts) with VPC CNI addon
- **OIDC Provider**: For pod-level IAM permissions

### GKE Cluster
- **GKE Control Plane**: Managed Kubernetes control plane (v1.34 by default)
- **GKE Addons**:
  - VPC CNI (with IRSA support)
  - CoreDNS
  - kube-proxy
  - GKE Pod Identity Agent
- **GKE Managed Node Group**:
  - AL2023-based nodes
  - Auto-scaling configuration
  - Deployed in private subnets

## Resource Naming

All resources use the prefix `concur-test` by default, as specified in the requirements.

## Prerequisites

- Google Cloud SDK configured with appropriate credentials
- Terraform >= 1.0
- GCP Provider >= 5.0

## Usage

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Review the Plan

```bash
terraform plan
```

### Apply the Configuration

**Note**: Do not run `terraform apply` without permission.

```bash
terraform apply
```

### Configure kubectl

After the cluster is created, configure kubectl to access the cluster:

```bash
gcloud container clusters get-credentials concur-test-gke --region us-east1
```

Or use the output command:

```bash
terraform output -raw configure_kubectl | bash
```

### Verify Cluster Access

```bash
kubectl get nodes
kubectl get pods -A
```

## Customization

### Variables

You can customize the deployment by modifying variables in `variables.tf` or creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars example
gcp_region               = "us-west2"
cluster_name            = "my-custom-gke"
cluster_version         = "1.34"
node_group_instance_types = ["t3.medium", "t3.large"]
node_group_desired_size  = 3
```

### Key Variables

- `gcp_region`: GCP region for deployment (default: us-east1)
- `cluster_name`: Name of the GKE cluster (default: concur-test-gke)
- `cluster_version`: Kubernetes version (default: 1.34)
- `vpc_cidr`: VPC CIDR block (default: 10.0.0.0/16)
- `node_group_instance_types`: EC2 instance types for worker nodes (default: ["t3.medium"])
- `node_group_min_size`: Minimum number of nodes (default: 1)
- `node_group_max_size`: Maximum number of nodes (default: 3)
- `node_group_desired_size`: Desired number of nodes (default: 2)

## Outputs

The configuration provides useful outputs including:

- VPC and subnet IDs
- GKE cluster endpoint and certificate
- kubectl configuration command
- IAM role ARNs
- Security group IDs

View all outputs:

```bash
terraform output
```

## Clean Up

To destroy all resources:

```bash
terraform destroy
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           GCP VPC (10.0.0.0/16)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Public Subnet│  │ Public Subnet│  │ Public Subnet│         │
│  │  us-east1a  │  │  us-east1b  │  │  us-east1c  │         │
│  │ 10.0.101.0/24│  │ 10.0.102.0/24│  │ 10.0.103.0/24│         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │ NAT GW          │ NAT GW          │ NAT GW          │
│         │                 │                 │                 │
│  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐         │
│  │Private Subnet│  │Private Subnet│  │Private Subnet│         │
│  │  us-east1a  │  │  us-east1b  │  │  us-east1c  │         │
│  │  10.0.1.0/24 │  │  10.0.2.0/24 │  │  10.0.3.0/24 │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│         │                 │                 │                 │
│         └─────────────────┴─────────────────┘                 │
│                           │                                   │
│                  ┌────────┴─────────┐                         │
│                  │  GKE Node Group  │                         │
│                  │   (AL2023 Nodes) │                         │
│                  └──────────────────┘                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴──────────┐
                    │  GKE Control Plane │
                    │    (Managed)       │
                    └────────────────────┘
```

## Notes

- The GKE cluster is configured with both public and private endpoint access
- Worker nodes are deployed in private subnets for security
- NAT Gateways enable outbound internet access for private subnets
- All resources are tagged with the project name "concur-test"
- The configuration follows GCP GKE best practices
- Cluster logging is enabled for audit and troubleshooting

## Support

For issues or questions, please contact the author.
