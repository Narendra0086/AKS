variable "name" {
  description = "Name of the Kubernetes cluster."
}
variable "resource_group_name" {
  description = "Name of resource group to deploy resources in."
}
variable "location" {
  description = "The Azure Region in which to create resource."
}
variable "service_cidr" {
  description = "Cidr of service subnet. If subnet has UDR make sure this is routed correctly."
}
variable "kubernetes_version" {
  description = "Version of Kubernetes to deploy."
}
variable "node_os_channel_upgrade" {
  description = "The upgrade channel for this Kubernetes Cluster Nodes' OS Image."
  default     = "NodeImage"
}
variable "automatic_channel_upgrade" {
  description = "The upgrade channel for this Kubernetes Cluster"
  default     = null
}
variable "maintenance_window_node_os" {
  description = "Maintenance window of node os upgrades."
  type = object({
    frequency   = optional(string)
    interval    = optional(number)
    duration    = optional(number)
    day_of_week = optional(string) # Required if frequency is weekly.
    start_time  = optional(string)
  })
  default = null
}
variable "node_resource_group" {
  description = "The name of the Resource Group where the Kubernetes Nodes should exist."
  default     = null
}
variable "agent_pools" {
  description = "A list of agent pools to create, each item supports same properties as `agent_pool_profile`. See README for default values."
  type        = list(any)
}
variable "linux_profile" {
  description = "Username and ssh key for accessing Linux machines with ssh."
  type = object({
    username = string
    ssh_key  = string
  })
  default = null
}
variable "windows_profile" {
  description = "Admin username and password for Windows hosts."
  type = object({
    username = string
    password = string
  })
  default = null
}
variable "cluster_admins" {
  description = "List of Azure AD object ids that should be cluster admins"
  type        = list(string)
  default     = []
}
variable "cluster_users" {
  description = "List of Azure AD object ids that should be cluster users."
  type = list(object({
    principal_id = string
    namespace    = string
  }))
  default = []
}
variable "admins" {
  description = "List of Azure AD object ids that should be able to impersonate admin user."
  type = list(object({
    kind = string
    name = string
  }))
  default = []
}
variable "container_registries" {
  description = "List of Azure Container Registry ids where AKS needs pull access."
  type        = list(string)
  default     = []
}
variable "storage_contributor" {
  description = "List of storage account ids where the AKS service principal should have access."
  type        = list(string)
  default     = []
}
variable "managed_identities" {
  description = "List of managed identities where the AKS service principal should have access."
  type        = list(string)
  default     = []
}
variable "service_accounts" {
  description = "List of service accounts to create and their roles."
  type = list(object({
    name      = string
    namespace = string
    role      = string
  }))
  default = []
}
variable "diagnostics" {
  description = "Diagnostic settings for those resources that support it. See README.md for details on configuration."
  type = object({
    destination   = string
    eventhub_name = optional(string)
    logs          = list(string)
    metrics       = list(string)
  })
  default = null
}
variable "azure_policy_enabled" {
  description = "Should the Azure Policy Add-On be enabled?"
  type        = bool
  default     = true
}
variable "azure_rbac_enabled" {
  description = "Enable Azure RBAC to control authorization"
  type        = bool
  default     = false
}

variable "oms_agent_log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace which the OMS Agent should send data to. if value is null, no agent is deployed."
  type        = string
  default     = null
}
variable "key_vault_secrets_provider" {
  description = "Key Vault secrets provider settings."
  type = object({
    enabled                  = bool
    secret_rotation_enabled  = bool
    secret_rotation_interval = string
  })
  default = {
    enabled                  = false
    secret_rotation_enabled  = false
    secret_rotation_interval = "2m"
  }
}
variable "oidc_issuer_enabled" {
  description = "Enable or Disable the OIDC issuer URL. Defaults to false"
  type        = bool
  default     = false
}
variable "workload_identity_enabled" {
  description = "Specifies whether Azure AD Workload Identity should be enabled for the Cluster. Defaults to false"
  type        = bool
  default     = false
}
variable "tags" {
  description = "Tags to apply to all resources created."
  type        = map(string)
  default     = {}
}

variables.tf

 
locals {
  default_agent_profile = {
    count                       = 1
    vm_size                     = "Standard_D2_v3"
    os_type                     = "Linux"
    availability_zones          = null
    enable_auto_scaling         = false
    min_count                   = null
    max_count                   = null
    type                        = "VirtualMachineScaleSets"
    node_taints                 = null
    orchestrator_version        = null
    temporary_name_for_rotation = null
  }
  # Defaults for Linux profile
  # Generally smaller images so can run more pods and require smaller HD
  default_linux_node_profile = {
    max_pods        = 30
    os_disk_size_gb = 60
  }
  # Defaults for Windows profile
  # Do not want to run same number of pods and some images can be quite large
  default_windows_node_profile = {
    max_pods        = 20
    os_disk_size_gb = 200
  }
  agent_pools_with_defaults = [
    for ap in var.agent_pools :
    merge(local.default_agent_profile, ap)
  ]
  agent_pools = {
    for ap in local.agent_pools_with_defaults :
    ap.name => ap.os_type == "Linux" ? merge(local.default_linux_node_profile, ap) : merge(local.default_windows_node_profile, ap)
  }
  default_pool = var.agent_pools[0].name
  # Determine which load balancer to use
  agent_pool_availability_zones_lb = [for ap in local.agent_pools : ap.availability_zones != null ? "standard" : ""]
  load_balancer_sku                = coalesce(flatten([local.agent_pool_availability_zones_lb, ["standard"]])...)
  # Distinct subnets
  agent_pool_subnets = distinct([for ap in local.agent_pools : ap.vnet_subnet_id])
  diag_resource_list = var.diagnostics != null ? split("/", var.diagnostics.destination) : []
  parsed_diag = var.diagnostics != null ? {
    log_analytics_id   = contains(local.diag_resource_list, "Microsoft.OperationalInsights") ? var.diagnostics.destination : null
    storage_account_id = contains(local.diag_resource_list, "Microsoft.Storage") ? var.diagnostics.destination : null
    event_hub_auth_id  = contains(local.diag_resource_list, "Microsoft.EventHub") ? var.diagnostics.destination : null
    metric             = var.diagnostics.metrics
    log                = var.diagnostics.logs
    } : {
    log_analytics_id   = null
    storage_account_id = null
    event_hub_auth_id  = null
    metric             = []
    log                = []
  }
}

local.tf

 
