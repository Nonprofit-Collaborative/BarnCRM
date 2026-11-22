/**
 * Maria installs Project Management: BarnCRM Admin holders get Projects Admin, BarnCRM's roles get
 * their sets, the nightly step is offered, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:ProjectsPostInstall, ApexClass:ProjectsNightlyJobProvider')
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
	static void anUnsavedReturnPageShowsTheMyDomainAddressInTheConsole() {
		System.runAs(TestUsers.admin()) {
			Assert.areEqual(
				ProjectsSettings.myDomain(),
				SettingsService.getEffectiveValue(ProjectsSettings.SETTINGS_OBJECT, 'Invoice_Return_Url__c', 'Text'),
				'Never blank, on an org the install never ran in'
			);
		}
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

			Assert.areEqual(1, held(TestUsers.admin().Id, 'Projects_Admin'), 'BarnCRM Admin holds Projects Admin');
			Assert.areEqual(1, held(member.Id, 'Projects_Staff'), 'Team Member holds Projects Staff');
			Assert.isTrue(
				ModuleExtensions.forModule(NightlyStepProvider.class, 'Projects') instanceof ProjectsNightlyJobProvider,
				'The catalog registers the provider'
			);
			List<NightlyStep> steps = new ProjectsNightlyJobProvider().nightlySteps();
			Assert.areEqual(ProjectHealth.JOB_NAME, steps[0].key, 'The health step joins the nightly run');
			Assert.areEqual(400, steps[0].minute, 'At 6:40 AM');
			SettingsService.clearCaches();
			Assert.areEqual(
				Url.getOrgDomainUrl().toExternalForm(),
				ProjectsSettings.invoiceReturnUrl(),
				'The return page is My Domain until the admin saves one, never blank'
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'The install saves no setting');
		}
	}

	@IsTest
	static void aReturnPageTheAdminChoseIsKept() {
		System.runAs(TestUsers.admin()) {
			ModuleSettings.setForTest('Projects_Invoice_Return_Url', 'https://example.org/thanks');
			Test.startTest();
			new ProjectsPostInstall().runSetup(null);
			Test.stopTest();
			SettingsService.clearCaches();
			Assert.areEqual(
				'https://example.org/thanks',
				ProjectsSettings.invoiceReturnUrl(),
				'A saved page is never replaced'
			);
		}
	}
}
