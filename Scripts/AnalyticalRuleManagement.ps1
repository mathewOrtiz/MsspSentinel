$Subs = @(Get-AzSubscription).Id

$Subs.foreach(
{
    $Sentinel = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "True"}) | Select-Object -Property Name, ResourceGroupName

    $WorkspaceName = $Sentinel.Name

    $ResourceGroup = $Sentinel.ResourceGroupName

    $AnalyticalRules = @((Get-AzSentinelAlertRule -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName).Name)

    foreach($rule in $AnalyticalRules){
        New-Item -ItemType Directory $WorkspaceName
        $currentRule = Get-AzSentinelAlertRule -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName -RuleId $rule
        $filename = $currentRule.DisplayName -replace '[\\/:*?"<>|]', '_'
        $currentRule.Query| Out-File -FilePath $WorkspaceName "$filename.kql"

        #Now take the analytical rules that have been extracted and utilize this to place them into the correct directory structure
        New-Item -Path $WorkspaceName -ItemType Directory MicrosoftRules
        New-Item -Path $WorkspaceName -ItemType Directory AzureRules
        New-Item -Path $WorkspaceName -ItemType Directory PaloAlto
        New-Item -Path $WorkspaceName -ItemType Directory Linux

        #Loop through the analytical rules that we have imported into the current working directory
        $MicrosoftRules = @(Select-String -Path $WorkspaceName -SimpleMatch "[MS-]")
        $MicrosoftRules.ForEach({
            Move-Item -Path $WorkspaceName $_
        })
        $AzureRule = @(Select-String -Path $WorkspaceName -SimpleMatch "[Azure-]")
        $AzureRule.ForEach({
            Move-Item -Destination $WorkspaceName $_
        })
        $PaloAlto = @(Select-String -Path $WorkspaceName -SimpleMatch "[Palo-]")
        $PaloAlto.ForEach({
            Move-Item -Destination $WorkspaceName $_
        })
    }

#The below is the necessary code for the github integration


#First steps needs to prompt the user to input their github token for this use case. Alternatively we will look into changing this so that that user is prompted to authenticate to Keyvault.

Write-Host "Please enter your Github username and the token that you have been provided with to run this automation.

The team is working ot ensure that this automation can be run through the use of Azure keyvault so there is no need for local storage of indvidual tokens."

#The below should be taken using powershell secure cred input
Set-GitHubAuthentication


#Fork the existing repo.

#Use repo and name params 
New-GitHubRepositoryFork -OwnerName "NtiretySoc" -RepositoryName "Sentinel" -Name '$WorkSpaceName'

# We now need to initialize the repo locally so that we can edit the files that we would like.
Get-Command -ErrorAction SilentylContinue 
if((Get-Command -ErrorAction SilentlyContinue "git" )-eq $null ){
    Write-Host "We will now install the git module before proceeding"
    Install-Module -Name git
    if((Get-Command "git" -ErrorAction SilentlyContinue )-eq $null){
        Write-Host "We are unable to proceed with the process. Please ensure that you run through the troubleshooter.
        The Fork will need to be updated with the necessary info from what was pulled from the rules.
        "
    }else{
       $Repo =  Get-GitHubRepositoryFork -RepositoryName '$WorkspaceName' -OwnerName NtiretySoc
    }
    #This creates the necessary localized repo. We will work with the following using file moves in order to ensure our directory structure is correct.
    Set-Location $WorkSpaceName
    git clone $Repo.RepositortyUrl
    #We have the repo cloned in our directory which is holding all of our other analytical rule information.

    

}



    
})
