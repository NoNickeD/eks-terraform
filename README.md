# EKS with Terraform
Elastic Kubernetes Service (EKS) with Terraform.

## Prerequisites

1. Create [AWS account](https://console.aws.amazon.com)
2. Install [Amazon CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
3. Install [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
4. Install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)

## Creating credentials

Although the objective is to employ Terraform for all infrastructure-related tasks, some AWS-specific items are necessary. Specifically, we need to create an access key ID and a secret access key. To do this, please open the AWS Console. If you're new to AWS, register for an account otherwise, log in.

Next, navigate to My Security Credentials, where you'll find various options for generating credentials. Locate and expand the Access keys (access key ID and secret access key) section, then click on the Create New Access Key button. A message will confirm the successful creation of your access key. Make sure not to close this popup by clicking the Close button, as the access key information will be required and is only shown at this time.

```bash
# Kindly substitute the initial instance of [...] with the access key ID, and the subsequent instance with the secret access key in the upcoming commands.

export AWS_ACCESS_KEY_ID=[...]
export AWS_SECRET_ACCESS_KEY=[...]

# Create a file awscred with credentials
echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID 
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY 
export AWS_DEFAULT_REGION=eu-central-1" \
| tee awscred

.
├── awscred

# Importing enviroment variables from awscred file.
source awscred
```

## AWS Provider 

For more information please visit and read the official [documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs).

For the first initialization we need the following files/configs:

```bash
.
├── awscred
├── provider.tf
└── variables.tf
```
### provider.tf

- provider "aws": This line defines the AWS provider, which allows Terraform to interact with AWS services to create and manage resources.
- region = var.region: This line sets the AWS region where the resources will be created and managed. The value for the region is taken from a variable named region.


### variables.tf

- region: This variable represents the AWS region where the resources will be created and managed. It has a default value of "eu-central-1" and is of type string.
- cluster_name: This variable represents the name of the EKS (Elastic Kubernetes Service) cluster. It has a default value of "eks-test" and is of type string.
- k8s_version: This variable represents the Kubernetes version to be used in the EKS cluster. It has no default value and is of type string.
- release_version: This variable represents the release version of the EKS cluster. It has no default value and is of type string.
- min_node_count: This variable represents the minimum number of nodes in the EKS cluster's worker node group. It has a default value of 3 and is of type number.
- max_node_count: This variable represents the maximum number of nodes in the EKS cluster's worker node group. It has a default value of 9 and is of type number.
- machine_type: This variable represents the instance type of the worker nodes in the EKS cluster. It has a default value of "t2.small" and is of type string.

Rather than attempting to determine the supported Kubernetes versions in EKS, we will consult the Platform Versions page, which enumerates all presently available options.

```bash
open https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html
```

### AutoScaler

In contrast to other managed Kubernetes services like GKE and AKS, specifying the minimum and maximum number of worker nodes in EKS does not enable the Cluster [Autoscaler](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html#cluster-autoscaler) feature by default. Instead, these values are utilized to create an AWS Autoscaling Group. To achieve automatic scaling based on resource demand, the Cluster Autoscaler must be deployed separately. While this may change in the future, as of May 2020, the Kubernetes Cluster Autoscaler is not an integrated component of EKS.

Initialize the project:

```bash
terraform init
```

Apply the changes:

```bash
terraform apply
```

## Creating the Control Plane

The [aws_eks_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster.html) module can be employed to establish an EKS control plane. Nevertheless, EKS differs from other providers such as GKE and AKS in that it cannot be set up in isolation. Additional resources, including a role ARN, security group, and subnet, are required for its creation. Consequently, these resources may necessitate the creation of further supplementary resources.

```bash
.
├── awscred
├── controlPlane.tf
├── provider.tf
├── variables.tf
```
### controlPlane.tf

- aws_eks_cluster: Creates the EKS control plane with the specified cluster name, role ARN, and Kubernetes version. It also configures the VPC by specifying the security group and subnets.
- aws_iam_role: Creates an IAM role named eks-test-control-plane with the necessary permissions for the EKS control plane.
- aws_iam_role_policy_attachment: Attaches the Amazon EKS Cluster Policy and Amazon EKS Service Policy to the control plane IAM role.
- aws_vpc: Creates a VPC named eks-test with a CIDR block of 10.0.0.0/16. It also tags the VPC to be shared with the specified EKS cluster.
- aws_security_group: Creates a security group named eks-test for cluster communication with worker nodes. The security group is associated with the created VPC and allows all outbound traffic.
- data.aws_availability_zones: Fetches the available AWS availability zones.
- aws_subnet: Creates three subnets for the worker nodes within the created VPC. Each subnet is associated with a different availability zone, has a CIDR block of 10.0.X.0/24, and enables public IP mapping. The subnets are tagged to be shared with the specified EKS cluster.


EKS has a unique approach to managing Kubernetes versions. It only allows specifying major and minor versions (e.g., 1.26), and to use a specific patch, the release_version field must be defined, which is only applicable for node pools. However, our focus is on major and minor versions only.

Choose any valid major and minor version, but avoid the latest one. You will understand why we don't recommend the newest version later on. If you're unsure which version to select, the second-to-newest is a safe bet. For instance, if the latest version is 1.26, choose 1.25.

To make it more convenient when running future commands that may require a valid Kubernetes version, we will save the chosen version in an environment variable.

```bash
# Kubernetes Version
export K8S_VER='1.25'
```

We will also establish a variable for the release version. While it won't be required until we create worker node pools, since we're already defining variables, we may as well address this one too. To see the available options, let's visit the Amazon EKS-optimized [Linux AMI versions page](https://docs.aws.amazon.com/eks/latest/userguide/eks-linux-ami-versions.html).

```bash
# Release version
export RELEASE_VER='1.25.7-20230411'
```
At this point, we can proceed to apply the configuration and establish the control plane.

```bash
terraform apply --var k8s_version=$K8S_VER --var release_version=$RELEASE_VER
```

Before examining the nodes in our newly created Kubernetes cluster, we must first generate a kubeconfig file to provide kubectl with the necessary information to access the cluster. While this can be done directly with the AWS CLI.

Assuming you don't remember the cluster name and region, or you didn't pay close attention, we can still access the required information using Terraform outputs, as long as it's available in the Terraform state. This scenario offers an excellent opportunity to showcase how Terraform outputs can be helpful in extracting specific information.

```bash
.
├── awscred
├── controlPlane.tf
├── output.tf
├── provider.tf
└── variables.tf
```

### output.tf

- output "cluster_name": This output block displays the value of the cluster_name variable, which represents the name of the EKS (Elastic Kubernetes Service) cluster.
- output "region": This output block displays the value of the region variable, which represents the AWS region where the resources will be created and managed.

```bash
# Update the state file to reflect the actual state of the infrastructure.
terraform refresh --var k8s_version=$K8S_VER --var release_version=$RELEASE_VER

# Outputs:
cluster_name = "eks-test"
region = "eu-central-1"
```

By running the following command allows you to update your local kubeconfig file with the necessary information to interact with your EKS cluster using kubectl or other Kubernetes tools, even if you don't have the cluster name and region information readily available. 

```bash
aws eks update-kubeconfig --name $(terraform output --raw cluster_name) --region $(terraform output --raw region)
```

To enable client authentication (for example, using kubectl), you must install the [AWS IAM Authenticator for Kubernetes](https://github.com/kubernetes-sigs/aws-iam-authenticator).

[Installing aws-iam-authenticator](https://github.com/awsdocs/amazon-eks-user-guide/blob/master/doc_source/install-aws-iam-authenticator.md)

```bash
kubectl get nodes -o wide
```

## Creating Worker Nodes

Worker nodes can be managed using the [aws_eks_node_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group.html) module in Terraform. As anticipated, another pre-configured definition is available for our use.

```bash
.
├── awscred
├── controlPlane.tf
├── output.tf
├── provider.tf
├── variables.tf
└── workerNodes.tf
```

### workerNodes.tf

- "aws_eks_node_group" "primary": This block creates an Amazon EKS node group, which is a group of worker nodes managed by Amazon EKS. The configuration specifies various attributes, such as the cluster name, Kubernetes version, instance types, and scaling configuration.
- "aws_iam_role" "worker": This block creates an AWS IAM role with the name eks-test-worker. This role is used by the worker nodes in the EKS cluster. The assume_role_policy attribute defines a policy allowing EC2 instances to assume this role.
- "aws_iam_role_policy_attachment": There are three of these blocks, each attaching a different policy to the worker IAM role. These policies grant the necessary permissions for worker nodes to interact with Amazon EKS, the EKS CNI plugin, and Amazon EC2 Container Registry.
- "aws_internet_gateway" "worker": This block creates an Internet Gateway and attaches it to the specified VPC. It allows resources within the VPC to access the internet.
- "aws_route_table" "worker": This block creates a route table in the specified VPC. The route directs all traffic with a destination of 0.0.0.0/0 (all IP addresses) to the previously created Internet Gateway.
- "aws_route_table_association" "worker": This block creates associations between the specified subnets and the route table. It does this for three subnets by using a count parameter.

```bash
terraform apply --var k8s_version=$K8S_VER --var release_version=$RELEASE_VER
```

**We've successfully established a cluster by employing Infrastructure as Code via Terraform!**

```bash
kubectl get nodes -o wide
```

## Destroying the Cluster and resources.

```bash
terraform destroy --var k8s_version=$K8S_VER --var release_version=$RELEASE_VER
```
The cluster, along with all the associated resources we specified, has now been completely removed.
