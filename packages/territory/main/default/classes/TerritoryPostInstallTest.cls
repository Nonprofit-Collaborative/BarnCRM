/**
 * Maria installs Territory Management and can open it straight away: she holds Territory Admin,
 * BarnCRM's roles hold their sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:TerritoryPostInstall')
private class TerritoryPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer setsHeldBy(Id userId, String setName) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :setName
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsTheAdminSetOnce() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ TerritoryAccessSync.ADMIN_SET }
				)
				.Id;

			Test.startTest();
			Test.testInstall(new TerritoryPostInstall(), null);
			System.enqueueJob(new TerritoryPostInstall.InstallerAccess(fresh));
			System.enqueueJob(new TerritoryPostInstall.InstallerAccess(alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, setsHeldBy(fresh, TerritoryAccessSync.ADMIN_SET), 'Installer');
			Assert.areEqual(1, setsHeldBy(alreadyHolding, TerritoryAccessSync.ADMIN_SET), 'Once');
			Assert.isTrue(ModuleSetups.ran().contains('Territory'), 'Setup is marked as run');
		}
	}

	/** A grant the platform refuses is logged, never thrown, and a missing context is a no-op. */
	@IsTest
	static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
		System.runAs(TestUsers.admin()) {
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new TerritoryPostInstall().onInstall(null);
			System.enqueueJob(new TerritoryPostInstall.InstallerAccess(notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :TerritoryPostInstall.ACCESS_CONTEXT
					WITH SYSTEM_MODE
				],
				'The refusal is in the Error Log'
			);
		}
	}

	@IsTest
	static void anInstallWithNoInstallerStillSyncsTheRoles() {
		System.runAs(TestUsers.admin()) {
			User reader = TestUsers.standardUser('Reader');
			insert new PermissionSetAssignment(
				AssigneeId = reader.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Read_Only').Id
			);

			Test.startTest();
			new TerritoryPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(1, setsHeldBy(reader.Id, 'Territory_Read_Only'), 'Read Only holds it');
		}
	}
}
