/**
 * Public forms' Health Check (ADR-0184 public forms on a Salesforce Site, decision 9): quiet
 * with no public form; with one, it reports a missing Site, a guest user without Forms Public
 * Guest (and gives it), and processing not scheduled (and schedules it).
 */
@IsTest(testFor='ApexClass:FormsHealthCheckExtension, ApexClass:FormsSites')
private class FormsHealthCheckExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static Set<String> keys(List<HealthCheckService.Finding> findings) {
		// Read through JSON: the finding's fields are Core's and not namespace accessible.
		Set<String> found = new Set<String>();
		for (Object finding : (List<Object>) JSON.deserializeUntyped(JSON.serialize(findings))) {
			found.add(String.valueOf(((Map<String, Object>) finding).get('key')));
		}
		return found;
	}

	@IsTest
	static void quietWithNoPublicForm() {
		System.runAs(admin()) {
			FormsSites.testSites = new List<FormsSites.SiteInfo>();
			FormsTestData.volunteerInterest();
			Assert.isTrue(new FormsHealthCheckExtension().findings().isEmpty(), 'Nothing to say');
		}
	}

	@IsTest
	static void aPublicFormWithNoSiteOrProcessingIsReportedAndFixed() {
		System.runAs(admin()) {
			FormsSites.testSites = new List<FormsSites.SiteInfo>();
			FormsTestData.publicVolunteerInterest(50);
			FormsHealthCheckExtension extension = new FormsHealthCheckExtension();

			Set<String> found = keys(extension.findings());
			Assert.isTrue(found.contains('forms_public_no_site'), 'No Site: ' + found);
			Assert.isTrue(
				found.contains(FormsHealthCheckExtension.FIX_SCHEDULE),
				'Not scheduled: ' + found
			);

			Test.startTest();
			String done = extension.runFix(
				FormsHealthCheckExtension.FIX_SCHEDULE,
				extension.fixScope(FormsHealthCheckExtension.FIX_SCHEDULE)
			);
			Test.stopTest();
			Assert.isNotNull(done, 'Says what it did');
			Assert.isTrue(FormPublicProcessor.isScheduled(), 'Scheduled');
		}
	}

	@IsTest
	static void aGuestWithoutAccessIsGivenIt() {
		System.runAs(admin()) {
			FormsSites.SiteInfo site = new FormsSites.SiteInfo();
			site.name = 'Zzforms Site';
			site.guestUserId = UserInfo.getUserId();
			site.url = 'https://zzforms.example.org';
			FormsSites.testSites = new List<FormsSites.SiteInfo>{ site };
			Form__c form = FormsTestData.publicVolunteerInterest(50);
			FormsHealthCheckExtension extension = new FormsHealthCheckExtension();

			Assert.isTrue(
				keys(extension.findings()).contains(FormsHealthCheckExtension.FIX_GUEST),
				'Reported'
			);
			Assert.areEqual(
				new List<String>{ 'Zzforms Site' },
				extension.fixScope(FormsHealthCheckExtension.FIX_GUEST),
				'Names the Site'
			);
			extension.runFix(
				FormsHealthCheckExtension.FIX_GUEST,
				new List<String>{ 'Zzforms Site' }
			);
			Assert.isFalse(
				keys(extension.findings()).contains(FormsHealthCheckExtension.FIX_GUEST),
				'Given'
			);
			Assert.isNotNull(extension.fixLabel(FormsHealthCheckExtension.FIX_GUEST), 'Labelled');
			Assert.isNull(extension.fixLabel('other'), 'Not its key');
			Assert.areEqual(
				new List<String>{ 'https://zzforms.example.org' },
				FormsSites.activeSiteUrls(),
				'The Site address'
			);
			Assert.isTrue(
				FormBuilderController.getBuilder(form.Id).publicLinks[0].endsWith(form.Id),
				'The builder links the form'
			);
		}
	}
}
