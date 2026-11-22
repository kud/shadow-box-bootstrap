@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Coloured console output is the whole user interface of these scripts.
        'PSAvoidUsingWriteHost'
        # Internal helpers, not a published module: plural nouns and verbs read better here.
        'PSUseSingularNouns'
        'PSUseApprovedVerbs'
        # -DryRun is the explicit preview mechanism; ShouldProcess would duplicate it.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
