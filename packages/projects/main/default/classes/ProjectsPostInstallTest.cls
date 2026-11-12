/**
 * Maria installs Project Management: BarnCRM Admin holders get Projects Admin, BarnCRM's roles get
 * their sets, the nightly step is offered, and nothing in the install can fail it.
 */
@IsTest(
	testFor='ApexClass:ProjectsPostInstall, ApexClass:ProjectsAccessSync, ApexClass:ProjectsNightlyJobProvider'
)
private class ProjectsPostInstallTest {
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
			Test.testInstall(new ProjectsPostInstall(), null);
			Test.stopTest();

			Assert.areEqual(
				1,
				held(TestUsers.admin().Id, ProjectsAccessSync.ADMIN_SET),
				'BarnCRM Admin holds Projects Admin'
			);
			Assert.areEqual(
				1,
				held(member.Id, 'Projects_Staff'),
				'Team Member holds Projects Staff'
			);
			Assert.areEqual('Projects', new ProjectsAccessSync().moduleName(), 'Module key');
			List<NightlyStep> steps = new ProjectsNightlyJobProvider().nightlySteps();
			Assert.areEqual(
				ProjectHealth.JOB_NAME,
				steps[0].key,
				'The health step joins the nightly run'
			);
			Assert.areEqual(400, steps[0].minute, 'At 6:40 AM');
		}
	}
}
