/**
 * A template is parsed and checked against the org's schema, and anything a portal must never
 * do is refused whole (canonical model R-PB2).
 */
@IsTest(testFor='ApexClass:PortalTemplate')
private class PortalTemplateTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Portal_Admin');
	}

	private static Map<String, Object> sample() {
		return (Map<String, Object>) JSON.deserializeUntyped(PortalTestData.template());
	}

	private static Map<String, Object> rolesPage(Map<String, Object> template) {
		return (Map<String, Object>) ((List<Object>) template.get('pages'))[1];
	}

	private static String refusal(Map<String, Object> template) {
		try {
			PortalTemplate.parse(JSON.serialize(template));
		} catch (PortalTemplate.TemplateException refused) {
			return refused.getMessage();
		}
		return null;
	}

	@IsTest
	static void readsTheSampleTemplate() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Test.startTest();
			PortalTemplate template = PortalTemplate.parse(PortalTestData.template());
			Test.stopTest();

			Assert.areEqual(2, template.pages.size(), 'Two pages');
			PortalTemplate.PageSpec roles = template.page('roles');
			Assert.areEqual(Affiliation__c.SObjectType, roles.objectType, 'The related object');
			Assert.areEqual('Contact__c', roles.personField, 'Filtered by the person');
			Assert.isTrue(roles.canUpdate && !roles.canCreate, 'Update only');
			Assert.areEqual(
				'Say Thanks',
				roles.extensionLabels.get('Test.Thanks'),
				'The module action'
			);
			Assert.areEqual(
				'Organization',
				roles.field('Organization__r.Name').label,
				'Label from the template'
			);
			Assert.areEqual('Role__c ASC', roles.orderBy, 'Ordered');
			Assert.areEqual(1, roles.conditions.size(), 'One fixed test');
			Assert.isNull(template.page('nope'), 'An unknown page is absent');
		}
	}

	@IsTest
	static void refusesWhatAPortalMustNeverDo() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Map<String, Object> editsTheLink = sample();
			((List<Object>) rolesPage(editsTheLink).get('fields'))
				.add(new Map<String, Object>{ 'field' => 'Contact__c', 'edit' => true });
			Map<String, Object> standardObject = sample();
			rolesPage(standardObject).put('object', 'Account');
			Map<String, Object> ownObject = sample();
			rolesPage(ownObject).put('object', 'Portal_Session__c');
			Map<String, Object> notAPersonLink = sample();
			rolesPage(notAPersonLink).put('personField', 'Organization__c');
			Map<String, Object> catalogWithoutTests = sample();
			rolesPage(catalogWithoutTests).put('kind', 'catalog');
			rolesPage(catalogWithoutTests).remove('where');
			rolesPage(catalogWithoutTests).put('actions', new List<Object>());
			Map<String, Object> unknownField = sample();
			((List<Object>) rolesPage(unknownField).get('fields'))
				.add(new Map<String, Object>{ 'field' => 'Nope__c' });
			Map<String, Object> unknownOp = sample();
			((Map<String, Object>) ((List<Object>) rolesPage(unknownOp).get('where'))[0])
				.put('op', 'like');
			Map<String, Object> oldVersion = sample();
			oldVersion.put('schemaVersion', 2);
			Map<String, Object> createOnPerson = sample();
			((Map<String, Object>) ((List<Object>) createOnPerson.get('pages'))[0])
				.put('actions', new List<Object>{ 'create' });

			Test.startTest();
			List<String> refusals = new List<String>{
				refusal(editsTheLink),
				refusal(standardObject),
				refusal(ownObject),
				refusal(notAPersonLink),
				refusal(catalogWithoutTests),
				refusal(unknownField),
				refusal(unknownOp),
				refusal(oldVersion),
				refusal(createOnPerson)
			};
			Test.stopTest();

			for (Integer i = 0; i < refusals.size(); i++) {
				Assert.isNotNull(refusals[i], 'Template ' + i + ' is refused');
			}
			Assert.isTrue(refusals[0].contains('cannot be edited'), refusals[0]);
			Assert.isTrue(refusals[1].contains('custom object'), refusals[1]);
		}
	}

	private static final String VIA_PARENT = 'Reciprocal_Relationship__r.Contact__c';

	private static Map<String, Object> viaParentTemplate(Map<String, Object> page) {
		Map<String, Object> template = sample();
		template.put('pages', new List<Object>{ page });
		return template;
	}

	private static Map<String, Object> viaParentPage(String personField) {
		return new Map<String, Object>{
			'key' => 'kin',
			'title' => 'Kin',
			'kind' => 'related',
			'object' => 'Relationship__c',
			'personField' => personField,
			'fields' => new List<Object>{ new Map<String, Object>{ 'field' => 'Name' } }
		};
	}

	@IsTest
	static void reachesThePersonThroughOneParentForReadingOnly() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Map<String, Object> editPage = viaParentPage(VIA_PARENT);
			editPage.put(
				'fields',
				new List<Object>{ new Map<String, Object>{ 'field' => 'Name', 'edit' => true } }
			);
			Map<String, Object> writePage = viaParentPage(VIA_PARENT);
			writePage.put('actions', new List<Object>{ 'update' });

			Test.startTest();
			PortalTemplate template = PortalTemplate.parse(
				JSON.serialize(viaParentTemplate(viaParentPage(VIA_PARENT)))
			);
			String editRefusal = refusal(viaParentTemplate(editPage));
			String updateRefusal = refusal(viaParentTemplate(writePage));
			String notContact = refusal(
				viaParentTemplate(viaParentPage('Reciprocal_Relationship__r.Name'))
			);
			String twoHops = refusal(
				viaParentTemplate(viaParentPage('Reciprocal_Relationship__r.Contact__r.Id'))
			);
			Test.stopTest();

			Assert.isTrue(template.page('kin').personViaParent, 'Reached through the parent');
			Assert.isNotNull(editRefusal, 'Nothing is editable through a parent');
			Assert.isNotNull(updateRefusal, 'No update through a parent');
			Assert.isNotNull(notContact, 'The parent field must be a Contact lookup');
			Assert.isNotNull(twoHops, 'One hop only');
		}
	}

	@IsTest
	static void refusesABlankOrBrokenTemplate() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Test.startTest();
			String blank = refusalOf('');
			String notJson = refusalOf('{ pages');
			String noPages = refusalOf('{"schemaVersion": 1, "pages": []}');
			Test.stopTest();

			Assert.isNotNull(blank, 'No template');
			Assert.isNotNull(notJson, 'Not JSON');
			Assert.isNotNull(noPages, 'No pages');
		}
	}

	private static String refusalOf(String source) {
		try {
			PortalTemplate.parse(source);
		} catch (PortalTemplate.TemplateException refused) {
			return refused.getMessage();
		}
		return null;
	}
}
