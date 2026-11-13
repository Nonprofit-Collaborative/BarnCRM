/**
 * Maria installs Portal Builder and can set up a portal straight away: she holds Portal Builder
 * Admin, nothing in the install can fail it, and no portal accepts sign-ins until she turns
 * Portal Sign-In on.
 */
@IsTest(testFor='ApexClass:PortalPostInstall')
private class PortalPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = 'Portal_Admin'
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsTheAdminSetOnce() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ 'Portal_Admin' }
				)
				.Id;

			Test.startTest();
			Test.testInstall(new PortalPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job('Portal', fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job('Portal', alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds the admin set');
			Assert.areEqual(1, adminSetsHeldBy(alreadyHolding), 'Never given twice');
			Assert.isFalse(
				Portal_Settings__c.getOrgDefaults().Enabled__c == true,
				'Portal Sign-In ships off'
			);
		}
	}

	@IsTest
	static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
		System.runAs(TestUsers.admin()) {
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new PortalPostInstall().onInstall(null);
			new PortalPostInstall().runSetup(null);
			System.enqueueJob(new ModuleAccessSyncs.Job('Portal', notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'PortalPostInstall.grantInstallerAccess'
					WITH SYSTEM_MODE
				],
				'The refusal is in the Error Log'
			);
		}
	}
}
