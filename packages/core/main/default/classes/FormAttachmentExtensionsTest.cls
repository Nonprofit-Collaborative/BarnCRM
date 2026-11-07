/**
 * A module attaches a form to its own records and hears about each processed submission, and a
 * module that fails never stops the form (ADR-0175 `0175-forms-module.md`, decision 9). Core has
 * no module, so extensions are injected by class name, as modules register theirs.
 */
@IsTest(testFor='ApexClass:FormAttachmentExtensions')
private class FormAttachmentExtensionsTest {
	private static final String EVENTS_CLASS = 'EventsFormAttachmentExtension';
	private static final String BROKEN_CLASS = 'BrokenFormAttachmentExtension';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** Takes forms on accounts, attaches one form to every account and keeps what it hears. */
	private class Recording implements FormAttachmentExtension {
		Id formId;
		List<FormSubmissionReceipt> heard = new List<FormSubmissionReceipt>();

		Recording(Id formId) {
			this.formId = formId;
		}

		public Boolean handles(Schema.SObjectType contextType) {
			return contextType == Account.SObjectType;
		}

		public Id formFor(Id contextRecordId) {
			return formId;
		}

		public Boolean signedClaim(Id contextRecordId) {
			return true;
		}

		public void received(FormSubmissionReceipt receipt) {
			heard.add(receipt);
		}
	}

	/** Writes a record, then fails, as a module with a bug might. */
	private class Failing implements FormAttachmentExtension {
		public Boolean handles(Schema.SObjectType contextType) {
			return true;
		}

		public Id formFor(Id contextRecordId) {
			throw new System.TypeException('Cannot tell');
		}

		public Boolean signedClaim(Id contextRecordId) {
			throw new System.TypeException('Cannot tell');
		}

		public void received(FormSubmissionReceipt receipt) {
			insert as user new Account(Name = 'Written Before The Failure');
			throw new System.TypeException('The module refused it');
		}
	}

	private static void register(Map<String, FormAttachmentExtension> byName) {
		FormAttachmentExtensions.EXTENSION_CLASSES.clear();
		FormAttachmentExtensions.EXTENSION_CLASSES.addAll(byName.keySet());
		FormAttachmentExtensions.overrides = byName;
	}

	private static Account context() {
		Account record = new Account(Name = 'Spring Gala');
		insert as user record;
		return record;
	}

	@IsTest
	static void theModuleNamesTheFormAndHearsTheSubmission() {
		System.runAs(TestUsers.admin()) {
			Account gala = context();
			// Any record identifier stands for the form: Core never reads it.
			Recording events = new Recording(gala.Id);
			register(
				new Map<String, FormAttachmentExtension>{
					EVENTS_CLASS => (FormAttachmentExtension) events
				}
			);

			FormSubmissionReceipt receipt = new FormSubmissionReceipt();
			receipt.contextRecordId = gala.Id;
			receipt.answers.put('email', 'pat@example.org');
			List<String> failures = FormAttachmentExtensions.notify(receipt);

			Assert.areEqual(
				gala.Id,
				FormAttachmentExtensions.formFor(gala.Id),
				'The form it attached'
			);
			Assert.isTrue(failures.isEmpty(), 'Nothing failed');
			Assert.areEqual(1, events.heard.size(), 'The module heard the submission once');
			Assert.areEqual(
				'pat@example.org',
				events.heard[0].answers.get('email'),
				'With its answers'
			);
			Assert.isNull(FormAttachmentExtensions.formFor(null), 'No record, no form');
			Assert.isTrue(
				FormAttachmentExtensions.notify(new FormSubmissionReceipt()).isEmpty(),
				'A submission filled from no record goes to no module'
			);
		}
	}

	@IsTest
	static void aFailingModuleIsRolledBackLoggedAndReported() {
		System.runAs(TestUsers.admin()) {
			Account gala = context();
			Recording events = new Recording(null);
			register(
				new Map<String, FormAttachmentExtension>{
					BROKEN_CLASS => (FormAttachmentExtension) new Failing(),
					EVENTS_CLASS => (FormAttachmentExtension) events
				}
			);

			FormSubmissionReceipt receipt = new FormSubmissionReceipt();
			receipt.contextRecordId = gala.Id;
			Test.startTest();
			List<String> failures = FormAttachmentExtensions.notify(receipt);
			Id found = FormAttachmentExtensions.formFor(gala.Id);
			Test.stopTest();

			Assert.areEqual(new List<String>{ 'The module refused it' }, failures, 'Reported');
			Assert.areEqual(1, events.heard.size(), 'The other module still heard it');
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Account
					WHERE Name = 'Written Before The Failure'
					WITH USER_MODE
				],
				'What the failing module wrote was rolled back'
			);
			Assert.isNull(found, 'A failing lookup finds nothing');
		}
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM Error_Log__c
				WHERE
					Context__c IN (
						'FormAttachmentExtensions.notify',
						'FormAttachmentExtensions.formFor'
					)
				WITH SYSTEM_MODE
			],
			'Both failures are in the Error Log'
		);
	}

	@IsTest
	static void aClassThatIsNotAnInstalledExtensionIsAbsent() {
		System.runAs(TestUsers.admin()) {
			FormAttachmentExtensions.overrides = new Map<String, FormAttachmentExtension>();
			for (
				String name : new List<String>{
					'NoSuchClassAnywhere',
					'ExtensionFakeNotAnExtension',
					'ExtensionFakeUnbuildable'
				}
			) {
				FormAttachmentExtensions.EXTENSION_CLASSES.clear();
				FormAttachmentExtensions.EXTENSION_CLASSES.add(name);
				Assert.isTrue(FormAttachmentExtensions.installed().isEmpty(), name + ' is absent');
			}
		}
	}
}
