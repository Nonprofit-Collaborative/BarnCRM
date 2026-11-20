/**
 * Health Check's Household Upkeep overlap finding (RT-04, canonical model R-HA6): reported while
 * Upkeep is on and NPSP households are in use, pointing to the Migration Assistant when the
 * Migration package is installed. No test org has NPSP, so the tests set stand-in sources
 * through `NpspHouseholdSource.useForTest`.
 */
@IsTest(testFor='ApexClass:HealthCheckOrgShapeChecks')
private class HealthCheckNpspOverlapTest {
	private static final String NPSP_NAME = 'Garcia Household (NPSP stand-in)';

	/** NPSP's Account Model answered by the test; households found by name. */
	private class FakeSource extends NpspHouseholdSource {
		private Boolean creates;
		private Boolean present;
		private Boolean fails = false;

		FakeSource(Boolean present, Boolean creates) {
			this.present = present;
			this.creates = creates;
		}

		public override Boolean available() {
			return present;
		}

		public override String condition() {
			return present ? 'Name = :npspName' : '';
		}

		public override Map<String, Object> binds() {
			return new Map<String, Object>{ 'npspName' => NPSP_NAME };
		}

		public override Boolean createsHouseholds() {
			if (fails) {
				throw new IllegalArgumentException('Setting could not be read');
			}
			return creates;
		}
	}

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void useSource(NpspHouseholdSource source) {
		NpspHouseholdSource.useForTest(NpspHouseholdSource.NPSP, source);
	}

	private static HealthCheckService.Finding overlapFinding() {
		for (HealthCheckService.Finding finding : HealthCheckRunner.run()) {
			if ('npsp_upkeep_overlap'.equals(finding.key)) {
				return finding;
			}
		}
		return null;
	}

	@IsTest
	static void healthCheckReportsUpkeepOnWhileNpspHouseholdsAreInUse() {
		System.runAs(TestUsers.admin()) {
			TestSettings.newInstall();
			useSource(new FakeSource(false, false));
			FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
			Assert.isNull(overlapFinding(), 'Nothing to report while NPSP is not in use');

			// NPSP arrives, with the Household Account model, after Upkeep was switched on.
			useSource(new FakeSource(true, true));
			IntegrationAppService.migrationInstalledOverride = false;
			Test.startTest();
			HealthCheckService.Finding finding = overlapFinding();
			IntegrationAppService.migrationInstalledOverride = true;
			HealthCheckService.Finding withMigration = overlapFinding();
			Test.stopTest();

			Assert.isNotNull(finding, 'Both packages would make households, so it is reported');
			Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.severity, 'A warning');
			Assert.areEqual(
				HealthCheckService.SECTION_GENERAL,
				finding.fixTarget,
				'Without the Migration package it links to the General page, to turn Households off'
			);
			Assert.areEqual(
				'/lightning/n/' + NamespaceUtil.qualify(HealthCheckOrgShapeChecks.MIGRATION_TAB),
				withMigration.fixTarget,
				'With it, the Migration Assistant tab, where Adopt NPSP Households is'
			);
		}
	}

	@IsTest
	static void healthCheckSaysNothingWhenUpkeepIsOff() {
		System.runAs(TestUsers.admin()) {
			TestSettings.newInstall();
			useSource(new FakeSource(true, true));

			Test.startTest();
			HealthCheckService.Finding finding = overlapFinding();
			Test.stopTest();

			Assert.isNull(finding, 'Upkeep is off, so nothing overlaps');
		}
	}
}
