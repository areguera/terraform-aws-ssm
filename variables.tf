variable "name" {
  description = "(Required) The project name. This value is prefixed to SSM configuration resources."
  type        = string
}

variable "description" {
  description = "(Optional) The project description."
  type        = string
  default     = ""
}

variable "operating_system" {
  description = "(Optional) Defines the operating system the patch baseline applies to. Supported operating systems include AMAZON_LINUX_2."
  type        = string
  default     = "AMAZON_LINUX_2"
}

variable "approved_patches_compliance_level" {
  description = "(Optional) Defines the compliance level for approved patches. This means that if an approved patch is reported as missing, this is the severity of the compliance violation. Valid compliance levels include the following: CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL, UNSPECIFIED."
  type        = string
  default     = "UNSPECIFIED"
}

variable "approved_patches_enable_non_security" {
  description = "(Optional) Indicates whether the list of approved patches includes non-security updates that should be applied to the instances."
  type        = bool
  default     = false
}

variable "max_concurrency" {
  description = "(Optional) Specify the number of managed nodes that run a command simultaneously. Posible values can be integers (e.g., '5', '10') or percentages (e.g., '10%', '20%'). In both cases the values must be passed as string."
  type        = string
  default     = "10%"
}

variable "max_errors" {
  description = "(Optional) Specify how many errors are allowed before the system stops sending the command to additional managed nodes. Posible values can be integers (e.g., '5', '10') or percentages (e.g., '10%', '20%'). In both cases the values must be passed as string."
  type        = string
  default     = "1"
}

variable "approval_rules" {
  description = "(Required) Specify the set of rules used to include patches in the baseline. Up to 10 approval rules can be specified."
  type = list(object({
    approve_after_days  = number
    compliance_level    = string
    enable_non_security = bool
    patch_filters       = list(object({
      key    = string
      values = list(string)
    }))
  }))
}

variable "maintenance_window" {
  description = "(Required) Specify the set of rules used to configure the maintenance window."
  type = object({
    schedule          = string
    schedule_timezone = string
    cutoff            = number
    duration          = number
    enabled           = bool
  })
}
