// Template for scripts/org/package-upgrade-test.sh: %%NS%% and %%KEY%% are filled in. Not deployed.
// Used only with --type unlocked. A post-install script runs for managed packages only, so on
// an unlocked install the test runs each package's setup itself, as the installing admin, the
// way Module Manager's Finish Setup does, through the global entry point BarnInstallCheck (a
// subscriber's anonymous Apex cannot see a package's public classes). The steps only add what
// is missing.
List<String> done = %%NS%%.BarnInstallCheck.finishSetup('%%KEY%%');
System.debug(LoggingLevel.ERROR, 'UPGRADE-TEST setup ran for: ' + String.join(done, ', '));
