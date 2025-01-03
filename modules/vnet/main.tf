# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network
resource "azurerm_virtual_network" "this" {
  count = var.create_virtual_network ? 1 : 0

  name                = var.name
  location            = var.region
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = length(coalesce(var.address_space, [])) > 0
      error_message = "The `var.address_space` property is required when creating a VNET."
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/virtual_network
data "azurerm_virtual_network" "this" {
  count = var.create_virtual_network == false ? 1 : 0

  resource_group_name = var.resource_group_name
  name                = var.name
}

locals {
  virtual_network = var.create_virtual_network ? azurerm_virtual_network.this[0] : data.azurerm_virtual_network.this[0]
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet
resource "azurerm_subnet" "this" {
  for_each = { for k, v in var.subnets : k => v if var.create_subnets }

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = local.virtual_network.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.enable_storage_service_endpoint ? ["Microsoft.Storage"] : null
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subnet
data "azurerm_subnet" "this" {
  for_each = { for k, v in var.subnets : k => v if var.create_subnets == false }

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = local.virtual_network.name
}

locals {
  subnets = var.create_subnets ? azurerm_subnet.this : data.azurerm_subnet.this
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group
resource "azurerm_network_security_group" "this" {
  for_each = var.network_security_groups

  name                = each.value.name
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

locals {
  nsg_rules = flatten([
    for nsg_key, nsg in var.network_security_groups : [
      for rule_key, rule in nsg.rules : {
        nsg_key   = nsg_key
        nsg_name  = nsg.name
        rule_name = rule.name
        rule      = rule
      }
    ]
  ])
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule
resource "azurerm_network_security_rule" "this" {
  for_each = {
    for nsg in local.nsg_rules : "${nsg.nsg_key}-${nsg.rule_name}" => nsg
  }

  name                         = each.value.rule_name
  resource_group_name          = var.resource_group_name
  network_security_group_name  = azurerm_network_security_group.this[each.value.nsg_key].name
  priority                     = each.value.rule.priority
  direction                    = each.value.rule.direction
  access                       = each.value.rule.access
  protocol                     = each.value.rule.protocol
  source_port_range            = each.value.rule.source_port_range
  source_port_ranges           = each.value.rule.source_port_ranges
  destination_port_range       = each.value.rule.destination_port_range
  destination_port_ranges      = each.value.rule.destination_port_ranges
  source_address_prefix        = each.value.rule.source_address_prefix
  source_address_prefixes      = each.value.rule.source_address_prefixes
  destination_address_prefix   = each.value.rule.destination_address_prefix
  destination_address_prefixes = each.value.rule.destination_address_prefixes

  depends_on = [azurerm_network_security_group.this]
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table
resource "azurerm_route_table" "this" {
  for_each = var.route_tables

  name                          = each.value.name
  location                      = var.region
  resource_group_name           = var.resource_group_name
  tags                          = var.tags
  disable_bgp_route_propagation = each.value.disable_bgp_route_propagation
}

locals {
  route = flatten([
    for route_table_key, route_table in var.route_tables : [
      for route_key, route in route_table.routes : {
        route_table_name = route_table.name
        route_table_key  = route_table_key
        route_name       = route.name
        route            = route
      }
    ]
  ])
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route
resource "azurerm_route" "this" {
  for_each = {
    for route in local.route : "${route.route_table_key}-${route.route_name}" => route
  }

  name                   = each.value.route_name
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this[each.value.route_table_key].name
  address_prefix         = each.value.route.address_prefix
  next_hop_type          = each.value.route.next_hop_type
  next_hop_in_ip_address = each.value.route.next_hop_type == "VirtualAppliance" ? each.value.route.next_hop_ip_address : null
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = { for k, v in var.subnets : k => v if v.network_security_group_key != null }

  subnet_id                 = local.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.value.network_security_group_key].id
}

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association
resource "azurerm_subnet_route_table_association" "this" {
  for_each = { for k, v in var.subnets : k => v if v.route_table_key != null }

  subnet_id      = local.subnets[each.key].id
  route_table_id = azurerm_route_table.this[each.value.route_table_key].id
}
