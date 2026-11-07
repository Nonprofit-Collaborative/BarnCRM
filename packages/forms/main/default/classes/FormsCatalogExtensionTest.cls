/**
 * Forms' answers to Core's form catalog seam (ADR-NEXT): the public forms, a form's questions and
 * the public address tied to a record.
 */
@IsTest(testFor='ApexClass:FormsCatalogExtension')
private class FormsCatalogExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	@IsTest
	static void listsOnlyPublishedPublicForms() {
		System.runAs(admin()) {
			FormsTestData.volunteerInterest();
			Form__c publicForm = FormsTestData.publicVolunteerInterest(50);
			Test.startTest();
			List<FormCatalogEntry> forms = new FormsCatalogExtension().publicForms();
			Test.stopTest();
			Assert.areEqual(1, forms.size(), 'A form that is not public is not offered');
			Assert.areEqual(String.valueOf(publicForm.Id), forms[0].key);
		}
	}

	@IsTest
	static void readsTheQuestionsInOrder() {
		System.runAs(admin()) {
			Form__c form = FormsTestData.volunteerInterest();
			Test.startTest();
			List<FormCatalogEntry> questions = new FormsCatalogExtension().questions(form.Id);
			Test.stopTest();
			Assert.areEqual('first', questions[0].key);
			Assert.areEqual('number', questions[6].kind);
			Assert.isTrue(FormsCatalogExtension.questionsIn('not json').isEmpty());
			Assert.isTrue(FormsCatalogExtension.questionsIn(null).isEmpty());
		}
	}

	@IsTest
	static void buildsTheAddressOnAnActiveSite() {
		System.runAs(admin()) {
			FormsSites.SiteInfo site = new FormsSites.SiteInfo();
			site.url = 'https://zzforms.example.org';
			FormsSites.testSites = new List<FormsSites.SiteInfo>{ site };
			Form__c publicForm = FormsTestData.publicVolunteerInterest(50);
			Form__c privateForm = FormsTestData.volunteerInterest();
			FormsCatalogExtension extension = new FormsCatalogExtension();
			Test.startTest();
			String link = extension.publicLink(publicForm.Id, UserInfo.getUserId());
			String bare = extension.publicLink(publicForm.Id, null);
			String refused = extension.publicLink(privateForm.Id, null);
			Test.stopTest();
			Assert.areEqual(
				'https://zzforms.example.org/FormsPublic?form=' +
					publicForm.Id +
					'&record=' +
					UserInfo.getUserId(),
				link
			);
			Assert.isFalse(bare.contains('record='));
			Assert.isNull(refused, 'A form that is not public has no address');
			FormsSites.testSites = new List<FormsSites.SiteInfo>();
			Assert.isNull(extension.publicLink(publicForm.Id, null), 'No Site, no address');
		}
	}
}
