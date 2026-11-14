/**
 * Maria installs Memberships and can open it straight away: she holds Memberships Admin, the roles
 * hold their sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:MembershipsPostInstall')
private class MembershipsPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = 'Memberships_Admin'
			WITH SYSTEM_MODE
		];
	}

	private static Integer accessErrors() {
		return [
			SELECT COUNT()
			FROM Error_Log__c
			WHERE Context__c = 'MembershipsPostInstall.grantInstallerAccess'
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsMembershipsAdminOnceAndTheRolesTheirSets() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id holding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ 'Memberships_Admin' }
				)
				.Id;
			User reader = TestUsers.standardUser('Reader');
			insert new PermissionSetAssignment(
				AssigneeId = reader.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Read_Only').Id
			);

			Test.startTest();
			Test.testInstall(new MembershipsPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job('Memberships', fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job('Memberships', holding));
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Memberships Admin');
			Assert.areEqual(1, adminSetsHeldBy(holding), 'Never given twice');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :reader.Id AND PermissionSet.Name = 'Memberships_Read_Only'
					WITH SYSTEM_MODE
				],
				'The Read Only role holds Memberships Read Only after the install'
			);
			Assert.areEqual(0, accessErrors(), 'Nothing failed');
		}
	}

	@IsTest
	static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
		System.runAs(TestUsers.admin()) {
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new MembershipsPostInstall().onInstall(null);
			new MembershipsPostInstall().runSetup(null);
			System.enqueueJob(new ModuleAccessSyncs.Job('Memberships', notAUser));
			Test.stopTest();

			Assert.isTrue(accessErrors() >= 1, 'The refusal is in the Error Log');
		}
	}
}
