# Generate a random password

# https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password
resource "random_password" "this" {
  count = anytrue([
    for _, v in var.scale_sets : v.authentication.password == null
    if !v.authentication.disable_password_authentication
    ]) ? (
    anytrue([for _, v in var.test_infrastructure : v.authentication.password == null]) ? 2 : 1
  ) : 0

  length           = 16
  min_lower        = 16 - 4
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "_%@"
}

locals {
  authentication = {
    for k, v in var.scale_sets : k =>
    merge(
      v.authentication,
      {
        ssh_keys = [for ssh_key in v.authentication.ssh_keys : file(ssh_key)]
        password = try(coalesce(v.authentication.password, random_password.this[0].result), null)
      }
    )
  }
}

# Create or source a Resource Group

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group
resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = "${var.name_prefix}${var.resource_group_name}"
  location = var.region

  tags = var.tags
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group
data "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group = var.create_resource_group ? azurerm_resource_group.this[0] : data.azurerm_resource_group.this[0]
}

# Manage the network required for the topology

module "vnet" {
  source = "../../modules/vnet"

  for_each = var.vnets

  name                   = each.value.create_virtual_network ? "${var.name_prefix}${each.value.name}" : each.value.name
  create_virtual_network = each.value.create_virtual_network
  resource_group_name    = coalesce(each.value.resource_group_name, local.resource_group.name)
  region                 = var.region

  address_space = each.value.address_space

  create_subnets = each.value.create_subnets
  subnets        = each.value.subnets

  network_security_groups = {
    for k, v in each.value.network_security_groups : k => merge(v, { name = "${var.name_prefix}${v.name}" })
  }
  route_tables = {
    for k, v in each.value.route_tables : k => merge(v, { name = "${var.name_prefix}${v.name}" })
  }

  tags = var.tags
}

module "vnet_peering" {
  source = "../../modules/vnet_peering"

  for_each = var.vnet_peerings

  local_peer_config = {
    name                = "peer-${each.value.local_vnet_name}-to-${each.value.remote_vnet_name}"
    resource_group_name = coalesce(each.value.local_resource_group_name, local.resource_group.name)
    vnet_name           = each.value.local_vnet_name
  }
  remote_peer_config = {
    name                = "peer-${each.value.remote_vnet_name}-to-${each.value.local_vnet_name}"
    resource_group_name = coalesce(each.value.remote_resource_group_name, local.resource_group.name)
    vnet_name           = each.value.remote_vnet_name
  }

  depends_on = [module.vnet]
}

module "natgw" {
  source = "../../modules/natgw"

  for_each = var.natgws

  create_natgw        = each.value.create_natgw
  name                = each.value.create_natgw ? "${var.name_prefix}${each.value.name}" : each.value.name
  resource_group_name = coalesce(each.value.resource_group_name, local.resource_group.name)
  region              = var.region
  zone                = try(each.value.zone, null)
  idle_timeout        = each.value.idle_timeout
  subnet_ids          = { for v in each.value.subnet_keys : v => module.vnet[each.value.vnet_key].subnet_ids[v] }

  public_ip = try(merge(each.value.public_ip, {
    name = "${each.value.public_ip.create ? var.name_prefix : ""}${each.value.public_ip.name}"
  }), null)
  public_ip_prefix = try(merge(each.value.public_ip_prefix, {
    name = "${each.value.public_ip_prefix.create ? var.name_prefix : ""}${each.value.public_ip_prefix.name}"
  }), null)

  tags       = var.tags
  depends_on = [module.vnet]
}

# Create Load Balancers, both internal and external

module "load_balancer" {
  source = "../../modules/loadbalancer"

  for_each = var.load_balancers

  name                = "${var.name_prefix}${each.value.name}"
  region              = var.region
  resource_group_name = local.resource_group.name
  zones               = each.value.zones
  backend_name        = each.value.backend_name

  health_probes = each.value.health_probes

  nsg_auto_rules_settings = try(
    {
      nsg_name = try(
        "${var.name_prefix}${var.vnets[each.value.nsg_auto_rules_settings.nsg_vnet_key].network_security_groups[
        each.value.nsg_auto_rules_settings.nsg_key].name}",
        each.value.nsg_auto_rules_settings.nsg_name
      )
      nsg_resource_group_name = try(
        var.vnets[each.value.nsg_auto_rules_settings.nsg_vnet_key].resource_group_name,
        each.value.nsg_auto_rules_settings.nsg_resource_group_name,
        null
      )
      source_ips    = each.value.nsg_auto_rules_settings.source_ips
      base_priority = each.value.nsg_auto_rules_settings.base_priority
    },
    null
  )

  frontend_ips = {
    for k, v in each.value.frontend_ips : k => merge(
      v,
      {
        public_ip_name = v.create_public_ip ? "${var.name_prefix}${v.public_ip_name}" : v.public_ip_name,
        subnet_id      = try(module.vnet[each.value.vnet_key].subnet_ids[v.subnet_key], null)
      }
    )
  }

  tags       = var.tags
  depends_on = [module.vnet]
}

# Create Application Gateways

module "appgw" {
  source = "../../modules/appgw"

  for_each = var.appgws

  name                = "${var.name_prefix}${each.value.name}"
  resource_group_name = local.resource_group.name
  region              = var.region
  subnet_id           = module.vnet[each.value.vnet_key].subnet_ids[each.value.subnet_key]

