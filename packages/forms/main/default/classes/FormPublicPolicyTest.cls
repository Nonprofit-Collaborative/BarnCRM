/**
 * What a public form may write (canonical model R-FM3; ADR-0184 public forms on a Salesforce
 * Site, decision 3): people, organizations and custom objects, through fields that are not
 * lookups, never overwriting; the settings read with their defaults; a public form published from
 * the Form Builder is marked Public and its version gets a signing key, and one that maps a lookup
 * is refused.
 */
@IsTest(testFor='ApexClass:FormPublicPolicy, ApexClass:FormBuilderController')
private class FormPublicPolicyTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(FormsTestData.ADMIN);
	}

	private static Map<String, Object> firstRecord(Map<String, Object> definition) {
		return (Map<String, Object>) ((List<Object>) definition.get('records'))[0];
	}

	@IsTest
	static void theVolunteerFormMayBePublic() {
		System.runAs(admin()) {
			Map<String, Object> definition = FormsTestData.publicDefinition(10);
			Assert.isTrue(FormPublicPolicy.isPublic(definition), 'Public');
			Assert.isNull(FormPublicPolicy.problem(definition), 'Nothing refused');
			Assert.areEqual(3, FormPublicPolicy.minSeconds(definition), 'Its seconds');
			Assert.areEqual(10, FormPublicPolicy.hourlyLimit(definition), 'Its limit');
			Assert.areEqual(
				'Thanks for signing up.',
				FormPublicPolicy.confirmation(definition),
				'Its thank you'
			);
			Map<String, Object> plain = FormsTestData.definition();
			Assert.isFalse(FormPublicPolicy.isPublic(plain), 'Not public without the block');
			Assert.areEqual(50, FormPublicPolicy.hourlyLimit(plain), 'The default limit');
			Assert.isNull(FormPublicPolicy.confirmation(plain), 'The shipped thank you');
		}
	}

	@IsTest
	static void overwritingLookupsAndFormsObjectsAreRefused() {
		System.runAs(admin()) {
			Map<String, Object> overwrite = FormsTestData.publicDefinition(10);
			firstRecord(overwrite)
				.put('matching', new Map<String, Object>{ 'onMatch' => 'overwrite' });
			Assert.isNotNull(FormPublicPolicy.problem(overwrite), 'Overwrite refused');

			Map<String, Object> lookup = FormsTestData.publicDefinition(10);
			List<Object> steps = (List<Object>) lookup.get('steps');
			List<Object> fields = (List<Object>) ((Map<String, Object>) steps[0]).get('fields');
			fields.add(FormsTestData.field('acct', 'text', false, 'person', 'AccountId'));
			Assert.isNotNull(FormPublicPolicy.problem(lookup), 'A lookup refused');

			Map<String, Object> own = FormsTestData.publicDefinition(10);
			List<Object> records = (List<Object>) own.get('records');
			((Map<String, Object>) records[2]).put('object', 'Form_Submission__c');
			Assert.isNotNull(FormPublicPolicy.problem(own), 'A Forms object refused');
		}
	}

	/**
	 * A Forms object is refused however its name is written: with spaces around it (which the
	 * describe would still resolve) or with the package prefix, which the list is checked
	 * against after resolving the name.
	 */
	@IsTest
	static void aFormsObjectIsRefusedUnderAnyName() {
		System.runAs(admin()) {
			Assert.isFalse(FormPublicPolicy.objectAllowed('Form_Submission__c'), 'As written');
			Assert.isFalse(FormPublicPolicy.objectAllowed(' Form_Draft__c'), 'With a space');
			Assert.isFalse(
				FormPublicPolicy.objectAllowed(NamespaceUtil.qualify('Form__c')),
				'With the prefix, where the package has one'
			);
			Assert.isTrue(FormPublicPolicy.objectAllowed('Contact'), 'A person still may');
		}
	}

	@IsTest
	static void theGuestCopyHasNoRecordsOrTargets() {
		System.runAs(admin()) {
			String copy = FormPublicPolicy.publicCopy(FormsTestData.publicDefinition(10));
			Assert.isFalse(copy.contains('Affiliation__c'), 'No object names');
			Assert.isFalse(copy.contains('"target"'), 'No targets');
			Assert.isTrue(copy.contains('"steps"'), 'The questions stay');
		}
	}

	@IsTest
	static void publishingAPublicFormMarksItAndSignsTheVersion() {
		System.runAs(admin()) {
			Form__c form = new Form__c(Name = 'Zzpublish', Status__c = 'Draft');
			insert as user form;

			FormBuilderController.BuilderView view = FormBuilderController.publish(
				form.Id,
				JSON.serialize(FormsTestData.publicDefinition(10))
			);

			Assert.isTrue(view.isPublic, 'Public');
			Form_Version__c version = [
				SELECT Signing_Key__c
				FROM Form_Version__c
				WHERE Form__c = :form.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(64, version.Signing_Key__c.length(), 'Signed');

			Map<String, Object> lookup = FormsTestData.publicDefinition(10);
			List<Object> steps = (List<Object>) lookup.get('steps');
			((List<Object>) ((Map<String, Object>) steps[0]).get('fields'))
				.add(FormsTestData.field('acct', 'text', false, 'person', 'AccountId'));
			try {
				FormBuilderController.publish(form.Id, JSON.serialize(lookup));
				Assert.fail('A public form writing a lookup is not published');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					1,
					[SELECT COUNT() FROM Form_Version__c WHERE Form__c = :form.Id WITH USER_MODE],
					'No new version'
				);
			}
		}
	}
}
