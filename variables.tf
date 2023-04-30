variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "cluster_name" {
  type    = string
  default = "eks-test"
}

variable "k8s_version" {
  type = string
}

variable "release_version" {
  type    = string
}

variable "min_node_count" {
  type    = number
  default = 3
}

variable "max_node_count" {
  type    = number
  default = 9
}

variable "machine_type" {
  type    = string
  default = "t2.small"
}