/**
 * Maria installs Corporate Hub and can open it straight away: she holds Corporate Hub Admin,
 * BarnCRM's roles hold their sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:CorporateHubPostInstall')
private class CorporateHubPostInstallTest {
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
	static void theInstallerGetsTheAdminSetOnceAndTheRolesTheirSets() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ CorporateHubAccessSync.ADMIN_SET }
				)
				.Id;
			User member = TestUsers.standardUser('Member');
			insert new PermissionSetAssignment(
				AssigneeId = member.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Test.testInstall(new CorporateHubPostInstall(), null);
			System.enqueueJob(new CorporateHubPostInstall.InstallerAccess(fresh));
			System.enqueueJob(new CorporateHubPostInstall.InstallerAccess(alreadyHolding));
			Test.stopTest();

			Assert.areEqual(
				1,
				setsHeldBy(fresh, CorporateHubAccessSync.ADMIN_SET),
				'The installer holds it'
			);
			Assert.areEqual(
				1,
				setsHeldBy(alreadyHolding, CorporateHubAccessSync.ADMIN_SET),
				'Never twice'
			);
			Assert.areEqual(
				1,
				setsHeldBy(member.Id, 'Corporate_Hub_Staff'),
				'Team Member holds Staff'
			);
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :CorporateHubPostInstall.ACCESS_CONTEXT
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
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new CorporateHubPostInstall().onInstall(null);
			System.enqueueJob(new CorporateHubPostInstall.InstallerAccess(notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :CorporateHubPostInstall.ACCESS_CONTEXT
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
			new CorporateHubPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(
				1,
				setsHeldBy(reader.Id, 'Corporate_Hub_Read_Only'),
				'Read Only holds it'
			);
		}
	}
}
