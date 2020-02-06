[CmdletBinding()]
param (
    [string]
    $Repository = 'Test',

    [string]
    $StagingFolder = 'Staging',

    [switch] $SkipCompile,
    [switch] $CompileOnly,
    [switch] $SkipCleanup
)

$OriginalModuleName = "dbatools"
$PublishedModuleName = "IWU.dbatools"
Push-Location $PSScriptRoot

# Re-compile allcommands.ps1 and en-us/dbatools-help.xml
if (-not $SkipCompile) {
    Remove-Module $OriginalModuleName -ea Ignore
    Import-Module ".\$OriginalModuleName.psm1"
    HelpOut\Install-MAML $OriginalModuleName -Compact -NoVersion -FunctionRoot functions, internal\functions
    Remove-Module $OriginalModuleName
    if ($CompileOnly) {
        Pop-Location
        return
    }
}

# Stage files for Publish-Module
$msg = "Staging files to $StagingFolder"
Write-Progress $msg
Remove-Item $StagingFolder -Recurse -Force -ea Ignore
if (-not (Test-Path $StagingFolder)) {
    New-Item $StagingFolder\$PublishedModuleName -Type Directory | Out-Null
}
Copy-Item "$OriginalModuleName.psd1" "$StagingFolder\$PublishedModuleName\$PublishedModuleName.psd1"
Copy-Item * $StagingFolder\$PublishedModuleName -Recurse -Exclude $StagingFolder, "$OriginalModuleName.psd1", .git*, .vscode, bin, tests, appveyor.yml, codecov.yml, publish.ps1
New-Item $StagingFolder\$PublishedModuleName\bin -Type Directory | Out-Null
Copy-Item bin\* $StagingFolder\$PublishedModuleName\bin -Recurse -Exclude build, projects, StructuredLogger.dll
Write-Progress $msg -Completed

# Publish Module
$msg = "Publishing $PublishedModuleName to the ""$Repository"" repository"
Write-Progress $msg
Publish-Module -Path $StagingFolder\$PublishedModuleName -Repository $Repository
Write-Progress $msg -Completed

# Clean up
if (-not $SkipCleanup) {
    $msg = "Deleting the staging folder [$StagingFolder]"
    Write-Progress $msg
    Remove-Item $StagingFolder -Recurse -Force
    Write-Progress $msg -Completed
}

Pop-Location