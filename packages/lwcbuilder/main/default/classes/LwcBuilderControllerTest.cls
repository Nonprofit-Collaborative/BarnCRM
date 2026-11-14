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
			Assert.areEqual(
				LwcBuilderController.rowsPerList(),
				studio.get('rowsPerList'),
				'Export uses the Rows per List setting (LB-07)'
			);
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

	private static Map<String, Object> group(
		String key,
		String label,
		List<Map<String, Object>> children
	) {
		return new Map<String, Object>{ 'key' => key, 'label' => label, 'children' => children };
	}

	private static List<Object> one(Object value) {
		return new List<Object>{
			new Map<String, Object>{ 'value' => value, 'label' => String.valueOf(value) }
		};
	}

	@IsTest
	static void aSummaryChartHasOneCellPerGroup() {
		// runs-as: deploying user (plain inputs, no record or report is read)
		List<String> series = new List<String>();
		List<Map<String, Object>> rows = LwcBuilderController.chartRows(
			new List<Map<String, Object>>{
				group('0', 'Alpha', new List<Map<String, Object>>()),
				group('1', 'Beta', null)
			},
			null,
			new Map<String, List<Object>>{ '0!T' => one(5) },
			series
		);
		Assert.areEqual(2, rows.size(), 'A row per group');
		Assert.areEqual('Alpha', rows[0].get('label'), 'The group label');
		Assert.areEqual(1, ((List<Object>) rows[0].get('cells')).size(), 'One cell');
		Assert.areEqual(
			0,
			((List<Object>) ((List<Object>) rows[1].get('cells'))[0]).size(),
			'A group with no fact has an empty cell'
		);
		Assert.isTrue(series.isEmpty(), 'One grouping has no series');
	}

	@IsTest
	static void aSecondGroupingBecomesTheSeriesInTheOrderMet() {
		// runs-as: deploying user (plain inputs, no record or report is read)
		List<String> series = new List<String>();
		List<Map<String, Object>> rows = LwcBuilderController.chartRows(
			new List<Map<String, Object>>{
				group(
					'0',
					'Alpha',
					new List<Map<String, Object>>{
						new Map<String, Object>{ 'key' => '0_0', 'label' => 'Open' },
						new Map<String, Object>{ 'key' => '0_1', 'label' => 'Closed' }
					}
				),
				group(
					'1',
					'Beta',
					new List<Map<String, Object>>{
						new Map<String, Object>{ 'key' => '1_1', 'label' => 'Closed' }
					}
				)
			},
			null,
			new Map<String, List<Object>>{
				'0_0!T' => one(1),
				'0_1!T' => one(2),
				'1_1!T' => one(3)
			},
			series
		);
		Assert.areEqual(new List<String>{ 'Open', 'Closed' }, series, 'Series in the order met');
		List<Object> beta = (List<Object>) rows[1].get('cells');
		Assert.areEqual(2, beta.size(), 'The lane Beta lacks is filled');
		Assert.isNull(beta[0], 'Beta has no Open');
		Assert.isNotNull(beta[1], 'Beta has Closed');
	}

	@IsTest
	static void aMatrixChartUsesItsColumnsAsSeriesAndCapsThemAtTwelve() {
		// runs-as: deploying user (plain inputs, no record or report is read)
		List<Map<String, Object>> across = new List<Map<String, Object>>();
		Map<String, List<Object>> cells = new Map<String, List<Object>>();
		for (Integer i = 0; i < 14; i++) {
			across.add(new Map<String, Object>{ 'key' => String.valueOf(i), 'label' => 'C' + i });
			cells.put('0!' + i, one(i));
		}
		List<String> series = new List<String>();
		List<Map<String, Object>> rows = LwcBuilderController.chartRows(
			new List<Map<String, Object>>{ group('0', 'Alpha', null) },
			across,
			cells,
			series
		);
		Assert.areEqual(12, series.size(), 'At most twelve series');
		Assert.areEqual(12, ((List<Object>) rows[0].get('cells')).size(), 'A cell per column');
	}

	@IsTest
	static void aDefinitionSentAsTextIsCheckedAndOneTooLargeIsRefused() {
		System.runAs(admin()) {
			Map<String, Object> saved = save(new Map<String, Object>{ 'definition' => DEFINITION });
			String notJson = refusalOf(
				new Map<String, Object>{ 'key' => 'Other', 'definition' => '{not json' }
			);
			String tooLarge = refusalOf(
				new Map<String, Object>{
					'key' => 'Other',
					'definition' => new Map<String, Object>{
						'schemaVersion' => 1,
						'sections' => new List<Object>{ 'x'.repeat(140000) }
					}
				}
			);
			String noBody;
			try {
				LwcBuilderController.saveComponent(null);
			} catch (AuraHandledException e) {
				noBody = e.getMessage();
			}

			Assert.areEqual(
				JSON.deserializeUntyped(DEFINITION),
				JSON.deserializeUntyped((String) saved.get('definition')),
				'A text definition is stored'
			);
			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Definition'),
				notJson,
				'Text that is not JSON is not a definition'
			);
			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_TooLarge'),
				tooLarge,
				'A definition over the size limit is refused'
			);
			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_NameNeeded'),
				noBody,
				'Nothing sent is a missing name'
			);
		}
	}

	@IsTest
	static void aSaveThatCannotBeStoredOrIdentifiedIsRefusedWithoutAStack() {
		System.runAs(admin()) {
			Map<String, Object> gone = save(new Map<String, Object>{ 'key' => 'Gone' });
			delete as user new Built_Component__c(Id = (Id) gone.get('id'));
			String deleted = refusalOf(new Map<String, Object>{ 'id' => gone.get('id') });
			String badId = refusalOf(new Map<String, Object>{ 'id' => 'not an id' });
			Map<String, Object> noObject = save(
				new Map<String, Object>{ 'key' => 'No_Object', 'objectName' => '' }
			);

			Assert.isNotNull(deleted, 'Updating a row that was deleted is refused');
			Assert.areEqual(
				BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Generic'),
				badId,
				'An id that is not an id shows the generic message'
			);
			Assert.areEqual(
				'',
				noObject.get('objectName') ?? '',
				'A component need not name an object'
			);
		}
	}

	@IsTest
	static void theRendererIgnoresAKeyThatIsNotAKey() {
		System.runAs(admin()) {
			Map<String, Object> result = LwcBuilderController.loadComponent('not a key');

			Assert.areEqual(true, result.get('enabled'), 'Components are on');
			Assert.areEqual(false, result.get('found'), 'A bad key finds nothing');
			Assert.isFalse(result.containsKey('definition'), 'And reads nothing');
		}
	}

	@IsTest
	static void permissionChecksStopAtFiftyNamesAndTolerateNone() {
		System.runAs(admin()) {
			List<String> names = new List<String>();
			for (Integer i = 0; i < 60; i++) {
				names.add('Not_Real_' + i);
			}

			Map<String, Boolean> held = LwcBuilderController.checkPermissions(names);

			Assert.areEqual(50, held.size(), 'At most fifty are checked');
			Assert.isFalse(held.get('Not_Real_0'), 'Unknown is false');
			Assert.isTrue(
				LwcBuilderController.checkPermissions(null).isEmpty(),
				'No names, no answers'
			);
		}
	}

	@IsTest
	static void aListShowsAtMostSixColumnsTypesItsFilterAndNeedsAKnownObject() {
		System.runAs(admin()) {
			save(new Map<String, Object>{ 'name' => 'Listed', 'key' => 'Listed' });

			Map<String, Object> wide = LwcBuilderController.loadRecords(
				JSON.serialize(
					new Map<String, Object>{
						'object' => 'Built_Component__c',
						'fields' => new List<String>{
							'Name',
							'Key__c',
							'Description__c',
							'Object_Name__c',
							'Active__c',
							'Version__c',
							'Definition__c'
						},
						'filterField' => 'Version__c',
						'filterValue' => '1',
						'orderBy' => 'Version__c'
					}
				)
			);
			Map<String, Object> noFields = LwcBuilderController.loadRecords(
				JSON.serialize(
					new Map<String, Object>{
						'object' => 'Built_Component__c',
						'fields' => 'Name',
						'parentField' => 'OwnerId',
						'recordId' => ''
					}
				)
			);
			Map<String, Object> blankFilter = LwcBuilderController.loadRecords(
				JSON.serialize(
					new Map<String, Object>{
						'object' => 'Built_Component__c',
						'fields' => new List<String>{ 'Name' },
						'filterField' => 'Description__c',
						'filterValue' => ' '
					}
				)
			);
			String noObject = listRefusal(new Map<String, Object>{ 'object' => 'Nope__c' });
			String noName = listRefusal(new Map<String, Object>{ 'fields' => new List<String>() });
			String badSort = listRefusal(
				new Map<String, Object>{ 'object' => 'Built_Component__c', 'orderBy' => 'Nope__c' }
			);

			Assert.areEqual(6, ((List<Object>) wide.get('columns')).size(), 'Six columns at most');
			Assert.areEqual(1, ((List<SObject>) wide.get('rows')).size(), 'Version 1 matches');
			Assert.isTrue(
				((List<Object>) noFields.get('columns')).isEmpty(),
				'Fields not a list: none'
			);
			Assert.isTrue(
				((List<SObject>) noFields.get('rows')).isEmpty(),
				'A parent with no id matches nothing'
			);
			Assert.areEqual(
				1,
				((List<SObject>) blankFilter.get('rows')).size(),
				'A blank filter value compares with null, so the row with no description matches'
			);
			String expected = BarnHelp.text(
				'LwcBuilder',
				'LwcBuilder_Error_Object',
				new List<Object>{ 'Nope__c' }
			);
			Assert.areEqual(expected, noObject, 'An object that is not there');
			Assert.isNotNull(noName, 'No object at all is refused');
			Assert.isTrue(
				badSort.contains('Nope__c'),
				'A sort field not on the object: ' + badSort
			);
		}
	}

	@IsTest
	static void dateAndNumberFiltersAreTypedAndBadOnesNameTheField() {
		System.runAs(admin()) {
			Map<String, Object> byDate = LwcBuilderController.loadRecords(
				JSON.serialize(
					new Map<String, Object>{
						'object' => 'Contact',
						'fields' => new List<String>{ 'LastName' },
						'filterField' => 'Birthdate',
						'filterValue' => '2001-02-03',
						'filterOperator' => 'notEquals',
						'orderBy' => 'LastName'
					}
				)
			);
			String badDate = listRefusal(
				new Map<String, Object>{
					'object' => 'Contact',
					'filterField' => 'Birthdate',
					'filterValue' => 'yesterday'
				}
			);

			Assert.areEqual(1, ((List<Object>) byDate.get('columns')).size(), 'One column');
			Assert.isTrue(((List<SObject>) byDate.get('rows')).isEmpty(), 'No contacts exist');
			Assert.isTrue(badDate.contains('yesterday'), 'The value is named: ' + badDate);
		}
	}

	@IsTest
	static void rowsPerListFallsBackToTenWhenOutOfRange() {
		insert as system new LWC_Builder_Settings__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Rows_Per_List__c = 500
		);
		SettingsService.clearCaches();
		System.runAs(admin()) {
			Assert.areEqual(
				10,
				LwcBuilderController.rowsPerList(),
				'Over 200 is the default of 10'
			);
		}
	}

	@IsTest
	static void aReportNameThatIsNotAnApiNameFindsNoReport() {
		System.runAs(admin()) {
			String refused;
			try {
				LwcBuilderController.loadChart('not a name');
			} catch (AuraHandledException e) {
				refused = e.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Chart_NoReport',
					new List<Object>{ 'not a name' }
				),
				refused,
				'Refused without querying'
			);
		}
	}

	@IsTest
	static void aChartHasAtMostTwoHundredRows() {
		// runs-as: deploying user (plain inputs, no record or report is read)
		List<Map<String, Object>> groups = new List<Map<String, Object>>();
		for (Integer i = 0; i < 205; i++) {
			groups.add(group(String.valueOf(i), 'G' + i, null));
		}
		Assert.areEqual(
			200,
			LwcBuilderController.chartRows(
					groups,
					null,
					new Map<String, List<Object>>(),
					new List<String>()
				)
				.size(),
			'Capped'
		);
	}
}
