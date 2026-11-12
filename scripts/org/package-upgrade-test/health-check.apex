// Template for scripts/org/package-upgrade-test.sh: %%NS%% becomes the namespace. Not deployed.
// Runs every Health Check as the installing admin and fails when any finding is an error.
// Warnings and information are allowed. The checks only read, so nothing needs rolling back.
List<%%NS%%.HealthCheckService.Finding> findings = %%NS%%.HealthCheckService.run();
List<String> errors = new List<String>();
for (%%NS%%.HealthCheckService.Finding finding : findings) {
	if (finding.severity == %%NS%%.HealthCheckService.SEVERITY_ERROR) {
		errors.add(finding.key + ': ' + finding.title);
	}
}
System.debug(LoggingLevel.ERROR, 'UPGRADE-TEST health check: ' + findings.size() + ' finding(s), ' + errors.size() + ' error(s)');
Assert.areEqual(0, errors.size(), 'Health Check errors: ' + String.join(errors, '; '));
