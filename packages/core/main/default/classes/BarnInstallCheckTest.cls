/**
 * The install and upgrade test's global entry points (D-199): each delegates to the public
 * service and runs only for someone who may run setup. Maria may manage settings; Priya may
 * not and has no Customize Application; Ada has Customize Application only, which is enough
 * while nobody in the org holds Manage BarnCRM Settings (the bootstrap).
 */
@IsTest(testFor='ApexClass:BarnInstallCheck, ApexClass:BarnCRMPermissions')
private class BarnInstallCheckTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private class StubSetup implements ModuleSetup {
		public Integer timesRun = 0;

		public void runSetup(Id installerId) {
			timesRun++;
		}
	}

	private static StubSetup stubbedGiving() {
		StubSetup stub = new StubSetup();
		ModuleSetups.noneForTest = true;
		ModuleSetups.overrides.put('Giving', stub);
		ModuleDetectionService.givingPresentOverride = true;
		return stub;
	}

	@IsTest
	static void healthCheckReturnsAPlainSummary() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			System.runAs(maria) {
				Integer expected = HealthCheckService.run().size();

				Map<String, Object> summary = BarnInstallCheck.runHealthCheck();

				Assert.areEqual(expected, summary.get('findings'), 'Every finding counted');
				List<String> errors = (List<String>) summary.get('errorFindings');
				Assert.areEqual(errors.size(), summary.get('errors'), 'One line per error');
			}
		}
	}

	@IsTest
	static void finishSetupRunsThePackagesStepsAndMarksIt() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			StubSetup giving = stubbedGiving();
			System.runAs(maria) {
				List<String> done = BarnInstallCheck.finishSetup('Giving');

				Assert.areEqual(1, giving.timesRun, 'Giving setup ran');
				Assert.areEqual(1, done.size(), 'Named once');
				Assert.isTrue(ModuleSetups.ran().contains('giving'), 'Marked');
			}
		}
	}

	@IsTest
	static void everyEntryPointNeedsSetupAccess() {
		System.runAs(TestUsers.admin()) {
			User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
			StubSetup giving = stubbedGiving();
			BarnCRMPermissions.anyoneManagesOverride = false;
			Integer refused = 0;
			System.runAs(priya) {
				try {
					BarnInstallCheck.runHealthCheck();
				} catch (ModuleManagerService.ModuleManagerException expected) {
					refused++;
				}
				try {
					BarnInstallCheck.loadSampleData();
				} catch (ModuleManagerService.ModuleManagerException expected) {
					refused++;
				}
				try {
					BarnInstallCheck.finishSetup('Giving');
				} catch (ModuleManagerService.ModuleManagerException expected) {
					refused++;
				}
			}
			Assert.areEqual(3, refused, 'No Customize Application, so no bootstrap either');
			Assert.areEqual(0, giving.timesRun, 'Nothing ran');
		}
	}

	@IsTest
	static void customizeApplicationRunsSetupOnlyWhileNobodyManagesSettings() {
		User ada = TestUsers.onRunningProfileWith('Ada', new List<String>());
		System.runAs(ada) {
			Assert.isFalse(BarnCRMPermissions.canManageSettings(), 'Ada holds no BarnCRM set');

			BarnCRMPermissions.anyoneManagesOverride = true;
			Assert.isFalse(BarnCRMPermissions.canRunSetup(), 'Someone can do it, so not Ada');

			BarnCRMPermissions.anyoneManagesOverride = false;
			Assert.isTrue(BarnCRMPermissions.canRunSetup(), 'Nobody can, so an admin may start');
		}
	}
}
