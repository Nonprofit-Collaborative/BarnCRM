/**
 * Installing Mirror adds it to Core's setup marker, so Health Check and the Modules page do not
 * flag it for Finish Setup, and schedules nothing: the hourly Case check waits until Send Cases to
 * a service provider is on (N-10).
 */
@IsTest(testFor='ApexClass:MirrorPostInstall')
private class MirrorPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void installingMirrorMarksItsSetupAndSchedulesNothing() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Test.testInstall(new MirrorPostInstall(), null);
			Test.stopTest();

			Assert.isTrue(ModuleSetups.ran().contains('mirror'), 'Setup recorded for Mirror.');
			Assert.isFalse(
				CaseProviderRequestsHourly.isScheduled(),
				'No hourly Case check while sending Cases is off.'
			);
		}
	}

	@IsTest
	static void finishSetupRunsTheSameStepTwiceSafely() {
		System.runAs(TestUsers.admin()) {
			MirrorPostInstall setup = new MirrorPostInstall();
			setup.runSetup(null);
			setup.runSetup(null);

			Assert.isTrue(ModuleSetups.ran().contains('mirror'), 'Still recorded once.');
		}
	}
}
