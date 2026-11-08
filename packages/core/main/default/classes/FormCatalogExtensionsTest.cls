/**
 * Events offers a survey only when a module keeps forms, and a module that fails never breaks
 * the page (ADR-0188). Core has no module, so extensions are injected by class name.
 */
@IsTest(testFor='ApexClass:FormCatalogExtensions')
private class FormCatalogExtensionsTest {
	private static final String WORKS = 'FormsCatalogExtension';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private class Working implements FormCatalogExtension {
		public List<FormCatalogEntry> publicForms() {
			FormCatalogEntry entry = new FormCatalogEntry();
			entry.key = 'a00000000000001';
			entry.label = 'After the event';
			return new List<FormCatalogEntry>{ entry };
		}

		public List<FormCatalogEntry> questions(Id formId) {
			FormCatalogEntry entry = new FormCatalogEntry();
			entry.key = 'rating';
			entry.label = 'Rating';
			entry.kind = 'number';
			return new List<FormCatalogEntry>{ entry };
		}

		public String publicLink(Id formId, Id contextRecordId) {
			return 'https://example.test/FormsPublic?form=' + formId + '&record=' + contextRecordId;
		}
	}

	private class Failing implements FormCatalogExtension {
		public List<FormCatalogEntry> publicForms() {
			throw new System.TypeException('Cannot list');
		}

		public List<FormCatalogEntry> questions(Id formId) {
			throw new System.TypeException('Cannot read');
		}

		public String publicLink(Id formId, Id contextRecordId) {
			throw new System.TypeException('Cannot link');
		}
	}

	private static void register(FormCatalogExtension extension) {
		FormCatalogExtensions.EXTENSION_CLASSES.clear();
		FormCatalogExtensions.EXTENSION_CLASSES.add(WORKS);
		FormCatalogExtensions.overrides = new Map<String, FormCatalogExtension>{
			WORKS => extension
		};
	}

	@IsTest
	static void absentWithoutAModule() {
		System.runAs(TestUsers.admin()) {
			// No class registered, so the answer does not depend on whether Forms is installed.
			FormCatalogExtensions.EXTENSION_CLASSES.clear();
			Test.startTest();
			Boolean available = FormCatalogExtensions.isAvailable();
			Test.stopTest();
			Assert.isFalse(available, 'No module keeps forms in this org');
			Assert.isTrue(FormCatalogExtensions.publicForms().isEmpty());
			Assert.isTrue(FormCatalogExtensions.questions(UserInfo.getUserId()).isEmpty());
			Assert.isNull(FormCatalogExtensions.publicLink(UserInfo.getUserId(), null));
		}
	}

	@IsTest
	static void answersFromAnInstalledExtension() {
		System.runAs(TestUsers.admin()) {
			register(new Working());
			Test.startTest();
			Boolean available = FormCatalogExtensions.isAvailable();
			List<FormCatalogEntry> forms = FormCatalogExtensions.publicForms();
			List<FormCatalogEntry> questions = FormCatalogExtensions.questions(
				UserInfo.getUserId()
			);
			String link = FormCatalogExtensions.publicLink(UserInfo.getUserId(), null);
			Test.stopTest();
			Assert.isTrue(available);
			Assert.areEqual('After the event', forms[0].label);
			Assert.areEqual('number', questions[0].kind);
			Assert.isTrue(link.contains('FormsPublic?form='), 'The extension builds the link');
		}
	}

	@IsTest
	static void aFailingExtensionIsLoggedAndSkipped() {
		System.runAs(TestUsers.admin()) {
			register(new Failing());
			Test.startTest();
			List<FormCatalogEntry> forms = FormCatalogExtensions.publicForms();
			List<FormCatalogEntry> questions = FormCatalogExtensions.questions(
				UserInfo.getUserId()
			);
			String link = FormCatalogExtensions.publicLink(UserInfo.getUserId(), null);
			Test.stopTest();
			Assert.isTrue(forms.isEmpty());
			Assert.isTrue(questions.isEmpty());
			Assert.isNull(link);
		}
	}
}
