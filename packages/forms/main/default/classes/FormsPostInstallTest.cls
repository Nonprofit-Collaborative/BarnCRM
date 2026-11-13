/**
 * Maria installs the Forms module and can open it straight away: she holds Forms Admin, BarnCRM's
 * roles hold their Forms sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:FormsPostInstall')
private class FormsPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = 'Forms_Admin'
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsFormsAdminOnceAndTheRolesTheirSets() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ 'Forms_Admin' }
				)
				.Id;
			User member = TestUsers.standardUser('Member');
			insert new PermissionSetAssignment(
				AssigneeId = member.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Test.testInstall(new FormsPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job('Forms', fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job('Forms', alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Forms Admin');
			Assert.areEqual(1, adminSetsHeldBy(alreadyHolding), 'Never given twice');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :member.Id AND PermissionSet.Name = 'Forms_Staff'
					WITH SYSTEM_MODE
				],
				'The Team Member role holds Forms Staff after the install'
			);
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'FormsPostInstall.grantInstallerAccess'
					WITH SYSTEM_MODE
				],
				'Nothing failed'
			);
		}
	}

	/** A grant the platform refuses is logged, never thrown, and a missing context is a no-op. */
	@IsTest
	static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
		System.runAs(TestUsers.admin()) {
			// An Id that is not a user: the assignment is refused for a reason other than a duplicate.
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new FormsPostInstall().onInstall(null);
			System.enqueueJob(new ModuleAccessSyncs.Job('Forms', notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'FormsPostInstall.grantInstallerAccess'
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
			new FormsPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :reader.Id AND PermissionSet.Name = 'Forms_Read_Only'
					WITH SYSTEM_MODE
				],
				'The Read Only role holds Forms Read Only'
			);
		}
	}
}
