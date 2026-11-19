/**
 * Maria installs Advanced Reporting and can open it straight away: she holds Advanced
 * Reporting Admin, BarnCRM's roles hold their sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:ReportingPostInstall')
private class ReportingPostInstallTest {
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
			Id alreadyHolding = TestDataFactory.createUser('Holder', new List<String>{ 'Reporting_Admin' }).Id;
			User member = TestUsers.standardUser('Member');
			insert new PermissionSetAssignment(
				AssigneeId = member.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Test.testInstall(new ReportingPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job('Reporting', fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job('Reporting', alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, setsHeldBy(fresh, 'Reporting_Admin'), 'The installer holds it');
			Assert.areEqual(1, setsHeldBy(alreadyHolding, 'Reporting_Admin'), 'Never twice');
			Assert.areEqual(1, setsHeldBy(member.Id, 'Reporting_Staff'), 'Team Member holds Staff');
		}
	}

	@IsTest
	static void anInstallWithNoInstallerStillSyncsTheRolesAndAMissingContextDoesNothing() {
		System.runAs(TestUsers.admin()) {
			User reader = TestUsers.standardUser('Reader');
			insert new PermissionSetAssignment(
				AssigneeId = reader.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Read_Only').Id
			);

			Test.startTest();
			new ReportingPostInstall().onInstall(null);
			new ReportingPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(1, setsHeldBy(reader.Id, 'Reporting_Read_Only'), 'Read Only holds it');
		}
	}
}
