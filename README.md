# tf-aks-sql-aad
This Terraform template enables authentication to Azure SQL Database using [AAD Pod Identity](https://github.com/Azure/aad-pod-identity) from an AKS Cluster. The template is loosely based on [this document](https://docs.microsoft.com/en-us/azure/app-service/app-service-web-tutorial-connect-msi) with the following differences;

- We use [PowerShell sqlserver module](https://docs.microsoft.com/en-us/powershell/module/sqlserver/invoke-sqlcmd?view=sqlserver-ps) instead of [sqlcmd utility](https://docs.microsoft.com/en-us/sql/tools/sqlcmd-utility?view=sql-server-ver15). When applying the template from an Azure DevOps pipeline, PowerShell already exists on all [hosted agents](https://github.com/actions/virtual-environments/blob/master/images/linux/Ubuntu1804-README.md).
- We set the Service Principal under which Terraform is running, as the [Azure AD Admin for SQL Server](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-aad-authentication-configure?tabs=azure-powershell#provision-an-azure-active-directory-administrator-for-your-managed-instance).
- When granting database roles to the managed identity, we create the external user via following T-SQL statement;
```sql
CREATE USER [<identity-name>] WITH default_schema=[dbo], SID=[<identity-sid>], TYPE=E;
```
instead of
```sql
CREATE USER [<identity-name>] FROM EXTERNAL PROVIDER;
```
When trying to execute non-interactively, the later T-SQL statement will fail with the following error;
```
Principal 'xyz' could not be created. Only connections established with Active Directory accounts can create other Active Directory users.
```
Many thanks to my colleague [Noel Bundick](https://www.noelbundick.com/) for pointing out to [this solution](https://github.com/microsoft/data-contest-toolkit/blob/noel/azure-infra/deploy/bootstrap/bootstrap.ps1) based on the [pseudo-documented SID hack](https://stackoverflow.com/questions/53001874/cant-create-azure-sql-database-users-mapped-to-azure-ad-identities-using-servic/56150547#56150547).

## Requirements
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
- [kubectl](https://docs.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-install-cli)
- [PowerShell](https://github.com/PowerShell/PowerShell#get-powershell)
- [Terraform](https://www.terraform.io/downloads.html)
- [Terraform authenticated via Service Principal](https://www.terraform.io/docs/providers/azurerm/guides/service_principal_client_secret.html)
>**Note:** This template performs [Azure AD role assignments](https://docs.microsoft.com/en-us/azure/role-based-access-control/overview) required by AAD Pod Identity. Therefore the Service Principal used for Terraform authentication must be created with `Owner` privileges.

## Azure resources
- Azure SQL Database
- User-Assigned Managed Identity
- AKS Cluster

## Smoke Test
Once `terraform apply` has successfully completed, fill the following variables from the Terraform output;
```sh
export aad_pod_id_binding_selector="aad-pod-id-binding-selector"
export aks_cluster_name="aks-xxxxxx"
export rg_name="rg-xxxxxx"
export sql_db_name="sqldb-test"
export sql_server_fqdn="sql-xxxxxx"
```

Then;
```
./smoke_test.sh
```

The smoke test will create a test pod in the newly provisioned AKS cluster and will attempt to authenticate to the SQL DB from the pod using managed identity. Once authentication is successful it will perform DDL and CRUD operations to validate the database roles.
