#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"

# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
$token = curl "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://database.windows.net/" -H "Metadata: true" | ConvertFrom-Json

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Data Source=$Env:server; Initial Catalog=$Env:database;"
$conn.AccessToken = $token.access_token
$conn.Open()

Write-Output "Connected to $Env:server/$Env:database using Managed Identity"

$conn.Close()
