# This script is update automatically by MarketInvoice.BuildAutomation package

# Get the FullName of NuGet executable
function script:Get-NuGetExecutable {
    Join-Path $SolutionFullPath "\.nuget\NuGet.exe"
}

# Restore NuGet packages for the solution
function script:Restore-NuGetPackages {
    Initialize-NuGetExecutable
    Invoke-Command -ErrorAction Stop -ScriptBlock { & $(Get-NuGetExecutable) restore "$SolutionFullName" -PackagesDirectory $(Get-PackagesDir) }
    if ($LASTEXITCODE) {
        Write-BuildMessage -Message "Error restoring NuGet packages" -ForegroundColor "Red"
        exit $LASTEXITCODE
    }
}

# Initalize the NuGet executable by downloading it if not found
function script:Initialize-NuGetExecutable {
    $NuGet = Get-NuGetExecutable
    if(-not (Test-Path $NuGet -PathType Leaf) -or -not (Test-Path $NuGet)) {
        # Download
        New-Directory (Split-Path $NuGet) | Out-Null
        # Installing NuGet command line https://docs.nuget.org/consume/command-line-reference
        "Downloading NuGet.exe"
	    $(New-Object System.Net.WebClient).DownloadFile("https://dist.nuget.org/win-x86-commandline/latest/nuget.exe", $NuGet)
    }
}

# Get the NuGet packages directory
function script:Get-PackagesDir {
    $PackagesDir = Join-Path $SolutionFullPath "packages" 
    $NuGet = Get-NuGetExecutable
    if (Test-Path $NuGet) {
		Push-Location -Path (Split-Path $NuGet)
        try {
            $RepositoryPath = Invoke-Command -ScriptBlock { & $NuGet config repositoryPath -AsPath 2>$1 }
            if ((-not [string]::IsNullOrWhiteSpace($RepositoryPath)) -and (Test-Path $RepositoryPath -PathType Container -IsValid)) { 
                $PackagesDir = $RepositoryPath
            }
        } catch {
		} finally {
			Pop-Location
		}
    }
    return $PackagesDir
}

# Write a message to the host with custom background and foreground color
function script:Write-BuildMessage {
	param(
        [Parameter(ValueFromPipeline=$true,Mandatory=$true)][string]$Message,
        [string]$BackgroundColor = $Host.UI.RawUI.BackgroundColor,
        [string]$ForegroundColor = $Host.UI.RawUI.ForegroundColor
    )

    $CurrentBackgroundColor = $Host.UI.RawUI.BackgroundColor
    $CurrentForegroundColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.BackgroundColor = $BackgroundColor
    $Host.UI.RawUI.ForegroundColor = $ForegroundColor
    $Message
    $Host.UI.RawUI.BackgroundColor = $CurrentBackgroundColor
    $Host.UI.RawUI.ForegroundColor = $CurrentForegroundColor
}

<#
Search the project $ProjectName within $ProjectFullPath
Returns the full name
#>
function script:Search-DefaultProjectFullName {
    param([string]$Name = $ProjectName)

    Get-ChildItem $ProjectFullPath | Where { $_.Name -match ".*$Name\.\w+proj$" } | Select -ExpandProperty FullName -First 1
}

