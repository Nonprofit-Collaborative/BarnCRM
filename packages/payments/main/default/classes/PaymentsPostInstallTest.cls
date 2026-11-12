/**
 * Maria installs Payments and can open it straight away: she holds Payments Admin, the roles hold
 * their sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:PaymentsPostInstall')
private class PaymentsPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :PaymentsAccessSync.ADMIN_SET
			WITH SYSTEM_MODE
		];
	}

	private static Integer accessErrors() {
		return [
			SELECT COUNT()
			FROM Error_Log__c
			WHERE Context__c = :PaymentsPostInstall.ACCESS_CONTEXT
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsPaymentsAdminOnceAndTheRolesTheirSets() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id holding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ PaymentsAccessSync.ADMIN_SET }
				)
				.Id;
			User reader = TestUsers.standardUser('Reader');
			insert new PermissionSetAssignment(
				AssigneeId = reader.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Read_Only').Id
			);

			Test.startTest();
			Test.testInstall(new PaymentsPostInstall(), null);
			System.enqueueJob(new PaymentsPostInstall.InstallerAccess(fresh));
			System.enqueueJob(new PaymentsPostInstall.InstallerAccess(holding));
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Payments Admin');
			Assert.areEqual(1, adminSetsHeldBy(holding), 'Never given twice');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :reader.Id AND PermissionSet.Name = 'Payments_Read_Only'
					WITH SYSTEM_MODE
				],
				'The Read Only role holds Payments Read Only after the install'
			);
			Assert.areEqual(0, accessErrors(), 'Nothing failed');
		}
	}

	@IsTest
	static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
		System.runAs(TestUsers.admin()) {
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new PaymentsPostInstall().onInstall(null);
			new PaymentsPostInstall().runSetup(null);
			System.enqueueJob(new PaymentsPostInstall.InstallerAccess(notAUser));
			Test.stopTest();

			Assert.isTrue(accessErrors() >= 1, 'The refusal is in the Error Log');
		}
	}
}
