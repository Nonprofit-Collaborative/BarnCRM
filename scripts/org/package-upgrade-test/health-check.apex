// Template for scripts/org/package-upgrade-test.sh: %%NS%% becomes the namespace, and
// %%EXPECT_HEALTH%% whether the Org Optimizer module, which holds the runner, is installed. Not
// deployed. Runs every Health Check as the installing admin, through the global entry point
// BarnInstallCheck, and fails when any finding is an error. Warnings and information are
// allowed. The checks only read, so nothing needs rolling back. Fails when Health Check should
// have run and did not; without the module it logs Skipped, never a clean pass.
Map<String, Object> summary = %%NS%%.BarnInstallCheck.runHealthCheck();
Boolean expected = %%EXPECT_HEALTH%%;
if (summary.get('available') != true) {
  Assert.isFalse(expected, 'Health Check did not run, though the Org Optimizer module is installed');
  System.debug(LoggingLevel.ERROR, 'UPGRADE-TEST health check: Skipped, the Org Optimizer module is not installed');
} else {
  List<String> errors = (List<String>) summary.get('errorFindings');
  System.debug(LoggingLevel.ERROR, 'UPGRADE-TEST health check: ' + summary.get('findings') + ' finding(s), ' + errors.size() + ' error(s)');
  Assert.areEqual(0, errors.size(), 'Health Check errors: ' + String.join(errors, '; '));
}
