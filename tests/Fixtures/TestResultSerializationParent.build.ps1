param(
    [System.Management.Automation.PSModuleInfo] $Invoker,
    [hashtable] $Parameters
)

$fixtureState = @{ Invoker = $Invoker; Parameters = $Parameters }

task . {
    try {
        if ($fixtureState.Invoker) {
            & $fixtureState.Invoker {
                param($BuildParameters)
                Invoke-Build @BuildParameters
            } $fixtureState.Parameters
        }
        else {
            $childParameters = $fixtureState.Parameters
            Invoke-Build @childParameters
        }
    }
    catch {
        if ($_.Exception.Message -notlike '*Injected task failure*') { throw }
    }
}