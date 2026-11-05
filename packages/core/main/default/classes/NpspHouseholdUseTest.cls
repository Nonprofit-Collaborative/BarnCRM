/**
 * Household Upkeep waits while NPSP households are in use (RT-04, canonical model R-HA6): the
 * detection, the refused turn-on, first-run setup leaving it out, and the Features row. No test
 * org has NPSP, so the tests replace `NpspHouseholdSource.instance` with stand-ins.
 */
@IsTest(
	testFor='ApexClass:NpspHouseholdSource, ApexClass:FeatureSwitchService, ApexClass:FeatureController'
)
private class NpspHouseholdUseTest {
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
		NpspHouseholdSource.instance = source;
		NpspHouseholdSource.clearCache();
	}

	@IsTest
	static void notInUseWithoutNpsp() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Boolean inUse = NpspHouseholdSource.householdsInUse();
			Boolean creates = NpspHouseholdSource.get().createsHouseholds();
			Test.stopTest();

			Assert.isFalse(inUse, 'An org without NPSP has no NPSP households in use');
			Assert.isFalse(creates, 'No NPSP setting object, so NPSP creates nothing');
			Assert.isNull(
				FeatureSwitchService.blockedReason(FeatureSwitchService.HOUSEHOLD_UPKEEP),
				'Household Upkeep can be turned on'
			);
		}
	}

	@IsTest
	static void inUseWhileNpspCreatesHouseholds() {
		System.runAs(TestUsers.admin()) {
			useSource(new FakeSource(true, true));

			Test.startTest();
			Boolean inUse = NpspHouseholdSource.householdsInUse();
			Test.stopTest();

			Assert.isTrue(inUse, 'Account Model Household Account means in use');
		}
	}

	@IsTest
	static void inUseWhileHouseholdsAreNotAdopted() {
		System.runAs(TestUsers.admin()) {
			insert as user new Account(Name = NPSP_NAME);
			useSource(new FakeSource(true, false));

			Test.startTest();
			Boolean inUse = NpspHouseholdSource.householdsInUse();
			Test.stopTest();

			Assert.isTrue(inUse, 'An NPSP household not yet adopted means in use');
		}
	}

	@IsTest
	static void notInUseOnceAdoptedAndAccountModelChanged() {
		System.runAs(TestUsers.admin()) {
			useSource(new FakeSource(true, false));

			Test.startTest();
			Boolean inUse = NpspHouseholdSource.householdsInUse();
			Test.stopTest();

			Assert.isFalse(inUse, 'No NPSP household left and NPSP no longer creates them');
		}
	}

	@IsTest
	static void aReadFailureAnswersNotInUse() {
		System.runAs(TestUsers.admin()) {
			FakeSource source = new FakeSource(true, true);
			source.fails = true;
			useSource(source);

			Test.startTest();
			Boolean inUse = NpspHouseholdSource.householdsInUse();
			Test.stopTest();

			Assert.isFalse(inUse, 'A failed read never blocks and never throws');
		}
	}

	@IsTest
	static void turningOnHouseholdUpkeepIsRefusedWithTheReason() {
		System.runAs(TestUsers.admin()) {
			TestSettings.newInstall();
			useSource(new FakeSource(true, true));
			Exception refused;

			Test.startTest();
			try {
				FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
			} catch (FeatureSwitchService.FeatureSwitchException e) {
				refused = e;
			}
			Test.stopTest();

			Assert.isNotNull(
				refused,
				'Household Upkeep is refused while NPSP households are in use'
			);
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_Feature_HouseholdUpkeep_NpspBlocked'),
				refused.getMessage(),
				'The refusal says why'
			);
			Assert.isFalse(
				FeatureSwitchService.isOn(FeatureSwitchService.HOUSEHOLD_UPKEEP),
				'It stays off'
			);
		}
	}

	@IsTest
	static void firstRunSetupLeavesHouseholdUpkeepOut() {
		System.runAs(TestUsers.admin()) {
			TestSettings.newInstall();
			useSource(new FakeSource(true, true));

			Test.startTest();
			FeatureSwitchService.finishFirstRun(
				new Set<String>{
					FeatureSwitchService.RELATIONSHIPS,
					FeatureSwitchService.HOUSEHOLD_UPKEEP
				}
			);
			Test.stopTest();

			Assert.areEqual(
				new Set<String>{ 'relationships' },
				FeatureSwitchService.featuresOn(),
				'The other ticked feature is on, Household Upkeep is not'
			);
			Assert.isFalse(FeatureSwitchService.awaitingFirstRun(), 'Setup is finished');
		}
	}

	@IsTest
	static void theFeaturesRowSaysWhyAndTheControllerPassesTheReasonOn() {
		System.runAs(TestUsers.admin()) {
			TestSettings.newInstall();
			useSource(new FakeSource(true, true));
			String message;

			Test.startTest();
			List<FeatureController.FeatureRow> rows = FeatureController.rows();
			try {
				FeatureController.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
			} catch (AuraHandledException e) {
				message = e.getMessage();
			}
			Test.stopTest();

			String reason = BarnHelp.text('Core', 'Core_Feature_HouseholdUpkeep_NpspBlocked');
			for (FeatureController.FeatureRow row : rows) {
				if (row.key == FeatureSwitchService.HOUSEHOLD_UPKEEP) {
					Assert.areEqual(reason, row.blockedReason, 'Household Upkeep says why');
				} else {
					Assert.isNull(row.blockedReason, row.key + ' is not held back');
				}
			}
			Assert.areEqual(reason, message, 'The person sees the reason, not a generic error');
		}
	}

	private static HealthCheckService.Finding overlapFinding() {
		for (HealthCheckService.Finding finding : HealthCheckService.run()) {
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
			Test.startTest();
			HealthCheckService.Finding finding = overlapFinding();
			Test.stopTest();

			Assert.isNotNull(finding, 'Both packages would make households, so it is reported');
			Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.severity, 'A warning');
			Assert.areEqual(
				HealthCheckService.SECTION_GENERAL,
				finding.fixTarget,
				'It links to the General page, where the adoption panel is'
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
