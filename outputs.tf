output rg_name {
  value = azurerm_resource_group.rg.name
}

output aks_cluster_name {
  value = azurerm_kubernetes_cluster.aks.name
}

output aad_pod_id_binding_selector {
  value = var.aad_pod_id_binding_selector
}

output sql_server_fqdn {
  value = azurerm_sql_server.sql.fully_qualified_domain_name
}

output sql_db_name {
  value = var.sql_db_name
}
