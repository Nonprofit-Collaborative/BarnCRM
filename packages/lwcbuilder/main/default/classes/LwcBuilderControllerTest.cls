/**
 * The LWC Builder's Apex (LB-01 to LB-05): an admin saves and versions a component, the
 * renderer finds it by key as the viewer, list blocks read only what the schema and the user
 * allow, and every refusal says what to fix.
 */
@IsTest(testFor='ApexClass:LwcBuilderController, ApexClass:LwcBuilderComponentPicklist')
private class LwcBuilderControllerTest {
	private static final String DEFINITION = '{"schemaVersion":1,"sections":[]}';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith('LWC_Builder_Admin');
		TestUsers.standardUserWith('Staff', new List<String>{ 'LWC_Builder_Staff' });
	}

	private static User admin() {
		return TestUsers.adminWith('LWC_Builder_Admin');
	}

	private static Map<String, Object> save(Map<String, Object> component) {
		Map<String, Object> input = new Map<String, Object>{
			'name' => 'Donor Snapshot',
			'key' => 'Donor_Snapshot',
			'objectName' => 'Contact',
			'active' => true,
			'definition' => JSON.deserializeUntyped(DEFINITION)
		};
		input.putAll(component);
		return LwcBuilderController.saveComponent(JSON.serialize(input));
	}

	private static String refusalOf(Map<String, Object> component) {
		try {
			save(component);
		} catch (AuraHandledException e) {
			return e.getMessage();
		}
		return null;
	}

	@IsTest
	static void anAdminSavesVersionsAndTheRendererFindsItByKey() {
		System.runAs(admin()) {
			Test.startTest();
			Map<String, Object> first = save(new Map<String, Object>());
			Map<String, Object> second = save(new Map<String, Object>{ 'id' => first.get('id') });
			Map<String, Object> shown = LwcBuilderController.loadComponent('Donor_Snapshot');
			save(new Map<String, Object>{ 'id' => first.get('id'), 'active' => false });
			Map<String, Object> hidden = LwcBuilderController.loadComponent('Donor_Snapshot');
			Map<String, Object> studio = LwcBuilderController.getStudio();
			Test.stopTest();

			Assert.areEqual(
				1,
				((Decimal) first.get('version')).intValue(),
				'A new component is version 1'
			);
			Assert.areEqual(
				2,
				((Decimal) second.get('version')).intValue(),
				'Each save raises the version'
			);
			Assert.areEqual(true, shown.get('found'), 'The renderer finds it by key');
			Assert.areEqual(DEFINITION, shown.get('definition'), 'With its definition');
			Assert.areEqual(false, hidden.get('found'), 'An inactive component shows nothing');
			Assert.areEqual(
				1,
				((List<Object>) studio.get('components')).size(),
				'One row in the builder'
			);
			Assert.areEqual(true, studio.get('sourceExport'), 'Source export ships on');
		}
	}

	@IsTest
	static void eachRefusalSaysWhatToFix() {
		System.runAs(admin()) {
			save(new Map<String, Object>());

			Test.startTest();
			Map<String, String> refusals = new Map<String, String>{
				'name' => refusalOf(new Map<String, Object>{ 'name' => ' ', 'key' => 'Other' }),
				'key' => refusalOf(new Map<String, Object>{ 'key' => 'has space' }),
				'dotted' => refusalOf(new Map<String, Object>{ 'key' => 'Has.Dot' }),
				'used' => refusalOf(new Map<String, Object>{ 'key' => 'DONOR_SNAPSHOT' }),
				'object' => refusalOf(
					new Map<String, Object>{ 'key' => 'Other', 'objectName' => 'Not_There__c' }
				),
				'definition' => refusalOf(
					new Map<String, Object>{
						'key' => 'Other',
						'definition' => new Map<String, Object>{ 'schemaVersion' => 2 }
					}
				)
			};
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_NameNeeded'),
				refusals.get('name'),
				'Name'
			);
			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Key'),
				refusals.get('key'),
				'Key'
			);
			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Key'),
				refusals.get('dotted'),
				'No dots'
			);
			Assert.areEqual(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Error_KeyUsed',
					new List<Object>{ 'DONOR_SNAPSHOT' }
				),
				refusals.get('used'),
				'Keys are unique whatever the case'
			);
			Assert.areEqual(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Error_Object',
					new List<Object>{ 'Not_There__c' }
				),
				refusals.get('object'),
				'Object'
			);
			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Definition'),
				refusals.get('definition'),
				'Definition'
			);
		}
	}

	@IsTest
	static void staffSeeComponentsButCannotSaveThem() {
		System.runAs(admin()) {
			save(new Map<String, Object>());
		}
		User staff = [SELECT Id FROM User WHERE LastName = 'Staff' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(staff) {
			Test.startTest();
			Map<String, Object> shown = LwcBuilderController.loadComponent('Donor_Snapshot');
			String refused = refusalOf(new Map<String, Object>{ 'key' => 'Staff_Component' });
			Test.stopTest();

			Assert.areEqual(true, shown.get('found'), 'Staff read built components');
			Assert.isNotNull(refused, 'Only LWC Builder Admin holders create them');
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Built_Component__c
					WHERE Key__c = 'Staff_Component'
					WITH SYSTEM_MODE
				],
				'Nothing saved'
			);
		}
	}

	@IsTest
	static void theSettingsHideComponentsAndCapLists() {
		insert as system new LWC_Builder_Settings__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Components_Enabled__c = false,
			Rows_Per_List__c = 2
		);
		SettingsService.clearCaches();
		System.runAs(admin()) {
			save(new Map<String, Object>());

			Test.startTest();
			Map<String, Object> result = LwcBuilderController.loadComponent('Donor_Snapshot');
			Integer rows = LwcBuilderController.rowsPerList();
			Test.stopTest();

			Assert.areEqual(
				false,
				result.get('enabled'),
				'Show Built Components off hides them all'
			);
			Assert.areEqual(false, result.get('found'), 'And nothing is read');
			Assert.areEqual(2, rows, 'Rows per List as saved');
		}
	}

	@IsTest
	static void listBlocksReadOnlyNamedFieldsAndBindTheFilter() {
		System.runAs(admin()) {
			for (String key : new List<String>{ 'Alpha', 'Bravo', 'Charlie' }) {
				save(
					new Map<String, Object>{
						'name' => key,
						'key' => key,
						'active' => key != 'Bravo'
					}
				);
			}

			Test.startTest();
			Map<String, Object> active = LwcBuilderController.loadRecords(
				JSON.serialize(
					new Map<String, Object>{
						'object' => 'Built_Component__c',
						'fields' => new List<String>{ 'Name', 'Key__c', 'Key__c' },
						'filterField' => 'Active__c',
						'filterValue' => 'true',
						'orderBy' => 'Name',
						'direction' => 'desc'
					}
				)
			);
			Map<String, Object> mine = LwcBuilderController.loadRecords(
				JSON.serialize(
					new Map<String, Object>{
						'object' => 'Built_Component__c',
						'fields' => new List<String>{ 'Name' },
						'parentField' => 'OwnerId',
						'recordId' => UserInfo.getUserId(),
						'filterField' => 'Active__c',
						'filterOperator' => 'notEquals',
						'filterValue' => 'true'
					}
				)
			);
			String badField = listRefusal(
				new Map<String, Object>{
					'object' => 'Built_Component__c',
					'fields' => new List<String>{ 'Nope__c' }
				}
			);
			String injected = listRefusal(
				new Map<String, Object>{
					'object' => 'Built_Component__c',
					'fields' => new List<String>{ 'Name FROM User' }
				}
			);
			String badValue = listRefusal(
				new Map<String, Object>{
					'object' => 'Built_Component__c',
					'filterField' => 'Version__c',
					'filterValue' => 'abc'
				}
			);
			Test.stopTest();

			List<Object> columns = (List<Object>) active.get('columns');
			List<SObject> rows = (List<SObject>) active.get('rows');
			Assert.areEqual(2, columns.size(), 'A field named twice is one column');
			Assert.areEqual(
				true,
				((Map<String, Object>) columns[0]).get('isName'),
				'Name links to the record'
			);
			Assert.areEqual(2, rows.size(), 'Only active components');
			Assert.areEqual('Charlie', rows[0].get('Name'), 'Sorted descending');
			Assert.areEqual(
				1,
				((List<SObject>) mine.get('rows')).size(),
				'Parent and not-equals filters'
			);
			Assert.areEqual(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Error_Field',
					new List<Object>{ 'Nope__c', 'Built_Component__c' }
				),
				badField,
				'A field not on the object'
			);
			Assert.areEqual(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Error_Field',
					new List<Object>{ 'Name FROM User', 'Built_Component__c' }
				),
				injected,
				'Anything but a field name is refused, never spliced into the query'
			);
			Assert.isTrue(
				badValue.contains('abc'),
				'A value that is not a number is refused: ' + badValue
			);
		}
	}

	private static String listRefusal(Map<String, Object> request) {
		try {
			LwcBuilderController.loadRecords(JSON.serialize(request));
		} catch (AuraHandledException e) {
			return e.getMessage();
		}
		return null;
	}

	@IsTest
	static void permissionsChartsAndThePicklist() {
		System.runAs(admin()) {
			save(new Map<String, Object>());

			Test.startTest();
			Map<String, Boolean> held = LwcBuilderController.checkPermissions(
				new List<String>{ 'LWC_Builder_Not_Real', 'not a name' }
			);
			String chart;
			try {
				LwcBuilderController.loadChart('No_Such_Report_Anywhere');
			} catch (AuraHandledException e) {
				chart = e.getMessage();
			}
			LwcBuilderComponentPicklist picklist = new LwcBuilderComponentPicklist();
			VisualEditor.DynamicPickListRows values = picklist.getValues();
			VisualEditor.DataRow first = picklist.getDefaultValue();
			Test.stopTest();

			Assert.areEqual(
				new Map<String, Boolean>{ 'LWC_Builder_Not_Real' => false },
				held,
				'Unknown is false'
			);
			Assert.areEqual(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Chart_NoReport',
					new List<Object>{ 'No_Such_Report_Anywhere' }
				),
				chart,
				'A report that is not there'
			);
			Assert.areEqual(
				0,
				LwcBuilderController.cell(null, 3).size(),
				'A report cell with no fact is empty, not an error (LB-07)'
			);
			Assert.areEqual(1, values.getDataRows().size(), 'Every component the admin can read');
			Assert.areEqual('Donor_Snapshot', first.getValue(), 'The picklist stores the key');
		}
	}
}
