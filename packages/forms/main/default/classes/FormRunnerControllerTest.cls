/**
 * The Form Runner offers published forms, opens the one given or the one a module attached to
 * the record, and sends answers through the submit service.
 */
@IsTest(testFor='ApexClass:FormRunnerController')
private class FormRunnerControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	@IsTest
	static void offersPublishedFormsAndOpensTheOneGivenOrAttached() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			Form__c form = FormsTestData.volunteerInterest();
			insert as user new Form__c(Name = 'Not Yet', Status__c = 'Draft');
			Account gala = AccountKindsTestData.organization('Zzform Gala');
			insert as user gala;
			FormsTestModule.register();
			FormsTestModule.attachedFormId = form.Id;

			List<FormRunnerController.FormOption> options = FormRunnerController.getPublishedForms();
			FormRunnerController.FormView given = FormRunnerController.getForm(form.Id, null);
			FormRunnerController.FormView attached = FormRunnerController.getForm(null, gala.Id);

			Assert.areEqual(1, options.size(), 'Only the published form is offered');
			Assert.areEqual('Volunteer Interest', options[0].name);
			Assert.areEqual(1, given.version, 'Its published version');
			Assert.isTrue(given.definition.contains('"schemaVersion":1'), 'With its definition');
			Assert.isTrue(given.canSubmit, 'The admin may send answers');
			Assert.areEqual(form.Id, attached.formId, 'The form the module attached');
			Assert.areEqual(gala.Id, attached.contextRecordId, 'Filled from the record');
			Assert.isNull(FormRunnerController.getForm(null, null), 'Nothing given, nothing open');
		}
	}

	@IsTest
	static void sendsAnswersAndExplainsARefusal() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			Form__c form = FormsTestData.volunteerInterest();
			Form__c draft = new Form__c(Name = 'Draft', Status__c = 'Draft');
			insert as user draft;

			Test.startTest();
			FormSubmitService.Result result = FormRunnerController.submit(
				form.Id,
				'{"last":"Zzrunner","email":"zz.runner@example.org"}',
				null
			);
			Test.stopTest();

			Assert.areEqual(FormSubmitService.PROCESSED, result.status, result.message);
			Assert.areEqual(
				FormSubmitService.INVALID,
				FormRunnerController.submit(form.Id, '', null).status,
				'No answers: the last name is required'
			);
			try {
				FormRunnerController.submit(draft.Id, '{}', null);
				Assert.fail('A draft is refused');
			} catch (AuraHandledException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'In plain words');
			}
		}
	}
}
