variable "name" {
  description = "The name of the Azure Virtual Machine."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the Resource Group to use."
  type        = string
}

variable "region" {
  description = "The name of the Azure region to deploy the resources in."
  type        = string
}

variable "tags" {
  description = "The map of tags to assign to all created resources."
  default     = {}
  type        = map(string)
}

variable "authentication" {
  description = <<-EOF
  A map defining authentication settings (including username and password).

  Following properties are available:

  - `username`                        - (`string`, optional, defaults to `panadmin`) the initial administrative VM-Series
                                        username.
  - `password`                        - (`string`, optional, defaults to `null`) the initial administrative VM-Series password.
  - `disable_password_authentication` - (`bool`, optional, defaults to `true`) disables password-based authentication.
  - `ssh_keys`                        - (`list`, optional, defaults to `[]`) a list of initial administrative SSH public keys.

  **Important!** \
  The `password` property is required when `ssh_keys` is not specified.

  **Important!** \
  `ssh_keys` property is a list of strings, so each item should be the actual public key value.
  If you would like to load them from files use the `file` function, for example: `[ file("/path/to/public/keys/key_1.pub") ]`.
  EOF
  type = object({
    username                        = optional(string, "panadmin")
    password                        = optional(string)
    disable_password_authentication = optional(bool, true)
    ssh_keys                        = optional(list(string), [])
  })
}

variable "image" {
  description = <<-EOF
  Basic Azure VM image configuration.

  Following properties are available:

  - `version`                 - (`string`, optional, defaults to `null`) VM-Series PAN-OS version; list available with
                                `az vm image list -o table --publisher paloaltonetworks  --offer prisma-sd-wan-ion-virtual-appliance --all`.
  - `publisher`               - (`string`, optional, defaults to `paloaltonetworks`) the Azure Publisher identifier for a image
                                which should be deployed.
  - `offer`                   - (`string`, optional, defaults to `prisma-sd-wan-ion-virtual-appliance`) the Azure Offer identifier corresponding to a
                                published image.
  - `sku`                     - (`string`, optional, defaults to `prisma-sdwan-ion-virtual-appliance`) ion SKU; list available with
                                `az vm image list -o table --all --publisher paloaltonetworks`.
  - `enable_marketplace_plan` - (`bool`, optional, defaults to `true`) when set to `true` accepts the license for an offer/plan
                                on Azure Market Place.
  - `custom_id`               - (`string`, optional, defaults to `null`) absolute ID of your own custom PAN-OS image to be used
                                for creating new Virtual Machines.

  **Important!** \
  `custom_id` and `version` properties are mutually exclusive.
  EOF
  type = object({
    version                 = optional(string)
    publisher               = optional(string, "paloaltonetworks")
    offer                   = optional(string, "prisma-sd-wan-ion-virtual-appliance")
    sku                     = optional(string, "prisma-sdwan-ion-virtual-appliance")
    enable_marketplace_plan = optional(bool, true)
    custom_id               = optional(string)
  })
  validation { # version & custom_id
    condition = (var.image.custom_id != null && var.image.version == null
      ) || (
      var.image.custom_id == null && var.image.version != null
    )
    error_message = <<-EOF
    Either `custom_id` or `version` has to be defined.
    EOF
  }
}

variable "virtual_machine" {
  description = <<-EOF
  Firewall parameters configuration.

  This map contains basic, as well as some optional Firewall parameters. Both types contain sane defaults.
  Nevertheless they should be at least reviewed to meet deployment requirements.

  List of either required or important properties:

  - `size`              - (`string`, optional, defaults to `Standard_D3_v2`) Azure VM size (type). Consult the *VM-Series
                          Deployment Guide* as only a few selected sizes are supported.
  - `zone`              - (`string`, required) Availability Zone to place the VM in, `null` value means a non-zonal deployment.
  - `disk_type`         - (`string`, optional, defaults to `StandardSSD_LRS`) type of Managed Disk which should be created,
                          possible values are `Standard_LRS`, `StandardSSD_LRS` or `Premium_LRS` (works only for selected
                          `vm_size` values).
  - `disk_name`         - (`string`, optional, defaults to VM name + `-disk` suffix) name od the OS disk.
  - `bootstrap_options` - bootstrap options to pass to VM-Series instance.

    Proper syntax is a string of semicolon separated properties, for example:

    ```hcl
    bootstrap_options = "type=dhcp-client;panorama-server=1.2.3.4"
    ```

    For more details on bootstrapping [see documentation](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/bootstrap-the-vm-series-firewall/create-the-init-cfgtxt-file/init-cfgtxt-file-components).

  List of other, optional properties:

  - `avset_key`                     - (`string`, optional, default to `null`) identifier of the Availability Set to use.
  - `accelerated_networking`        - (`bool`, optional, defaults to `true`) when set to `true`  enables Azure accelerated
                                      networking (SR-IOV) for all dataplane network interfaces, this does not affect the
                                      management interface (always disabled).
  - `allow_extension_operations`    - (`bool`, optional, defaults to `false`) should Extension Operations be allowed on this VM.
  - `disk_encryption_set_id`        - (`string`, optional, defaults to `null`) the ID of the Disk Encryption Set which should be
                                      used to encrypt this VM's disk.
  - `encryption_at_host_enabled`    - (`bool`, optional, defaults to Azure defaults) should all of disks be encrypted
                                      by enabling Encryption at Host.
  - `enable_boot_diagnostics`       - (`bool`, optional, defaults to `false`) enables boot diagnostics for a VM.
  - `boot_diagnostics_storage_uri`  - (`string`, optional, defaults to `null`) Storage Account's Blob endpoint to hold
                                      diagnostic files, when skipped a managed Storage Account will be used (preferred).
  - `identity_type`                 - (`string`, optional, defaults to `SystemAssigned`) type of Managed Service Identity that
                                      should be configured on this VM. Can be one of "SystemAssigned", "UserAssigned" or
                                      "SystemAssigned, UserAssigned".
  - `identity_ids`                  - (`list`, optional, defaults to `[]`) a list of User Assigned Managed Identity IDs to be
                                      assigned to this VM. Required only if `identity_type` is not "SystemAssigned".
  EOF
  type = object({
    size                         = optional(string, "Standard_D3_v2")
    bootstrap_options            = optional(string)
    zone                         = string
    disk_type                    = optional(string, "StandardSSD_LRS")
    disk_name                    = string
    avset_id                     = optional(string)
    accelerated_networking       = optional(bool, true)
    allow_extension_operations   = optional(bool, false)
    encryption_at_host_enabled   = optional(bool)
    disk_encryption_set_id       = optional(string)
    enable_boot_diagnostics      = optional(bool, false)
    boot_diagnostics_storage_uri = optional(string)
    identity_type                = optional(string, "SystemAssigned")
    identity_ids                 = optional(list(string), [])
  })
  validation { # disk_type
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.virtual_machine.disk_type)
    error_message = <<-EOF
    The `disk_type` property can be one of: `Standard_LRS`, `StandardSSD_LRS` or `Premium_LRS`.
    EOF
  }
  validation { # identity_type
    condition = contains(
      ["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.virtual_machine.identity_type
    )
    error_message = <<-EOF
    The `identity_type` property can be one of \"SystemAssigned\", \"UserAssigned\" or \"SystemAssigned, UserAssigned\".
    EOF
  }
  validation { # identity_type & identity_ids
    condition = var.virtual_machine.identity_type == "SystemAssigned" ? (
      length(var.virtual_machine.identity_ids) == 0
    ) : length(var.virtual_machine.identity_ids) > 0
    error_message = <<-EOF
    The `identity_ids` property is required when `identity_type` is not \"SystemAssigned\".
    EOF
  }
}

