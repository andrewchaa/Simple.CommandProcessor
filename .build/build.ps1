Import-Properties
Import-Task Clean, Version-Assemblies, Version-BuildServer, Build, Test, Pack, Push, New-Artifact

# Synopsis: Initialize the Notifications API
Task . Clean, Build, Test, {
@"
/  __ \                                         | | ___ \                                      
| /  \/ ___  _ __ ___  _ __ ___   __ _ _ __   __| | |_/ / __ ___   ___ ___  ___ ___  ___  _ __ 
| |    / _ \| '_ ' _ \| '_ ' _ \ / _' | '_ \ / _' |  __/ '__/ _ \ / __/ _ \/ __/ __|/ _ \| '__|
| \__/\ (_) | | | | | | | | | | | (_| | | | | (_| | |  | | | (_) | (_|  __/\__ \__ \ (_) | |   
 \____/\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|\__,_\_|  |_|  \___/ \___\___||___/___/\___/|_|   
"@
}

# Synopsis: Build the Command Processor
Task Build-CommandProcessor {
    $script:Version = Get-ProjectSemanticVersion
	$script:CodeCoverage = $false
}, Version-BuildServer, Clean, Version-Assemblies, Build, Test, New-Artifact, Pack

