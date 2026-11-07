/**
 * Maria installs the Event Management module and can open it straight away: she holds Events
 * Admin, BarnCRM's roles hold their Event Management sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:EventsPostInstall')
private class EventsPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :EventsAccessSync.ADMIN_SET
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsEventsAdminOnceAndTheRolesTheirSets() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ EventsAccessSync.ADMIN_SET }
				)
				.Id;
			User member = TestUsers.standardUser('Member');
			insert new PermissionSetAssignment(
				AssigneeId = member.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Test.testInstall(new EventsPostInstall(), null);
			System.enqueueJob(new EventsPostInstall.InstallerAccess(fresh));
			System.enqueueJob(new EventsPostInstall.InstallerAccess(alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Events Admin');
			Assert.areEqual(1, adminSetsHeldBy(alreadyHolding), 'Never given twice');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :member.Id AND PermissionSet.Name = 'Events_Staff'
					WITH SYSTEM_MODE
				],
				'The Team Member role holds Events Staff after the install'
			);
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :EventsPostInstall.ACCESS_CONTEXT
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
			new EventsPostInstall().onInstall(null);
			System.enqueueJob(new EventsPostInstall.InstallerAccess(notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :EventsPostInstall.ACCESS_CONTEXT
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
			new EventsPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM PermissionSetAssignment
					WHERE AssigneeId = :reader.Id AND PermissionSet.Name = 'Events_Read_Only'
					WITH SYSTEM_MODE
				],
				'The Read Only role holds Events Read Only'
			);
		}
	}
}