variable "interfaces" {
  description = <<-EOF
  List of the network interface specifications.

  **Note!** \
  The ORDER in which you specify the interfaces DOES MATTER.

  Interfaces will be attached to VM in the order you define here, therefore:

  - The first should be the management interface, which does not participate in data filtering.
  - The remaining ones are the dataplane interfaces.

  Following configuration options are available:

  - `name`                          - (`string`, required) the interface name.
  - `subnet_id`                     - (`string`, required) ID of an existing subnet to create the interface in.
  - `private_ip_address`            - (`string`, optional, defaults to `null`) static private IP to assign to the interface. When
                                      skipped Azure will assign one dynamically. Keep in mind that a dynamic IP is guarantied not
                                      to change as long as the VM is running. Any stop/deallocate/restart operation might cause
                                      the IP to change.
  - `create_public_ip`              - (`bool`, optional, defaults to `false`) if `true`, creates a public IP for the interface.
  - `public_ip_name`                - (`string`, optional, defaults to `null`) name of the public IP to associate with the
                                      interface. When `create_public_ip` is set to `true` this will become a name of a newly
                                      created Public IP interface. Otherwise this is a name of an existing interfaces that will
                                      be sourced and attached to the interface.
  - `public_ip_resource_group_name` - (`string`, optional, defaults to `var.resource_group_name`) name of a Resource Group that
                                      contains public IP that that will be associated with the interface. Used only when
                                      `create_public_ip` is `false`.
  - `attach_to_lb_backend_pool`     - (`bool`, optional, defaults to `false`) set to `true` if you would like to associate this
                                      interface with a Load Balancer backend pool.
  - `lb_backend_pool_id`            - (`string`, optional, defaults to `null`) ID of an existing backend pool to associate the
                                      interface with.

  Example:

  ```hcl
  [
    # management interface with a new public IP
    {
      name                 = "fw-mgmt"
      subnet_id            = azurerm_subnet.my_mgmt_subnet.id
      public_ip_name       = "fw-mgmt-pip"
      create_public_ip     = true
    },
    # public interface reusing an existing public IP resource
    {
      name                      = "fw-public"
      subnet_id                 = azurerm_subnet.my_pub_subnet.id
      attach_to_lb_backend_pool = true
      lb_backend_pool_id        = module.inbound_lb.backend_pool_id
      create_public_ip          = false
      public_ip_name            = "fw-public-pip"
    },
  ]
  ```
  EOF
  type = list(object({
    name                          = string
    subnet_id                     = string
    create_public_ip              = optional(bool, false)
    public_ip_name                = optional(string)
    public_ip_resource_group_name = optional(string)
    private_ip_address            = optional(string)
    lb_backend_pool_id            = optional(string)
    attach_to_lb_backend_pool     = optional(bool, false)
  }))
  validation { # create_public_ip & public_ip_name
    condition = alltrue([
      for v in var.interfaces : v.public_ip_name != null if v.create_public_ip
    ])
    error_message = <<-EOF
    The `public_ip_name` property is required when `create_public_ip` is set to `true`.
    EOF
  }
  validation { # lb_backend_pool_id & attach_to_lb_backend_pool
    condition = alltrue([
      for v in var.interfaces : v.lb_backend_pool_id != null if v.attach_to_lb_backend_pool
    ])
    error_message = <<-EOF
    The `lb_backend_pool_id` cannot be `null` when `attach_to_lb_backend_pool` is set to `true`.
    EOF
  }
}
