#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"

# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
$token = curl "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://database.windows.net/" -H "Metadata: true" | ConvertFrom-Json

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Data Source=$Env:server; Initial Catalog=$Env:database;"
$conn.AccessToken = $token.access_token

$conn.Open()
Write-Output "Connected to $Env:server/$Env:database using Managed Identity"

try {
    $cmd = New-Object System.Data.SqlClient.SqlCommand
    $cmd.Connection = $conn

    # Generate a random table name
    $table = "dbo.table_" + -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object {[char]$_})

    Write-Output "Creating $table ..."
    $cmd.CommandText = "CREATE TABLE $table (ID INT);"
    $cmd.ExecuteNonQuery()

    Write-Output "Inserting into $table ..."
    $cmd.CommandText = "INSERT INTO $table VALUES (1);"
    $cmd.ExecuteNonQuery()

    Write-Output "Reading $table ..."
    $cmd.CommandText = "SELECT * FROM $table;"
    $cmd.ExecuteNonQuery()

    Write-Output "Deleting from $table ..."
    $cmd.CommandText = "DELETE FROM $table;"
    $cmd.ExecuteNonQuery()

    Write-Output "Dropping $table ..."
    $cmd.CommandText = "DROP TABLE $table;"
    $cmd.ExecuteNonQuery()
}
finally {
    $conn.Close()
}
