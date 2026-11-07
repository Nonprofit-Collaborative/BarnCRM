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
			WHERE AssigneeId = :userId AND PermissionSet.Name = :PortalAccessSync.ADMIN_SET
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsTheAdminSetOnce() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ PortalAccessSync.ADMIN_SET }
				)
				.Id;

			Test.startTest();
			Test.testInstall(new PortalPostInstall(), null);
			System.enqueueJob(new PortalPostInstall.InstallerAccess(fresh));
			System.enqueueJob(new PortalPostInstall.InstallerAccess(alreadyHolding));
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
			System.enqueueJob(new PortalPostInstall.InstallerAccess(notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :PortalPostInstall.ACCESS_CONTEXT
					WITH SYSTEM_MODE
				],
				'The refusal is in the Error Log'
			);
		}
	}
}