<#
Get an array representing all the projects in the solution
Project properties:
- Name (e.g 'Project')
- File (e.g 'Project.csproj')
- Directory (full path, e.g 'C:\Source\Solution_dir\Project_dir')
#>
function script:Get-SolutionProjects {
	$Solution = "$(Join-Path "$SolutionFullPath" "$SolutionName").sln"
	If(Test-Path "$Solution") {
		$projects = @()
			Get-Content "$Solution" |
			Select-String 'Project\(' |
				ForEach {
					$ProjectParts = $_ -Split '[,=]' | ForEach { $_.Trim('[ "{}]') };
					if($ProjectParts[2] -match ".*\.\w+proj$") {
						$ProjectPathParts = $ProjectParts[2].Split("\");
						$Projects += New-Object PSObject -Property @{
							Name = $ProjectParts[1];
							File = $ProjectPathParts[-1];
							Directory = Join-Path "$SolutionFullPath" $ProjectParts[2].Replace("\$($ProjectPathParts[-1])", "");
						}
					}
				}
		return $Projects
	}
}

<#
Get an array representing all the test projects in the solution (name ending in 'Tests')
Project properties:
- <See Get-SolutionProjects>
- Type (e.g. 'UnitTests')
#>
function script:Get-SolutionTestProjects {
	Get-SolutionProjects | Where { $_.Name.EndsWith("Tests") } | Select Name, File, Directory, @{Name="Type";Expression={$_.Name -split '\.' | Select -Last 1}}
}

<#
Get an array representing all the NuGet packages installed in the solution
Package properties:
- id (e.g. 'NUnit')
- version (e.g. '3.2.0')
#>
function script:Get-SolutionPackages {
    $Packages = @()
    foreach($Project in Get-SolutionProjects) {
        $PackagesConfig = Join-Path $Project.Directory "packages.config"
        if(Test-Path $PackagesConfig) {
            $Packages += ([xml](Get-Content -Path "$PackagesConfig")).packages.package
        }
    }

    return ($packages | Select -Unique id, version | Sort id, version)
}

# The the package directroy for a given NuGet package id
function script:Get-PackageDir {
	param([Parameter(ValueFromPipeline=$true,Mandatory=$true)][AllowEmptyString()][string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) { 
        throw "PackageId cannot be empty"
    }

    $MatchingPackages = (Get-SolutionPackages | Where { $_.id -ieq $PackageId })

    if ($MatchingPackages.Count -eq 0) {
        throw "Cannot find '$PackageId' NuGet package in the solution"
    } elseif ($MatchingPackages.Count -gt 1) {
		throw "Found multiple versions of '$PackageId' NuGet package installed in the solution"
    }

    return Join-Path (Get-PackagesDir) ($MatchingPackages[0].id + '.' + $MatchingPackages[0].version)
}

<#
Import the tasks found in order
- .build\tasks
- any MarketInvoice.BuildAutomation.* package installed
#>
function script:Import-Task {
    param([Parameter(Mandatory=$true)][string[]]$Tasks)

    Import-File -Files $Tasks -Path "tasks"
}

<#
Import the tasks found in order
- .build\scripts
- any MarketInvoice.BuildAutomation.* package installed
#>
function script:Import-Script {
    param([Parameter(Mandatory=$true)][string[]]$Scripts)

    Import-File -Files $Scripts -Path "scripts"
}


<#
Import files within the current project and any BuildAutomation.* package installed within a given path
$Files = an array of ps1 file names (without extension, e.g. Script1,Script2,Script3)
$Path = the local directory containing the file (e.g. tasks), which is in order
 - .build for the current project
 - the root directory of any MarketInvoice.BuildAutomation.*
#>
function script:Import-File {
    param(
        [Parameter(Mandatory=$true)][string[]]$Files,
        [Parameter(Mandatory=$true)][string]$Path
    )

    # Define the historical list of imported files
    if (-not (Test-Path variable:script:MarketInvoiceBuildAutomationImportedFiles)) {
        $script:MarketInvoiceBuildAutomationImportedFiles = @()
    }

    # List of directories in which we search the file
    $Directories = @()
    $Directories += $BuildFullPath
    foreach ($Package in (Get-SolutionPackages | Where { $_.id -match "^MarketInvoice\.BuildAutomation\.*" })) {
        $Directories += Get-PackageDir $Package.id
    }

    foreach($File in $Files) {
        $FilePath = Join-Path $Path "$File.ps1"
        foreach($Directory in $Directories) {
            $FileFullPath = Join-Path $Directory $FilePath
            if ((Test-Path $FileFullPath) -and ($script:MarketInvoiceBuildAutomationImportedFiles -notcontains $FileFullPath)) {
                . $FileFullPath
                $script:MarketInvoiceBuildAutomationImportedFiles += $FileFullPath
                break
            }
        }
        if ($script:MarketInvoiceBuildAutomationImportedFiles -notcontains $FileFullPath) {
            throw "Cannot import $File"
        }
    }
}

<#
Import the properties script for a give BuildAutomation.* package
It does always import .build\scripts\Properties.ps1 (if found)
#>
function script:Import-Properties {
    param([string[]]$Packages)

    # Define the historical list of imported properties
    if (-not (Test-Path variable:script:MarketInvoiceBuildAutomationImportedProperties)) {
        $script:MarketInvoiceBuildAutomationImportedProperties = @()
    }

    $PropertiesPath = "scripts\Properties.ps1"

    # Always import solution properties
    $SolutionProperties = Join-Path $BuildFullPath $PropertiesPath
    if ((Test-Path $SolutionProperties) -and ($script:MarketInvoiceBuildAutomationImportedProperties -notcontains $SolutionProperties)) {
        . $SolutionProperties
        $script:MarketInvoiceBuildAutomationImportedProperties += $SolutionProperties
    }

    # Import properties from packages
    $SolutionPackages = Get-SolutionPackages
    foreach ($Package in $Packages) {
        if ($SolutionPackages | Where { $_.id -eq $Package }) {
            $PackageProperties = Join-Path (Get-PackageDir $Package) $PropertiesPath
            If ((Test-Path $PackageProperties) -and ($script:MarketInvoiceBuildAutomationImportedProperties -notcontains $PackageProperties)) {
                . $PackageProperties
                $script:MarketInvoiceBuildAutomationImportedProperties += $PackageProperties
            }
        }
    }
}

# Set the default project
function script:Set-Project {
    param([string]$Name)

    $private:Project = Get-SolutionProjects | Where { $_.Name -eq $Name } | Select -First 1

    if (-not $private:Project) {
        Write-BuildMessage -Message "Cannot find project $Name" -ForegroundColor "Yellow"
        # Find first project in the solution
        $private:Project = Get-SolutionProjects | Select -First 1
        $script:ProjectFullPath = $private:Project.Directory
        $script:ProjectName = $private:Project.Name
        Write-BuildMessage -Message "Using default project $script:ProjectName" -ForegroundColor "Yellow"
    } else {
        Write-BuildMessage -Message "Set default project $Name" -ForegroundColor "Yellow"
        $script:ProjectName = $Name
        $script:ProjectFullPath = $private:Project.Directory
    }
    $script:ProjectFullName = Search-DefaultProjectFullName
    $script:ArtifactFullPath = Join-Path $BuildOutputFullPath $script:ProjectName

    # Re-evaluate properties
    foreach ($Properties in $script:MarketInvoiceBuildAutomationImportedProperties) {
        . $Properties
    }
}

# Silently remove an item (no output)
function script:Remove-ItemSilently {
	param([parameter(ValueFromPipeline)][string]$Item)

	Remove-Item -Path "$Item" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path "$Item") {
        # Ensure removal of directories exceeding the 260 characters limit
        Get-ChildItem -Directory -Path "$Item" | ForEach { CMD /C "RD /S /Q ""$($_.FullName)""" }
    }
}

# Create a new directory if not found
function script:New-Directory {
	param([string]$Path)

	if (-not (Test-Path "$Path")) { 
        New-Item -ItemType Directory -Path "$Path" -Force
    } else {
        Get-Item -Path "$Path"
    }
}

<#
Push the NuGet package to a given source
Default push source is nuget.org
#>
function script:Push-Package {
	[CmdletBinding(DefaultParameterSetName="DefaultPushSource")] 
	param(		
		[Parameter(Mandatory=$true)]
		[string[]]$Packages,

		[Parameter(Mandatory=$true,ParameterSetName="DefaultPushSourceWithKey")]
		[Parameter(Mandatory=$true,ParameterSetName="SourceWithKey")]
		[string]$ApiKey,
		
		[Parameter(Mandatory=$true,ParameterSetName="Source")]
		[Parameter(Mandatory=$true,ParameterSetName="SourceWithKey")]
		[string]$Source
	)

    $NuGet = Get-NuGetExecutable

	foreach($Package in $Packages) {
		switch ($PsCmdlet.ParameterSetName) {
			"DefaultPushSource"  { Exec { & $NuGet push "$Package" -NonInteractive } }
			"DefaultPushSourceWithKey" { Exec { & $NuGet push "$Package" -ApiKey $ApiKey -NonInteractive } }
			"Source"  { Exec { & $NuGet push "$Package" -Source $Source -NonInteractive } }
			"SourceWithKey" { Exec { & $NuGet push "$Package" -ApiKey $ApiKey -Source $Source -NonInteractive } }
		}
	}
}

# Remove recursively any Program Database file found in a given path
function script:Remove-PdbFiles {
	param([string]$Path)

	foreach($Item in (Get-ChildItem -Path "$Path" -Recurse -File -Include *.pdb | Select-Object -ExpandProperty FullName)) {
        Remove-ItemSilently $Item
    }
}

# Get the build output directory given a project's name
function script:Get-ProjectBuildOutputDir {
    param([Parameter(Mandatory=$true,ValueFromPipeline=$true)][string]$ProjectName)

	Begin { $Result = @() }
	
    Process {
        $Directory = Get-SolutionProjects | Where { $_.Name -eq $ProjectName } | Select -First 1 -ExpandProperty Directory
        Assert ($Directory -and (Test-Path $Directory)) "Cannot find project $ProjectName in $Directory"
		if ($Platform -and $Configuration -and (Test-Path (Join-Path $Directory "bin\$Platform\$Configuration"))) {
			# Project directory with platform and build configuration
			$Result += Join-Path $Directory "bin\$Platform\$Configuration"
		} elseif ($Configuration -and (Test-Path (Join-Path $Directory "bin\$Configuration"))) {
			# Project directory with build configuration
			$Result += Join-Path $Directory "bin\$Configuration"
		} elseif (Test-Path (Join-Path $Directory "bin")) {
			# Project directory with bin folder
			$Result += Join-Path $Directory "bin"
		}
	}

	End { 
        if ($Result.Count -eq 1) { 
            $Result[0] 
        } else { 
            $Result 
        } 
    }
}

# Select and validate the project to build
function script:Select-BuildProject {
    if ($BuildProjectOnly -eq $true) {
        $Project = $ProjectFullName
    } else {
        $Project = $SolutionFullName
    }
    Assert ($Project -and (Test-Path $Project)) "Cannot not find '$Project'"
    return $Project
}

# Get the FullName of dotCover executable
function script:Get-dotCoverExecutable {
    Join-Path (Get-PackageDir "JetBrains.dotCover.CommandLineTools") "tools\dotCover.exe"
}

# Get the scope of assemblies whose information should be added to the dotCover snapshot given a list of test assemblies
function script:Get-dotCoverScope {
    param([string[]]$Assemblies)

    # NuGet package dependencies to exclude from the scope
    $Packages = Get-ChildItem -Path $(Get-PackagesDir) -Recurse -File -Include "*.dll" `
                | Sort -Property BaseName -Unique `
                | Select -ExpandProperty BaseName

    # Add all projects
    $ScopeFullPath = Get-SolutionProjects | Select -ExpandProperty Name | Get-ProjectBuildOutputDir
		
    if (Test-Path $ArtifactFullPath) {
        # If the artifact has been created
        $ScopeFullPath += $ArtifactFullPath
    }
	
    # Add test assemblies directories
    $ScopeFullPath += $Assemblies | Split-Path

    # Return filtered list of assemblies
    return ($ScopeFullPath | Get-ChildItem -Recurse -File -Include @("*.dll","*.exe") `
            | Where { -not $_.BaseName.EndsWith("Tests") -and $Packages -notcontains $_.BaseName -and (Split-Path (Split-Path $_.FullName) -Leaf) -ne "roslyn" } `
            | Sort -Property BaseName -Unique `
            | Select -ExpandProperty FullName) -Join ";"
}

<#
Invoke MSpec against a list of assemblies
Requires Machine.Specifications.Runner.Console and JetBrains.dotCover.CommandLineTools (if code coverage is enabled)
#> 
function script:Invoke-MSpec {
    param([string[]]$Assemblies)

    $Assemblies = Get-ChildItem -Path $Assemblies | Where { Test-Path (Join-Path (Split-Path $_.FullName) "Machine.Specifications.dll") } | Select -ExpandProperty FullName

    if ($Assemblies) {
        "`r`nRunning MSpec Tests"
        $MSpec = Join-Path (Get-PackageDir "Machine.Specifications.Runner.Console") "tools\mspec-clr4.exe"
        $MSpecTestsResults = Join-Path $TestsResultsFullPath "MSpec.xml"
        New-Directory $TestsResultsFullPath | Out-Null

        if ($CodeCoverage -eq $true) {
            $dotCover = Get-dotCoverExecutable
            $dotCoverOutput = Join-Path $TestsResultsFullPath "MSpec.dotCover.Snapshot.dcvr"
            $dotCoverScope = Get-dotCoverScope $Assemblies
            Remove-ItemSilently $dotCoverOutput

            $MSpecAssemblies = $Assemblies -join "`"`" `"`""
            $MSpecArguments = "--xml `"`"$MSpecTestsResults`"`" --progress `"`"$MSpecAssemblies`"`""

            Exec { & "$dotCover" cover /TargetExecutable="$MSpec" /TargetArguments="$MSpecArguments" /Output="$dotCoverOutput" /Scope="$dotCoverScope" /Filters="`"$dotCoverFilters`"" /AttributeFilters="`"$dotCoverAttributeFilters`"" /ReturnTargetExitCode }
        } else {
            Exec { & "$MSpec" --xml $MSpecTestsResults --progress $Assemblies }
        }
    } else {
        Write-Build "Yellow" "MSpec tests not found"
    }
}

