variable "name" {
  description = "(Required) The project name. This value is prefixed to resources."
  type        = string
}

variable "description" {
  description = "(Optional) The project description."
  type        = string
  default     = ""
}

variable "operating_system" {
  description = "(Optional) Defines the operating system the patch baseline applies to. Supported operating systems include WINDOWS, AMAZON_LINUX, AMAZON_LINUX_2, SUSE, UBUNTU, CENTOS, and REDHAT_ENTERPRISE_LINUX. The Default value is AMAZON_LINUX_2."
  type        = string
  default     = "AMAZON_LINUX_2"
}

variable "approved_patches_compliance_level" {
  description = "(Optional) Defines the compliance level for approved patches. This means that if an approved patch is reported as missing, this is the severity of the compliance violation. Valid compliance levels include the following: CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL, UNSPECIFIED. The default value is UNSPECIFIED."
  type        = string
  default     = "UNSPECIFIED"
}

variable "approved_patches_enable_non_security" {
  description = "(Optional) Indicates whether the list of approved patches includes non-security updates that should be applied to the instances. Applies to Linux instances only."
  type        = bool
  default     = false
}

variable "max_concurrency" {
  description = "(Optional) Specify the number of managed nodes that run a command simultaneously. By default uses 10%."
  type        = string
  default     = "10%"
}

variable "max_errors" {
  description = "(Optional) Specify how many errors are allowed before the system stops sending the command to additional managed nodes. By default uses 1."
  type        = string
  default     = "1"
}

variable "approval_rules" {
  description = "(Required) A set of rules used to include patches in the baseline. Up to 10 approval rules can be specified. Each approval_rule block requires the fields documented below."
  type = list(object({
    approve_after_days  = number
    compliance_level    = string
    enable_non_security = bool

    patch_filters = list(object({
      key    = string
      values = list(string)
    }))
  }))
}

variable "maintenance_window" {
  description = "(Required)"
  type = object({
    schedule          = string
    schedule_timezone = string
    cutoff            = number
    duration          = number
    enabled           = bool
  })
}