  zones = each.value.zones
  public_ip = merge(
    each.value.public_ip,
    { name = "${each.value.public_ip.create ? var.name_prefix : ""}${each.value.public_ip.name}" }
  )
  domain_name_label              = each.value.domain_name_label
  capacity                       = each.value.capacity
  enable_http2                   = each.value.enable_http2
  waf                            = each.value.waf
  managed_identities             = each.value.managed_identities
  global_ssl_policy              = each.value.global_ssl_policy
  ssl_profiles                   = each.value.ssl_profiles
  frontend_ip_configuration_name = each.value.frontend_ip_configuration_name
  listeners                      = each.value.listeners
  backend_pool                   = each.value.backend_pool
  backend_settings               = each.value.backend_settings
  probes                         = each.value.probes
  rewrites                       = each.value.rewrites
  redirects                      = each.value.redirects
  url_path_maps                  = each.value.url_path_maps
  rules                          = each.value.rules

  tags       = var.tags
  depends_on = [module.vnet]
}

# Create VM-Series VM Scale Sets and closely associated resources

module "ngfw_metrics" {
  source = "../../modules/ngfw_metrics"

  count = var.ngfw_metrics != null ? 1 : 0

  create_workspace = var.ngfw_metrics.create_workspace

  name = "${var.ngfw_metrics.create_workspace ? var.name_prefix : ""}${var.ngfw_metrics.name}"
  resource_group_name = var.ngfw_metrics.create_workspace ? local.resource_group.name : (
    coalesce(var.ngfw_metrics.resource_group_name, local.resource_group.name)
  )
  region = var.region

  log_analytics_workspace = {
    sku                       = var.ngfw_metrics.sku
    metrics_retention_in_days = var.ngfw_metrics.metrics_retention_in_days
  }

  application_insights = {
    for k, v in var.scale_sets :
    k => { name = "${var.name_prefix}${v.name}-ai" }
    if length(v.autoscaling_profiles) > 0
  }

  tags = var.tags
}

module "vmss" {
  source = "../../modules/vmss"

  for_each = var.scale_sets

  name                = "${var.name_prefix}${each.value.name}"
  resource_group_name = local.resource_group.name
  region              = var.region

  authentication            = local.authentication[each.key]
  virtual_machine_scale_set = each.value.virtual_machine_scale_set
  image                     = each.value.image

  interfaces = [
    for v in each.value.interfaces : {
      name                   = v.name
      subnet_id              = module.vnet[each.value.vnet_key].subnet_ids[v.subnet_key]
      create_public_ip       = v.create_public_ip
      pip_domain_name_label  = v.pip_domain_name_label
      lb_backend_pool_ids    = try([module.load_balancer[v.load_balancer_key].backend_pool_id], [])
      appgw_backend_pool_ids = try([module.appgw[v.application_gateway_key].backend_pool_id], [])
    }
  ]

  autoscaling_configuration = merge(
    each.value.autoscaling_configuration,
    { application_insights_id = try(module.ngfw_metrics[0].application_insights_ids[each.key], null) }
  )
  autoscaling_profiles = each.value.autoscaling_profiles

  tags       = var.tags
  depends_on = [module.vnet, module.load_balancer, module.appgw]
}

# Create test infrastructure

locals {
  test_vm_authentication = {
    for k, v in var.test_infrastructure : k =>
    merge(
      v.authentication,
      {
        password = coalesce(v.authentication.password, try(random_password.this[1].result, null))
      }
    )
  }
}

module "test_infrastructure" {
  source = "../../modules/test_infrastructure"

  for_each = var.test_infrastructure

  resource_group_name = try(
    "${var.name_prefix}${each.value.resource_group_name}", "${local.resource_group.name}-testenv"
  )
  region = var.region
  vnets = { for k, v in each.value.vnets : k => merge(v, {
    name                    = "${var.name_prefix}${v.name}"
    hub_vnet_name           = "${var.name_prefix}${v.hub_vnet_name}"
    hub_resource_group_name = coalesce(v.hub_resource_group_name, local.resource_group.name)
    network_security_groups = { for kv, vv in v.network_security_groups : kv => merge(vv, {
      name = "${var.name_prefix}${vv.name}" })
    }
    route_tables = { for kv, vv in v.route_tables : kv => merge(vv, {
      name = "${var.name_prefix}${vv.name}" })
    }
  }) }
  load_balancers = { for k, v in each.value.load_balancers : k => merge(v, {
    name         = "${var.name_prefix}${v.name}"
    backend_name = coalesce(v.backend_name, "${v.name}-backend")
  }) }
  authentication = local.test_vm_authentication[each.key]
  spoke_vms = { for k, v in each.value.spoke_vms : k => merge(v, {
    name           = "${var.name_prefix}${v.name}"
    interface_name = "${var.name_prefix}${coalesce(v.interface_name, "${v.name}-nic")}"
    disk_name      = "${var.name_prefix}${coalesce(v.disk_name, "${v.name}-osdisk")}"
  }) }
  bastions = { for k, v in each.value.bastions : k => merge(v, {
    name           = "${var.name_prefix}${v.name}"
    public_ip_name = "${var.name_prefix}${coalesce(v.public_ip_name, "${v.name}-pip")}"
  }) }

  tags       = var.tags
  depends_on = [module.vnet]
}
