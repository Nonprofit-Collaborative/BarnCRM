/**
 * A template is parsed and checked against the org's schema, and anything a portal must never
 * do is refused whole (canonical model R-PB2).
 */
@IsTest(testFor='ApexClass:PortalTemplate, ApexClass:PortalData')
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
			Assert.isFalse(roles.search, 'No search box unless asked');
			Map<String, Object> searchable = sample();
			rolesPage(searchable).put('search', true);
			Assert.isTrue(
				PortalTemplate.parse(JSON.serialize(searchable)).page('roles').search,
				'A page may ask for a search box (PB-09)'
			);
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

	private static Map<String, Object> withTest(String field, String op, Object value) {
		Map<String, Object> template = sample();
		rolesPage(template)
			.put(
				'where',
				new List<Object>{
					new Map<String, Object>{ 'field' => field, 'op' => op, 'value' => value }
				}
			);
		return template;
	}

	private static PortalTemplate.Condition onlyTest(Map<String, Object> template) {
		return PortalTemplate.parse(JSON.serialize(template)).page('roles').conditions[0];
	}

	/** Where values are typed for their field when read, and one that cannot be is refused. */
	@IsTest
	static void typesWhereValuesForTheirFieldOrRefusesThem() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Test.startTest();
			Object day = onlyTest(withTest('Start_Date__c', 'greaterOrEqual', '2026-01-31')).value;
			Object today = onlyTest(withTest('Start_Date__c', 'lessOrEqual', 'TODAY')).value;
			Object primary = onlyTest(withTest('Is_Primary__c', 'equals', 'true')).value;
			String badDate = refusal(withTest('Start_Date__c', 'equals', 'last week'));
			String badFlag = refusal(withTest('Is_Primary__c', 'equals', 'maybe'));
			String wordOnText = refusal(withTest('Role__c', 'equals', 'NOW'));
			Map<String, Object> binds = new Map<String, Object>();
			String soql = PortalData.conditionSoql(
				onlyTest(withTest('Start_Date__c', 'lessOrEqual', 'NOW')),
				'v0',
				binds
			);
			Test.stopTest();

			Assert.areEqual(Date.newInstance(2026, 1, 31), day, 'A date for a date field');
			Assert.areEqual('TODAY', today, 'TODAY is read when the page is queried');
			Assert.areEqual(true, primary, 'A checkbox takes true');
			Assert.isTrue(badDate.contains('Start_Date__c'), badDate);
			Assert.isNotNull(badFlag, 'A checkbox takes only true or false');
			Assert.isNotNull(wordOnText, 'TODAY and NOW are for dates');
			Assert.areEqual('Start_Date__c <= :v0', soql, 'A bound test');
			Assert.areEqual(Date.today(), binds.get('v0'), 'NOW on a date field is today');
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

	private static String pageRefusal(Map<String, Object> page) {
		Map<String, Object> template = sample();
		((List<Object>) template.get('pages')).add(page);
		return refusal(template);
	}

	@IsTest
	static void readsPersonScopeCalendarDownloadAndScan() {
		System.runAs(TestUsers.adminWith('Portal_Admin')) {
			Map<String, Object> template = sample();
			((List<Object>) template.get('pages'))
				.add(
					PortalTestData.scopedPage(
						PortalTestData.scope('Organization__c', 'Organization__c')
					)
				);
			((Map<String, Object>) ((List<Object>) rolesPage(template).get('fields'))[1])
				.put('scan', true);
			Map<String, Object> relatedScoped = sample();
			rolesPage(relatedScoped)
				.put('personScope', PortalTestData.scope('Organization__c', 'Organization__c'));
			Map<String, Object> notPerson = PortalTestData.scope(
				'Organization__c',
				'Organization__c'
			);
			notPerson.put('personField', 'Organization__c');
			Map<String, Object> badCalendar = PortalTestData.scopedPage(
				PortalTestData.scope('Organization__c', 'Organization__c')
			);
			badCalendar.put(
				'calendar',
				new Map<String, Object>{ 'title' => 'Role__c', 'start' => 'Role__c' }
			);
			Map<String, Object> scanStatus = sample();
			((Map<String, Object>) ((List<Object>) rolesPage(scanStatus).get('fields'))[2])
				.put('scan', true);

			Test.startTest();
			PortalTemplate parsed = PortalTemplate.parse(JSON.serialize(template));
			String hop = pageRefusal(
				PortalTestData.scopedPage(
					PortalTestData.scope('Contact__r.AccountId', 'Contact__r.AccountId')
				)
			);
			String notCatalog = refusal(relatedScoped);
			String notLookup = pageRefusal(
				PortalTestData.scopedPage(PortalTestData.scope('Role__c', 'Organization__c'))
			);
			String otherTarget = pageRefusal(
				PortalTestData.scopedPage(PortalTestData.scope('Organization__c', 'Contact__c'))
			);
			String noPerson = pageRefusal(PortalTestData.scopedPage(notPerson));
			String calendarStart = pageRefusal(badCalendar);
			String scanNotText = refusal(scanStatus);
			Test.stopTest();

			PortalTemplate.PageSpec page = parsed.page('colleagues');
			Assert.areEqual('Organization__c', page.scope.field, 'Scoped by organization');
			Assert.areEqual(
				Affiliation__c.SObjectType,
				page.scope.objectType,
				'Through affiliations'
			);
			Assert.areEqual(1, page.scope.conditions.size(), 'With the scope\'s own test');
			Assert.areEqual('Start_Date__c', page.calendar.get('start'), 'Calendar start');
			Assert.isTrue(page.download, 'Download CSV');
			Assert.isTrue(parsed.page('roles').field('Role__c').scan, 'Role may be scanned');
			Assert.isNull(hop, 'Either path may go through one parent: ' + hop);
			Assert.isNotNull(notCatalog, 'personScope is for catalog pages only');
			Assert.isNotNull(notLookup, 'field must be a lookup');
			Assert.isNotNull(otherTarget, 'valueField must point where field points');
			Assert.isNotNull(noPerson, 'personField must be a Contact lookup');
			Assert.isNotNull(calendarStart, 'A calendar start is a date');
			Assert.isNotNull(scanNotText, 'Only an edited text field may be scanned');
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
