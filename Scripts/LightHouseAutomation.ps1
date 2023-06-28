function LightHouseConnection{
    $AutomationAppsObject = (AzADGroup -SearchString Automation).Id
    $SentinelResponderRole = (Get-AzRoleDefinition -Name "Azure Sentinel Responder").Id
    
    #Need to change the param generation to splatting. 
        $TenantId = $HomeContext
        #Creates our hashtable to utilize for the parameters for the JSON file.
        $parameters = [ordered]@{
            mspOfferName = @{
                value = "Ntirety Lighthouse SOC"
            }
            mspOfferDescription = @{
                value = "Ntirety SOC access granted"
            }
            managedByTenantId = @{
                value = $TenantId
            }
            authorizations =@{
                value =@(
                    @{
                        principalId = $AutomationAppsObject
                        roleDefinitionId = $SentinelResponderRole
                        principalIdDisplayName = "Automation"
                    }  
                )
            }
        }
        #Define the resources for the parameter file using a hashtable. 
        $MainObject = [ordered]@{
            '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
            contentVersion = "1.0.0.0"
            parameters = $parameters
        }
    
        $DirectoryName = "/home/Sentinel" + (Get-Date -Format "MMddyyyyHHmm")
        $FilePath = New-Item -ItemType Directory $DirectoryName
    
        #Converts the above to a JSON formatted file to be used for the ARM template push. 
        $MainObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $FilePath/TemplateParam.json
    
        Write-Host 'Establishing Azure Lighthouse connection'
        $temp = Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/Azure-Lighthouse-samples/master/templates/delegated-resource-management/subscription/subscription.json -OutFile $FilePath/ArmTemplateDeploy.json 
        $temp = New-AzDeployment -TemplateFile $FilePath/ArmTemplateDeploy.json -TemplateParameterFile $FilePath/TemplateParam.json -Location $global:Location
    
        Remove-Item -Recurse -Path $FilePath
    }