<#
Invoke NUnit against a list of assemblies
Requires NUnit.Runners.2.x and JetBrains.dotCover.CommandLineTools (if code coverage is enabled)
#> 
function script:Invoke-NUnit2 {
    param([string[]]$Assemblies)

    $Assemblies = Get-ChildItem -Path $Assemblies | Where { Test-Path (Join-Path (Split-Path $_.FullName) "nunit.framework.dll") } | Select -ExpandProperty FullName

    if ($Assemblies) {
        "`r`nRunning NUnit Tests"
        $NUnit = Join-Path (Get-PackageDir "NUnit.Runners") "tools\nunit-console.exe"
        $NUnitTestsResults = Join-Path $TestsResultsFullPath "NUnit.xml"
        New-Directory $TestsResultsFullPath | Out-Null

        if ($CodeCoverage -eq $true) {
            $dotCover = Get-dotCoverExecutable
            $dotCoverOutput = Join-Path $TestsResultsFullPath "NUnit.dotCover.Snapshot.dcvr"
            $dotCoverScope = Get-dotCoverScope $Assemblies
            Remove-ItemSilently $dotCoverOutput

            $NUnitAssemblies = $Assemblies -join "`"`" `"`""
            $NUnitArguments = "/work:`"`"$TestsResultsFullPath`"`" /result:`"`"$NUnitTestsResults`"`" /framework:`"`"net-$NUnitFrameworkVersion`"`" /nologo `"`"$NUnitAssemblies`"`""

            Exec { & "$dotCover" cover /TargetExecutable="$NUnit" /TargetArguments="$NUnitArguments" /Output="$dotCoverOutput" /Scope="$dotCoverScope" /Filters="`"$dotCoverFilters`"" /AttributeFilters="`"$dotCoverAttributeFilters`"" /ReturnTargetExitCode }
        } else {
            Exec { & "$NUnit" /work:"$TestsResultsFullPath" /result:"$NUnitTestsResults" /framework:"net-$NUnitFrameworkVersion" /nologo $Assemblies }
        }
    } else {
        Write-Build "Yellow" "NUnit tests not found"
    }
}

<#
Invoke NUnit against a list of assemblies
Requires NUnit.ConsoleRunner.3+ and JetBrains.dotCover.CommandLineTools (if code coverage is enabled)
#> 
function script:Invoke-NUnit {
    param([string[]]$Assemblies)

    $Assemblies = Get-ChildItem -Path $Assemblies | Where { Test-Path (Join-Path (Split-Path $_.FullName) "nunit.framework.dll") } | Select -ExpandProperty FullName

    if ($Assemblies) {
        "`r`nRunning NUnit Tests"
        $NUnit = Join-Path (Get-PackageDir "NUnit.ConsoleRunner") "tools\nunit3-console.exe"
        $NUnitTestsResults = Join-Path $TestsResultsFullPath "NUnit.xml"
        New-Directory $TestsResultsFullPath | Out-Null

        if ($CodeCoverage -eq $true) {
            $dotCover = Get-dotCoverExecutable
            $dotCoverOutput = Join-Path $TestsResultsFullPath "NUnit.dotCover.Snapshot.dcvr"
            $dotCoverScope = Get-dotCoverScope $Assemblies
            Remove-ItemSilently $dotCoverOutput

            $NUnitAssemblies = $Assemblies -join "`"`" `"`""
            $NUnitArguments = "--work:`"`"$TestsResultsFullPath`"`" --result:`"`"$NUnitTestsResults`"`" --noheader `"`"$NUnitAssemblies`"`""

            Exec { & "$dotCover" cover /TargetExecutable="$NUnit" /TargetArguments="$NUnitArguments" /Output="$dotCoverOutput" /Scope="$dotCoverScope" /Filters="`"$dotCoverFilters`"" /AttributeFilters="`"$dotCoverAttributeFilters`"" /ReturnTargetExitCode }
        } else {
            Exec { & "$NUnit" --work:"$TestsResultsFullPath" --result:"$NUnitTestsResults" --noheader $Assemblies }
        }
    } else {
        Write-Build "Yellow" "NUnit tests not found"
    }
}

<#
Merge dotCover snapshots found in TestsResultsFullPath and generates a report
#> 
function script:Merge-dotCoverSnapshots {
	param([string]$SnapshotsRegex = "*.dcvr", [string]$MergedSnapshotName = "dotCover.Snapshot.dcvr")

    if ($CodeCoverage -eq $false -or -not $TestsResultsFullPath -or -not (Test-Path $TestsResultsFullPath)) {
        return;
    }

    $MergedSnapshot = Join-Path $TestsResultsFullPath $MergedSnapshotName
    if (Test-Path $MergedSnapshot) {
        # If the merged snapshot already exists, rename it
        Move-Item $MergedSnapshot (Join-Path $TestsResultsFullPath "tmp$(Get-Random 100).$MergedSnapshotName")
    }

    $Snapshots = Get-ChildItem $TestsResultsFullPath -Filter "$SnapshotsRegex" | Select -ExpandProperty FullName
    $dotCoverReport = Join-Path $TestsResultsFullPath $dotCoverReportName
    if (Test-Path $dotCoverReport) {
        Remove-ItemSilently (-join ((Get-ChildItem $dotCoverReport).BaseName, "*"))
    }

    if($Snapshots) {
        "`r`nMerge dotCover Snapshots"
        $dotCover = Get-dotCoverExecutable
        $Source = $Snapshots -join ';'
		Exec { & "$dotCover" merge /Source="$Source" /Output="$MergedSnapshot" }
        "`r`nGenerate dotCover Report"
		Exec { & "$dotCover" report /Source="$MergedSnapshot" /Output="$dotCoverReport" /ReportType="$dotCoverReportType" }
    } else {
        Write-Build "Yellow" "`r`ndotCover snapshots not found"
    }
}

# Get the last committer date
function script:Get-CommitterDate {
    $Date = exec { git show --no-patch --format=%ci }

    [DateTime]::Parse($Date, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
}

# Get the current branch name
function script:Get-Branch {	
    $RawName = exec { git name-rev --name-only HEAD }
    
    if ($RawName -match '/([^/]+)$') {
        # In this case we resolved refs/heads/branch_name but we are only interested in branch_name
        $Name = $Matches[1]
    } else {
        $Name = $RawName
    }

    # If the current revision is behind HEAD, strip out such information from the name (e.g. master~1)
    return ($Name -replace "[~]\d+", "") | Select @{Name="Name"; Expression={$_}}, @{Name="IsMaster"; Expression={$_ -eq "master"}}
}

# Get the version object based on last committer date
function script:Get-Version {
    $CommitterDate = Get-CommitterDate
    $Branch = Get-Branch

    $Major = $CommitterDate.Year
    $Minor = $CommitterDate.Month.ToString("D2")
    $Build = $CommitterDate.Day.ToString("D2")
    $Revision = "$($CommitterDate.Hour.ToString('D2'))$($CommitterDate.Minute.ToString('D2'))$($CommitterDate.Second.ToString('D2'))"
    $PreReleaseLabel = if ($Branch.IsMaster) { "" } else { $Branch.Name[0..19] -join "" }
    $InformationalVersion = if ($PreReleaseLabel) { "$Major.$Minor.$Build.$Revision-$PreReleaseLabel" } else { "$Major.$Minor.$Build.$Revision" }

    return New-Object PSObject -Property @{
        Major = $Major;
        Minor = $Minor;
        Patch = "$Build$Revision";
        PreReleaseLabel = $PreReleaseLabel;
        Build = $Build;
        Revision = $Revision;
        SemVer = $InformationalVersion
        # Remove the Seconds from $Revision due to build numbers limited to 65535
        AssemblySemVer = "$Major.$Minor.$Build.$($Revision -replace '.{2}$')";
        InformationalVersion = $InformationalVersion
    }
}

# Get the version object following semantic versioning
function script:Get-SemanticVersion {
    param([string]$SemanticVersion)

    $VersionParts = $SemanticVersion.Split(".")
    $PatchParts = $VersionParts[2].Split("-")

    $Major = $VersionParts[0]
    $Minor = $VersionParts[1]
    $Patch = $PatchParts[0]
    
    $PreReleaseLabel = $PatchParts[1]
    if (-not (Get-Branch).IsMaster -and -not $PreReleaseLabel) {
        # Set pre-release label if not in master
        $CommitterDate = Get-CommitterDate
        $PreReleaseLabel = "pre$($CommitterDate.Year)$($CommitterDate.Month.ToString('D2'))$($CommitterDate.Day.ToString('D2'))$($CommitterDate.Hour.ToString('D2'))$($CommitterDate.Minute.ToString('D2'))$($CommitterDate.Second.ToString('D2'))"
    }

    $SemVer = if ($PreReleaseLabel) { "$Major.$Minor.$Patch-$PreReleaseLabel" } else { "$Major.$Minor.$Patch" }
    
    return New-Object PSObject -Property @{
        Major = $Major;
        Minor = $Minor;
        Patch = $Patch;
        PreReleaseLabel = $PreReleaseLabel;
        Build = $Patch;
        Revision = 0;
        SemVer = $SemVer
        AssemblySemVer = "$Major.$Minor.$Patch.0";
        InformationalVersion = $SemVer
    }
}

# Get the version object following semantic versioning from the default project's Version.txt
function script:Get-ProjectSemanticVersion {
    $VersionFile = Join-Path $ProjectFullPath "Version.txt"
    Assert (Test-Path $VersionFile) "Cannot find version file $VersionFile"
    Get-SemanticVersion (Get-Content $VersionFile | ? { $_.Trim() -ne '' }).Trim()
}