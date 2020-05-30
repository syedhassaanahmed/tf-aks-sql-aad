variable rg_location {
  default = "westeurope"
}

variable aks_version {
  default = "1.16.9"
}

variable aks_node_count {
  default = 1
}

variable aks_vm_size {
  default = "Standard_D2_v2"
}

variable aad_pod_id_ns {
  default = "aad-pod-id"
}

variable aad_pod_id_binding_selector {
  default = "aad-pod-id-binding-selector"
}

variable sql_db_name {
  default = "sqldb-test"
}
