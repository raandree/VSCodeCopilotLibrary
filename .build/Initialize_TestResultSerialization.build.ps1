task Initialize_TestResultSerialization {
	Update-TypeData -TypeName System.IO.FileInfo -SerializationMethod String -StringSerializationSource FullName -Force
	Update-TypeData -TypeName System.Management.Automation.PSDriveInfo -SerializationMethod String -StringSerializationSource Name -Force
	Update-TypeData -TypeName System.Management.Automation.ProviderInfo -SerializationMethod String -StringSerializationSource Name -Force
}
