provider "azurerm" {
  version = "=2.12.0"
  features {}
}

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${random_string.unique.result}"
  location = var.rg_location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = var.aks_version
  dns_prefix          = "aks"

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_vm_size
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_user_assigned_identity" "mi" {
  name                = "mi-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

provider "helm" {
  kubernetes {
    load_config_file       = false
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    username               = azurerm_kubernetes_cluster.aks.kube_config.0.username
    password               = azurerm_kubernetes_cluster.aks.kube_config.0.password
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

resource "helm_release" "aad_pod_id" {
  name             = "aad-pod-identity"
  repository       = "https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts"
  chart            = "aad-pod-identity"
  version          = "2.0.0"
  namespace        = var.aad_pod_id_ns
  create_namespace = true

  values = [
    <<-EOF
    azureIdentities:
    - name: "${azurerm_user_assigned_identity.mi.name}"
      resourceID: "${azurerm_user_assigned_identity.mi.id}"
      clientID: "${azurerm_user_assigned_identity.mi.client_id}"
      binding:
        name: "${azurerm_user_assigned_identity.mi.name}-identity-binding"
        selector: "${var.aad_pod_id_binding_selector}"
    EOF
  ]
}

data "azurerm_resource_group" "aks_node_rg" {
  name = azurerm_kubernetes_cluster.aks.node_resource_group
}

# Following roles are required by AAD Pod Identity and must be assigned to the Kubelet Identity
# https://github.com/Azure/aad-pod-identity/blob/master/docs/readmes/README.msi.md#pre-requisites---role-assignments
resource "azurerm_role_assignment" "vm_contributor" {
  scope                = data.azurerm_resource_group.aks_node_rg.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id
}

resource "azurerm_role_assignment" "all_mi_operator" {
  scope                = data.azurerm_resource_group.aks_node_rg.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id
}

resource "azurerm_role_assignment" "mi_operator" {
  scope                = azurerm_user_assigned_identity.mi.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id
}

resource "random_password" "sql" {
  length  = 16
  special = true
}

resource "azurerm_sql_server" "sql" {
  name                         = "sql-${random_string.unique.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "mradministrator"
  administrator_login_password = random_password.sql.result
}

data "azurerm_client_config" "current" {}

data "azuread_service_principal" "current" {
  object_id = data.azurerm_client_config.current.object_id
}

resource "azurerm_sql_active_directory_administrator" "sql" {
  server_name         = azurerm_sql_server.sql.name
  resource_group_name = azurerm_resource_group.rg.name
  login               = data.azuread_service_principal.current.display_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = data.azurerm_client_config.current.object_id
}

resource "azurerm_sql_firewall_rule" "azure_services" {
  name                = "AllowAzureServices"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

data "http" "my_ip" {
  url = "http://ipv4.icanhazip.com"
}

# This firewall rule is only needed when running locally
resource "azurerm_sql_firewall_rule" "my_ip" {
  name                = "My IP"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql.name
  start_ip_address    = trimspace(data.http.my_ip.body)
  end_ip_address      = trimspace(data.http.my_ip.body)
}

resource "azurerm_sql_database" "sql" {
  name                = var.sql_db_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  server_name         = azurerm_sql_server.sql.name
}

resource "null_resource" "sql_bootstrap" {
  triggers = {
    mi_name      = azurerm_user_assigned_identity.mi.name
    mi_client_id = azurerm_user_assigned_identity.mi.client_id
    sha1         = filesha1("${path.module}/bootstrap-sql.ps1")
  }
  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    environment = {
      # Use env var to pass connection string otherwise terraform cli will print it to stdout
      SQL_SA_CONNECTION_STRING = "Server=tcp:${azurerm_sql_server.sql.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_sql_database.sql.name};Persist Security Info=False;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;User ID=${azurerm_sql_server.sql.administrator_login};Password=${azurerm_sql_server.sql.administrator_login_password};"
    }
    command = <<EOF
      .'${path.module}/bootstrap-sql.ps1' `
        -identityName "${azurerm_user_assigned_identity.mi.name}" `
        -identityClientId "${azurerm_user_assigned_identity.mi.client_id}" `
        -sqlSaConnectionString "$Env:SQL_SA_CONNECTION_STRING"
EOF
  }
  depends_on = [
    azurerm_sql_active_directory_administrator.sql,
    azurerm_sql_firewall_rule.my_ip
  ]
}
