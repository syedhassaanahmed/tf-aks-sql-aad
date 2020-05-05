#!/usr/bin/env pwsh

[CmdletBinding()]
param (
   [Parameter(Mandatory = $true)]
   [string]
   $identityName,

   [Parameter(Mandatory = $true)]
   [string]
   $identityClientId,

   [Parameter(Mandatory = $true)]
   [string]
   $sqlSaConnectionString
)

$ErrorActionPreference = "Stop"

if (-Not (Get-Module -ListAvailable -Name SqlServer)) {
   Install-Module -Name SqlServer -Force -Scope CurrentUser
}

function ConvertTo-Sid {
   param (
      [string]$objectId
   )   

   [guid]$guid = [System.Guid]::Parse($objectId)

   foreach ($byte in $guid.ToByteArray()) {
       $byteGuid += [System.String]::Format("{0:X2}", $byte)
   }

   return "0x$byteGuid"
}

function Grant-AadObject {
   param (
      [string]$objectName,
      [string]$objectId,
      [string]$objectType
   )

   $sid = ConvertTo-Sid "$objectId"
   
   $grantQuery = @"
   IF EXISTS (SELECT name FROM sys.database_principals WHERE name = '$objectName')
   BEGIN
      DROP USER [$objectName];
   END
   
   CREATE USER [$objectName] WITH default_schema=[dbo], SID=$sid, TYPE=$objectType;
   ALTER ROLE db_datareader ADD MEMBER [$objectName];
   ALTER ROLE db_datawriter ADD MEMBER [$objectName];
   ALTER ROLE db_ddladmin ADD MEMBER [$objectName];
      
   GO
"@
   
   Invoke-Sqlcmd -ConnectionString $sqlSaConnectionString -Query $grantQuery
}

# Object type for Azure AD Users is 'E' and for Azure AD Groups is 'X'
Grant-AadObject "$identityName" "$identityClientId" "E"
