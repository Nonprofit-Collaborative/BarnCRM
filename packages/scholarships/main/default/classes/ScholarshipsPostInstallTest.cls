/**
 * Maria installs Scholarships: BarnCRM Admin holders get Scholarships Admin, BarnCRM's roles get
 * their sets, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:ScholarshipsPostInstall')
private class ScholarshipsPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer held(Id userId, String setName) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :setName
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void installGivesTheSetsThroughTheRoles() {
		System.runAs(TestUsers.admin()) {
			User member = TestUsers.standardUser('Member');
			insert new PermissionSetAssignment(
				AssigneeId = member.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Test.testInstall(new ScholarshipsPostInstall(), null);
			Test.stopTest();

			Assert.areEqual(
				1,
				held(TestUsers.admin().Id, 'Scholarships_Admin'),
				'BarnCRM Admin holds Scholarships Admin'
			);
			Assert.areEqual(1, held(member.Id, 'Scholarships_Staff'), 'Team Member holds Staff');
			Assert.areEqual(
				new List<String>{ 'Scholarships_Admin' },
				ModuleAccessSyncs.adminSets('Scholarships'),
				'The catalog row names the admin set'
			);
		}
	}
}
