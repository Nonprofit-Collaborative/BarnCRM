/**
 * Maria installs Contact Point Sync and can open its page straight away: she holds Contact Point
 * Sync Admin, nothing in the install can fail it, and nothing is copied until she starts the
 * backfill.
 */
@IsTest(testFor='ApexClass:ContactPointsPostInstall')
private class ContactPointsPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :ContactPointsAccessSync.ADMIN_SET
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsTheAdminSetOnce() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ ContactPointsAccessSync.ADMIN_SET }
				)
				.Id;

			Test.startTest();
			Test.testInstall(new ContactPointsPostInstall(), null);
			System.enqueueJob(new ContactPointsPostInstall.InstallerAccess(fresh));
			System.enqueueJob(new ContactPointsPostInstall.InstallerAccess(alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds the admin set');
			Assert.areEqual(1, adminSetsHeldBy(alreadyHolding), 'Never given twice');
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :ContactPointsPostInstall.ACCESS_CONTEXT
					WITH SYSTEM_MODE
				],
				'Nothing failed'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Contact_Point_Link__c WITH SYSTEM_MODE],
				'Nothing is copied at install'
			);
		}
	}

	@IsTest
	static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
		System.runAs(TestUsers.admin()) {
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new ContactPointsPostInstall().onInstall(null);
			new ContactPointsPostInstall().runSetup(null);
			System.enqueueJob(new ContactPointsPostInstall.InstallerAccess(notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :ContactPointsPostInstall.ACCESS_CONTEXT
					WITH SYSTEM_MODE
				],
				'The refusal is in the Error Log'
			);
		}
	}
}
