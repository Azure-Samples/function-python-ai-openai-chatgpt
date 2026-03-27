$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\local.settings.json")) {

    $output = azd env get-values

    # Parse the output to get the endpoint values
    foreach ($line in $output) {
        if ($line -match "PROJECT_ENDPOINT"){
            $AIProjectEndpoint = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "STORAGE_CONNECTION__queueServiceUri"){
            $StorageConnectionQueue = ($line -split "=")[1] -replace '"',''
        }
        if ($line -match "MODEL_DEPLOYMENT_NAME"){
            $ModelDeploymentName = ($line -split "=")[1] -replace '"',''
        }
    }

    @{
        "IsEncrypted" = "false";
        "Values" = @{
            "AzureWebJobsStorage" = "UseDevelopmentStorage=true";
            "FUNCTIONS_WORKER_RUNTIME" = "dotnet-isolated";
            "PROJECT_ENDPOINT" = "$AIProjectEndpoint";
            "MODEL_DEPLOYMENT_NAME" = "$ModelDeploymentName";
            "STORAGE_CONNECTION__queueServiceUri" = "$StorageConnectionQueue";
        }
    } | ConvertTo-Json | Out-File -FilePath ".\local.settings.json" -Encoding ascii
}