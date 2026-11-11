/**
 * NPSP customizable rollups (MIG-08, canonical model R-R16): NPSP-shaped rows read into the DLRS
 * definition shape, refused with a reason when BarnCRM cannot hold them, imported with the DLRS
 * steps under `NPSP_` keys, and seen by the same-field guard. NPSP cannot be installed in a test,
 * so organizations total their child organizations, as in `RollupDlrsImportTest`.
 */
@IsTest(testFor='ApexClass:RollupNpsp, ApexClass:RollupDlrs, ApexClass:RollupDlrsImport')
private class RollupNpspTest {
	private static final String COUNT_FIELD = 'Member_Count__c';

	@TestSetup
	static void createTestUser() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			TestDataFactory.createUser(
				'Maria',
				new List<String>{ 'BarnCRM_Admin', 'Rollup_Builder_Admin' }
			);
		}
	}

	private static User maria() {
		return TestUsers.fromSetup('Maria');
	}

	/** An active NPSP rollup of child organizations into their parent, with these values. */
	private static Map<String, Object> npsp(
		String key,
		String operation,
		Map<String, Object> extra
	) {
		Map<String, Object> values = new Map<String, Object>{
			'DeveloperName' => key,
			'MasterLabel' => key.replace('_', ' '),
			'Active' => true,
			'Summary_Object' => 'Account',
			'Summary_Field' => COUNT_FIELD,
			'Detail_Object' => 'Account',
			'Operation' => operation,
			'Time_Bound_Operation_Type' => 'All_Time'
		};
		values.putAll(extra == null ? new Map<String, Object>() : extra);
		return values;
	}

	private static Map<String, Object> rule(String field, String operator, String constant) {
		return new Map<String, Object>{
			'Filter_Group' => 'G1',
			'Object' => 'Account',
			'Field' => field,
			'Operator' => operator,
			'Constant' => constant
		};
	}

	private static RollupDlrs.Definition only(
		Map<String, Object> rollup,
		List<Map<String, Object>> rules
	) {
		List<RollupDlrs.Definition> read = RollupNpsp.toDefinitions(
			new List<Map<String, Object>>{ rollup },
			rules == null ? new List<Map<String, Object>>() : rules
		);
		Assert.areEqual(1, read.size(), 'One rollup read');
		return read[0];
	}

	@IsTest
	static void aSumWithATimeBoundAndFilterRulesReadsAsDlrsWould() {
		System.runAs(maria()) {
			RollupDlrs.Definition read = only(
				npsp(
					'Revenue_Recent',
					'Sum',
					new Map<String, Object>{
						'Filter_Group' => 'G1',
						'Amount_Object' => 'Account',
						'Amount_Field' => 'AnnualRevenue',
						'Date_Field' => 'CreatedDate',
						'Time_Bound_Operation_Type' => 'Days_Back',
						'Integer' => 30
					}
				),
				new List<Map<String, Object>>{
					rule('Type', 'In_List', 'Customer;Partner'),
					rule('NumberOfEmployees', 'Greater', '10'),
					rule('Name', 'Starts_With', 'Barn')
				}
			);
			Assert.isNull(read.unsupported, 'Copyable');
			Assert.areEqual(RollupDlrs.SOURCE_NPSP, read.source, 'Marked as NPSP');
			Assert.areEqual('ParentId', read.relationshipField, 'The one standard lookup');
			Assert.areEqual('Sum', read.aggregateOperation, 'In DLRS words');
			Assert.areEqual('AnnualRevenue', read.fieldToAggregate, 'Amount Field');
			Assert.areEqual(
				'CreatedDate = LAST_N_DAYS:30 AND Type IN (\'Customer\', \'Partner\') AND ' +
				'NumberOfEmployees > 10 AND Name LIKE \'Barn%\'',
				read.relationshipCriteria,
				'Time bound, then each rule, joined by AND'
			);
			Assert.isNotNull(
				RollupDlrsCriteria.toFilter(
					read.relationshipCriteria,
					new List<Map<String, Object>>()
				),
				'The DLRS criteria reader holds it'
			);
		}
	}

	@IsTest
	static void firstReadsDetailFieldInDateOrderAndDeletedRowsAreSkipped() {
		System.runAs(maria()) {
			List<RollupDlrs.Definition> read = RollupNpsp.toDefinitions(
				new List<Map<String, Object>>{
					npsp(
						'First_Name',
						'First',
						new Map<String, Object>{
							'Detail_Field' => 'Name',
							'Amount_Field' => 'AnnualRevenue',
							'Date_Field' => 'CreatedDate',
							'Time_Bound_Operation_Type' => 'Years_Ago',
							'Integer' => 1,
							'Active' => false
						}
					),
					npsp('Gone', 'Sum', new Map<String, Object>{ 'Is_Deleted' => true })
				},
				new List<Map<String, Object>>()
			);
			Assert.areEqual(1, read.size(), 'A deleted rollup is not read');
			Assert.isFalse(read[0].active, 'Inactive kept, as DLRS ones are');
			Assert.areEqual('Name', read[0].fieldToAggregate, 'Detail Field for First');
			Assert.areEqual('CreatedDate ASC NULLS LAST', read[0].fieldToOrderBy, 'Oldest first');
			Assert.areEqual('CreatedDate = LAST_YEAR', read[0].relationshipCriteria, 'Last year');
		}
	}

	@IsTest
	static void whatBarnCrmCannotHoldStaysInNpspWithTheReason() {
		System.runAs(maria()) {
			Map<String, String> expected = new Map<String, String>{
				'Streak' => BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOperation'),
				'Fiscal' => BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonFiscalYear'),
				'Elsewhere' => BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOtherObject'),
				'Old' => BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonTimeBound'),
				'Operator' => BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOperator'),
				'Record_Type' => BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonRecordType'),
				'No_Lookup' => BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonNoLookup')
			};
			List<RollupDlrs.Definition> read = RollupNpsp.toDefinitions(
				new List<Map<String, Object>>{
					npsp('Streak', 'Donor_Streak', null),
					npsp('Fiscal', 'Sum', new Map<String, Object>{ 'Use_Fiscal_Year' => true }),
					npsp(
						'Elsewhere',
						'Sum',
						new Map<String, Object>{ 'Amount_Object' => 'Contact' }
					),
					npsp(
						'Old',
						'Sum',
						new Map<String, Object>{
							'Date_Field' => 'CreatedDate',
							'Time_Bound_Operation_Type' => 'Years_Ago',
							'Integer' => 3
						}
					),
					npsp('Operator', 'Sum', new Map<String, Object>{ 'Filter_Group' => 'G1' }),
					npsp('Record_Type', 'Sum', new Map<String, Object>{ 'Filter_Group' => 'G2' }),
					npsp(
						'No_Lookup',
						'Count',
						new Map<String, Object>{ 'Summary_Object' => 'User' }
					)
				},
				new List<Map<String, Object>>{
					rule('Name', 'Does_Not_Contain', 'x'),
					new Map<String, Object>{
						'Filter_Group' => 'G2',
						'Object' => 'Account',
						'Field' => 'RecordTypeId',
						'Operator' => 'Equals',
						'Constant' => 'No_Such_Record_Type'
					}
				}
			);
			for (RollupDlrs.Definition definition : read) {
				String start = expected.get(definition.key).substringBefore('{0}');
				Assert.isTrue(
					definition.unsupported != null && definition.unsupported.startsWith(start),
					definition.key + ' says why: ' + definition.unsupported
				);
			}
		}
	}

	@IsTest
	static void importFromNpspCopiesUnderItsOwnKeyAndTheGuardNamesNpsp() {
		System.runAs(maria()) {
			RollupDlrsFake.useNpsp(
				RollupNpsp.toDefinitions(
					new List<Map<String, Object>>{ npsp('Child_Count', 'Count', null) },
					new List<Map<String, Object>>()
				)
			);
			Assert.isTrue(RollupDlrs.hasActive(true), 'NPSP has one');
			Assert.isFalse(RollupDlrs.hasActive(false), 'DLRS has none');
			Assert.isTrue(RollupDlrsImport.getCandidates(null).isEmpty(), 'Not offered as DLRS');
			List<RollupDlrsImport.Candidate> candidates = RollupDlrsImport.getCandidates(
				RollupDlrsImport.TOOL_NPSP
			);
			Assert.areEqual(1, candidates.size(), 'Offered as NPSP');
			Assert.isTrue(candidates[0].importable, String.valueOf(candidates[0].reasons));

			List<RollupDlrsImport.ImportRow> rows = RollupDlrsImport.importRollups(
				new List<String>{ 'Child_Count' },
				RollupDlrsImport.TOOL_NPSP
			);
			Assert.areEqual(RollupDlrsImport.CREATED, rows[0].outcome, rows[0].reason);
			Rollup_Definition__c copy = [
				SELECT Definition_Key__c, Active__c
				FROM Rollup_Definition__c
				WHERE Id = :rows[0].recordId
				WITH USER_MODE
			];
			Assert.areEqual('NPSP_Child_Count', copy.Definition_Key__c, 'Keyed NPSP_');
			Assert.isFalse(copy.Active__c, 'Switched off');
			Assert.isTrue(
				RollupDlrs.conflict('Account', COUNT_FIELD).contains('NPSP Customizable Rollups'),
				'The guard names NPSP'
			);
		}
	}

	@IsTest
	static void anOrgWithoutNpspHasNoNpspRollups() {
		System.runAs(maria()) {
			// The org reader runs against whatever this org has, and never fails or returns null.
			Assert.isNotNull(new RollupNpsp().read(), 'Read without failing');
			RollupDlrsFake.use(new List<RollupDlrs.Definition>());
			Assert.isTrue(RollupDlrs.definitions(true).isEmpty(), 'No NPSP rollups to offer');
			Assert.isFalse(RollupDlrs.hasActive(true), 'So no Import From NPSP');
		}
	}
}
