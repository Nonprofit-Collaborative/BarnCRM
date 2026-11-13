// Template for scripts/org/package-upgrade-test.sh: %%NS%% becomes the namespace. Not deployed.
// Runs every Health Check as the installing admin, through the global entry point
// BarnInstallCheck, and fails when any finding is an error. Warnings and information are
// allowed. The checks only read, so nothing needs rolling back.
Map<String, Object> summary = %%NS%%.BarnInstallCheck.runHealthCheck();
List<String> errors = (List<String>) summary.get('errorFindings');
System.debug(LoggingLevel.ERROR, 'UPGRADE-TEST health check: ' + summary.get('findings') + ' finding(s), ' + errors.size() + ' error(s)');
Assert.areEqual(0, errors.size(), 'Health Check errors: ' + String.join(errors, '; '));
