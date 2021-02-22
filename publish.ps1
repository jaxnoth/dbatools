[CmdletBinding()]
param (
    [string]
    $Repository = 'Test',

    [string]
    $StagingFolder = 'Staging',

    [string[]]
    $FilesToSign = @(
        '*.ps*1',
        'bin\library.ps1',
        'bin\typealiases.ps1',
        'internal\configurations\configuration.ps1',
        'internal\scripts\*.ps1',
        'optional\*.ps1',
        'xml\*.ps1xml'
    ),

    [switch] $SkipCompile,
    [switch] $CompileOnly,
    [switch] $SkipCleanup
)

$OriginalModuleName = "dbatools"
$PublishedModuleName = "IWU.dbatools"
Push-Location $PSScriptRoot

# Re-compile allcommands.ps1 and en-us/dbatools-help.xml
if (-not $SkipCompile) {
    $msg = "Compiling allcommands.ps1 and dbatools-help.xml for release"
    Write-Progress $msg
    Remove-Module $OriginalModuleName -ea Ignore
    Import-Module ".\$OriginalModuleName.psd1"
    HelpOut\Install-MAML $OriginalModuleName -Compact -NoVersion -FunctionRoot functions, internal\functions
    Remove-Module $OriginalModuleName
    if ($CompileOnly) {
        Pop-Location
        return
    }
    Write-Progress $msg -Completed
}

# Stage files for Publish-Module
$msg = "Staging files to $StagingFolder"
$ModulePath = "$StagingFolder\$PublishedModuleName"
if ([IO.Path]::GetFileName($StagingFolder) -eq $PublishedModuleName) {
    $ModulePath = $StagingFolder
}
Write-Progress $msg
Remove-Item $ModulePath -Recurse -Force -ea Ignore
New-Item $ModulePath -Type Directory | Out-Null
Copy-Item "$OriginalModuleName.psd1" "$ModulePath\$PublishedModuleName.psd1"
$ExcludeFromRoot = @(
    $StagingFolder, "$OriginalModuleName.psd1",
    ".git*", ".vscode", "bin", "tests",
    "appveyor.yml", "codecov.yml", "publish.ps1"
)
Copy-Item * $ModulePath -Recurse -Exclude $ExcludeFromRoot
New-Item $ModulePath\bin -Type Directory | Out-Null
$ExcludeFromBin = @(
    "build", "projects", "StructuredLogger.dll"
)
Copy-Item bin\* $ModulePath\bin -Recurse -Exclude $ExcludeFromBin
Write-Progress $msg -Completed

# Sign Files
$msg = "Signing files"
Write-Progress $msg
$certName = 'IWU Code Signing'
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.FriendlyName -eq $certName }
$i = 0
if (-not ($cert -is [System.Security.Cryptography.X509Certificates.X509Certificate2])) {
    Write-Error "Cannot find a certificate with friendly name '$certName' to use for signing."
    return
}
foreach ($file in $FilesToSign) {
    Write-Progress $msg "Signing $file" -PercentComplete (100 * $i++ / $FilesToSign.Count)
    Set-AuthenticodeSignature $ModulePath\$file $cert -TimestampServer http://timestamp.digicert.com | % {
        if ($_.Status -ne 'Valid') {
            Write-Warning "Failed to sign $($_.Path)"
        }
    }
}
Write-Progress $msg -Completed

# Publish Module
$msg = "Publishing $PublishedModuleName to the ""$Repository"" repository"
Write-Progress $msg
Publish-Module -Path $ModulePath -Repository $Repository
Write-Progress $msg -Completed

# Clean up
if (-not $SkipCleanup) {
    $msg = "Deleting the staging folder [$StagingFolder]"
    Write-Progress $msg
    Remove-Item $ModulePath -Recurse -Force
    if (-not (Get-ChildItem $StagingFolder -ea Ignore)) {
        Remove-Item $StagingFolder -ea Ignore
    }
    Write-Progress $msg -Completed
}

Pop-Location