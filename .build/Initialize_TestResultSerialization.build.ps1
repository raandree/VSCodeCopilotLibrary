task Initialize_TestResultSerialization {
	$typeNames = @('System.IO.FileInfo', 'System.Management.Automation.PSDriveInfo', 'System.Management.Automation.ProviderInfo')
	$originalTypeData = @(Get-TypeData -TypeName $typeNames | ForEach-Object { $_.Copy() })
	$previousExit = ${*}.B1.ExitBuild
	$restoreTypeData = {
		try {
			foreach ($typeName in $typeNames) {
				if (Get-TypeData -TypeName $typeName) {
					Remove-TypeData -TypeName $typeName -ErrorAction Stop
				}
			}
			foreach ($typeData in $originalTypeData) {
				Update-TypeData -TypeData $typeData -Force -ErrorAction Stop
			}
		}
		finally {
			if ($previousExit) { . $previousExit }
		}
	}.GetNewClosure()
	Exit-Build $restoreTypeData
	foreach ($typeName in $typeNames) {
		if (Get-TypeData -TypeName $typeName) {
			Remove-TypeData -TypeName $typeName -ErrorAction Stop
		}
		$original = $originalTypeData | Where-Object TypeName -eq $typeName
		$typeData = if ($original) { $original.Copy() } else { [System.Management.Automation.Runspaces.TypeData]::new($typeName) }
		$typeData.SerializationMethod = 'String'
		$typeData.PropertySerializationSet = $null
		$typeData.StringSerializationSource = if ($typeName -eq 'System.IO.FileInfo') { 'FullName' } else { 'Name' }
		Update-TypeData -TypeData $typeData -Force -ErrorAction Stop
	}
}
