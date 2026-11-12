/**
 * Maria installs LWC Builder and can open it straight away: she holds LWC Builder Admin,
 * BarnCRM's roles hold their sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:LwcBuilderPostInstall')
private class LwcBuilderPostInstallTest {
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
					new List<String>{ LwcBuilderAccessSync.ADMIN_SET }
				)
				.Id;
			User member = TestUsers.standardUser('Member');
			insert new PermissionSetAssignment(
				AssigneeId = member.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Test.testInstall(new LwcBuilderPostInstall(), null);
			System.enqueueJob(new LwcBuilderPostInstall.InstallerAccess(fresh));
			System.enqueueJob(new LwcBuilderPostInstall.InstallerAccess(alreadyHolding));
			Test.stopTest();

			Assert.areEqual(
				1,
				setsHeldBy(fresh, LwcBuilderAccessSync.ADMIN_SET),
				'The installer holds it'
			);
			Assert.areEqual(
				1,
				setsHeldBy(alreadyHolding, LwcBuilderAccessSync.ADMIN_SET),
				'Never twice'
			);
			Assert.areEqual(
				1,
				setsHeldBy(member.Id, 'LWC_Builder_Staff'),
				'Team Member holds Staff'
			);
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :LwcBuilderPostInstall.ACCESS_CONTEXT
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
			new LwcBuilderPostInstall().onInstall(null);
			System.enqueueJob(new LwcBuilderPostInstall.InstallerAccess(notAUser));
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :LwcBuilderPostInstall.ACCESS_CONTEXT
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
			new LwcBuilderPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(
				1,
				setsHeldBy(reader.Id, 'LWC_Builder_Read_Only'),
				'Read Only holds it'
			);
		}
	}
}
