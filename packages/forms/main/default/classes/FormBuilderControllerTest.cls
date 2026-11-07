/**
 * The Form Builder reads a form's draft, offers the objects and fields answers can be written
 * to, saves a draft, and publishes it as the next version only when every target exists.
 */
@IsTest(testFor='ApexClass:FormBuilderController')
private class FormBuilderControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	@IsTest
	static void savesADraftThenPublishesItAsTheNextVersion() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			Form__c form = new Form__c(Name = 'Zzbuild Interest', Status__c = 'Draft');
			insert as user form;
			String draft = JSON.serialize(FormsTestData.definition());

			Test.startTest();
			FormBuilderController.BuilderView opened = FormBuilderController.getBuilder(form.Id);
			FormBuilderController.BuilderView saved = FormBuilderController.saveDraft(
				form.Id,
				draft
			);
			FormBuilderController.BuilderView first = FormBuilderController.publish(form.Id, draft);
			FormBuilderController.BuilderView second = FormBuilderController.publish(
				form.Id,
				draft
			);
			Test.stopTest();

			Assert.isNull(opened.definition, 'A new form has no draft yet');
			Assert.isTrue(opened.canEdit, 'Forms Admin may change it');
			Assert.areEqual(draft, saved.definition);
			Assert.areEqual('Draft', saved.status, 'Saving a draft publishes nothing');
			Assert.areEqual(1, first.publishedVersion);
			Assert.areEqual('Published', first.status);
			Assert.areEqual(2, second.publishedVersion, 'Each publish is a new version');
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Form_Version__c WHERE Form__c = :form.Id WITH USER_MODE]
			);
		}
	}

	@IsTest
	static void refusesAFormWritingToAFieldThisOrgLacks() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			Form__c form = new Form__c(Name = 'Zzbuild Broken', Status__c = 'Draft');
			insert as user form;
			Map<String, Object> definition = FormsTestData.definition();
			FormRules.allFields(definition)[0]
				.put(
					'target',
					new Map<String, Object>{ 'record' => 'person', 'field' => 'No_Such_Field__c' }
				);

			String message;
			Test.startTest();
			try {
				FormBuilderController.publish(form.Id, JSON.serialize(definition));
			} catch (AuraHandledException e) {
				message = e.getMessage();
			}
			Test.stopTest();

			Assert.isNotNull(message, 'A missing field is refused');
			Assert.isTrue(message.contains('No_Such_Field__c'), message);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Form_Version__c WHERE Form__c = :form.Id WITH USER_MODE],
				'Nothing was published'
			);
		}
	}

	@IsTest
	static void refusesTextThatIsNotADefinition() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			Form__c form = new Form__c(Name = 'Zzbuild Garbled', Status__c = 'Draft');
			insert as user form;

			Boolean refused = false;
			Test.startTest();
			try {
				FormBuilderController.saveDraft(form.Id, 'not json');
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.isTrue(refused, 'Text that is not JSON is never saved');
		}
	}

	@IsTest
	static void offersObjectsAndWritableFields() {
		System.runAs(TestUsers.adminWith(FormsTestData.ADMIN)) {
			Test.startTest();
			List<FormBuilderController.Choice> objects = FormBuilderController.getObjects();
			List<FormBuilderController.Choice> fields = FormBuilderController.getFields('Contact');
			Test.stopTest();

			Set<String> objectNames = new Set<String>();
			for (FormBuilderController.Choice choice : objects) {
				objectNames.add(choice.value);
			}
			Assert.isFalse(objectNames.contains('Form__c'), 'The form objects are never offered');
			Set<String> fieldNames = new Set<String>();
			for (FormBuilderController.Choice choice : fields) {
				fieldNames.add(choice.value);
			}
			Assert.isTrue(fieldNames.contains('LastName'), 'A writable field is offered');
			Assert.isFalse(fieldNames.contains('Id'), 'A field nobody writes is not');
		}
	}
}
