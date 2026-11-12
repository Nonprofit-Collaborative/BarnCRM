/**
 * The Migration Assistant (MIG-01, canonical model R-MK1, R-MR1 to R-MR4): a kit is offered only
 * when its product is detected, steps run in order and are undone backwards, an import step
 * stages its source into an Import Batch, verification compares the numbers, and the retire
 * checklist completes the run. The "other product" is Contact, so no package is needed.
 */
@IsTest(
	testFor='ApexClass:MigrationKitService, ApexClass:MigrationController, ApexClass:MigrationStageBatch, ApexClass:IntegrationAppService'
)
private class MigrationKitServiceTest {
	private static final String APP = 'Test_App';
	private static final String KIT = 'Test_Kit';
	private static final String LAST_NAME = 'Migrationtest';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** The test product is detected by Contact, and the kit moves it. */
	private static void useKit(String stepsJson, String checklistJson, String extensionClass) {
		IntegrationAppService.catalogOverride = new List<Integration_App__mdt>{
			new Integration_App__mdt(
				DeveloperName = APP,
				MasterLabel = 'Test App',
				Category__c = 'Alternative',
				Detection_Objects__c = 'Contact',
				Show_Only_When_Installed__c = true
			)
		};
		IntegrationAppService.objectNamesOverride = new Set<String>{ 'contact' };
		MigrationKitService.catalogOverride = new List<Migration_Kit__mdt>{
			new Migration_Kit__mdt(
				DeveloperName = KIT,
				MasterLabel = 'Test Kit',
				Source_App__c = APP,
				Steps_JSON__c = stepsJson,
				Retire_Checklist_JSON__c = checklistJson,
				Extension_Class__c = extensionClass
			)
		};
	}

	private static final String TWO_TOOLS =
		'[{"key":"one","label":"One","kind":"tool","tab":"Rollup_Builder"},' +
		'{"key":"two","label":"Two","kind":"tool","tab":"Rollup_Builder"}]';
	private static final String ONE_ITEM = '[{"key":"off","text":"Switch it off."}]';

	private static String importStep(String templateKey, String lastName, String fields) {
		return '[{"key":"people","label":"People","kind":"import","source":"Contact",' +
			'"fields":' +
			fields +
			',"filters":[{"field":"LastName","value":"' +
			lastName +
			'"}],"templateKey":"' +
			templateKey +
			'"}]';
	}

	@IsTest
	static void aDetectedProductWithAKitOffersItsMigration() {
		System.runAs(TestUsers.admin()) {
			useKit(TWO_TOOLS, ONE_ITEM, null);
			List<IntegrationAppService.AppInfo> apps = IntegrationController.getApps();
			Assert.areEqual(
				KIT,
				apps[0].migrationKits[0].key,
				'The installed product links its kit'
			);
			Assert.areEqual('Test Kit', apps[0].migrationKits[0].label, 'Named by its label');

			IntegrationAppService.objectNamesOverride = new Set<String>();
			Assert.isTrue(IntegrationController.getApps().isEmpty(), 'Not installed: not listed');
			String message;
			try {
				MigrationController.getKit(KIT);
			} catch (AuraHandledException refused) {
				message = refused.getMessage();
			}
			Assert.areEqual(
				String.format(
					BarnHelp.text('Core', 'Core_Migration_ErrorNotDetected'),
					new List<String>{ 'Test Kit' }
				),
				message,
				'A kit whose product is gone is refused'
			);
		}
	}

	@IsTest
	static void toolStepsRunInOrderAndTheChecklistCompletesTheRun() {
		System.runAs(TestUsers.admin()) {
			useKit(TWO_TOOLS, ONE_ITEM, null);
			MigrationKitService.KitView view = MigrationController.getKit(KIT);
			Assert.areEqual(
				MigrationKitService.NOT_STARTED,
				view.steps[0].status,
				'First is ready'
			);
			Assert.areEqual(MigrationKitService.WAITING, view.steps[1].status, 'Second waits');
			Assert.areEqual(0, [SELECT COUNT() FROM Migration_Run__c], 'Viewing writes nothing');

			String outOfOrder;
			try {
				MigrationController.setToolStep(KIT, 'two', true);
			} catch (AuraHandledException refused) {
				outOfOrder = refused.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_Migration_ErrorOutOfOrder'),
				outOfOrder,
				'Steps run in order'
			);

			MigrationController.setToolStep(KIT, 'one', true);
			String tooEarly;
			try {
				MigrationController.setChecklistItem(KIT, 'off', true);
			} catch (AuraHandledException refused) {
				tooEarly = refused.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_Migration_ErrorNotAllDone'),
				tooEarly,
				'The checklist waits for every step'
			);
			view = MigrationController.setToolStep(KIT, 'two', true);
			Assert.isFalse(view.steps[0].canUnmark, 'A step with a later step done stays done');
			Assert.isTrue(view.steps[1].canUnmark, 'The last done step can be unmarked');

			view = MigrationController.setChecklistItem(KIT, 'off', true);
			Assert.isTrue(view.complete, 'Every step done and every item ticked');
			Assert.areEqual(
				'Complete',
				[SELECT Status__c FROM Migration_Run__c LIMIT 1].Status__c,
				'The run is Complete'
			);
			view = MigrationController.setChecklistItem(KIT, 'off', false);
			Assert.isFalse(view.complete, 'Unticking reopens it');
			Assert.areEqual(
				'In Progress',
				[SELECT Status__c FROM Migration_Run__c LIMIT 1].Status__c,
				'The run is open again'
			);
			Assert.areEqual(1, [SELECT COUNT() FROM Migration_Run__c], 'One run per kit');
		}
	}

	@IsTest
	static void anImportStepStagesItsSourceIntoADataJob() {
		System.runAs(TestUsers.admin()) {
			Import_Template__c template = ImportTemplateService.createObjectTemplate(
				'Migration test',
				'Contact'
			);
			// A kit's template maps its columns; an unmapped one fails the dry run that follows.
			ImportMapping mapping = new ImportMapping();
			mapping.columns.add(new ImportMapping.Column('Id', 'Record.Id'));
			mapping.columns.add(new ImportMapping.Column('FirstName', 'Record.FirstName'));
			mapping.columns.add(new ImportMapping.Column('Email', 'Record.Email'));
			ImportTestDataFactory.saveMapping(template.Id, mapping.serialize(), null);
			insert new List<Contact>{
				new Contact(FirstName = 'Ana', LastName = LAST_NAME, Email = 'ana@example.invalid'),
				new Contact(FirstName = 'Ben', LastName = LAST_NAME),
				new Contact(FirstName = 'Cy', LastName = 'Someoneelse')
			};
			useKit(
				importStep(
					template.Template_Key__c,
					LAST_NAME,
					'["FirstName","Email","Account.Name"]'
				),
				null,
				null
			);

			Test.startTest();
			MigrationKitService.KitView view = MigrationController.startStep(KIT, 'people');
			Test.stopTest();

			Import_Batch__c batch = [
				SELECT Row_Count__c, Expected_Count__c, Migration_Step__c, Status__c
				FROM Import_Batch__c
				WHERE Migration_Run__c != NULL
			];
			Assert.areEqual(2, batch.Row_Count__c, 'Only the records the filter names are read');
			Assert.areEqual(2, batch.Expected_Count__c, 'The source count is the control total');
			Assert.areEqual('people', batch.Migration_Step__c, 'Linked to its step');
			Map<String, Object> values;
			for (Import_Row__c row : [SELECT Raw_Values_JSON__c FROM Import_Row__c]) {
				Map<String, Object> read = (Map<String, Object>) JSON.deserializeUntyped(
					row.Raw_Values_JSON__c
				);
				if (read.get('FirstName') == 'Ana') {
					values = read;
				}
			}
			Assert.isNotNull(values, 'Each source record is a row');
			Assert.areEqual('ana@example.invalid', values.get('Email'), 'Keyed by the step field');
			Assert.isTrue(values.containsKey('Account.Name'), 'A relationship path is a column');
			Assert.isTrue(values.containsKey('Id'), 'The source Id is always read');

			view = MigrationController.getKit(KIT);
			Assert.areNotEqual(MigrationKitService.NOT_STARTED, view.steps[0].status, 'Started');
			Assert.areEqual(2, view.steps[0].sourceCount, 'Verification counts the source');
			Assert.areEqual(2, view.steps[0].staged, 'And what was read');
			Assert.isFalse(
				view.steps[0].canStart,
				'A started step cannot start again: ' + view.steps[0].status
			);
		}
	}

	@IsTest
	static void anEmptySourceIsDoneAtOnceAndVerified() {
		System.runAs(TestUsers.admin()) {
			useKit(importStep('no_template_needed', 'Nobodyhere', '["Email"]'), null, null);
			MigrationKitService.KitView view = MigrationController.startStep(KIT, 'people');
			Assert.areEqual(MigrationKitService.DONE, view.steps[0].status, 'Nothing to move');
			Assert.isTrue(view.steps[0].verified, 'Zero agrees with zero');
			Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c], 'No data job for nothing');
		}
	}

	@IsTest
	static void aFieldTheOrgLacksIsRefusedByName() {
		System.runAs(TestUsers.admin()) {
			useKit(importStep('any', LAST_NAME, '["Not_A_Field__c"]'), null, null);
			String message;
			try {
				MigrationController.startStep(KIT, 'people');
			} catch (AuraHandledException refused) {
				message = refused.getMessage();
			}
			Assert.isTrue(message.contains('Not_A_Field__c'), 'The missing name is said');
			Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c], 'Nothing started');
		}
	}

	@IsTest
	static void unreadableStepsAreShownAsAProblem() {
		System.runAs(TestUsers.admin()) {
			useKit('[{"key":"x","kind":"copy"}]', null, null);
			MigrationKitService.KitView view = MigrationController.getKit(KIT);
			Assert.isNotNull(view.problem, 'The reason is shown');
			Assert.isTrue(view.steps.isEmpty(), 'No step can run');
		}
	}

	@IsTest
	static void anExtensionChecksAToolStep() {
		System.runAs(TestUsers.admin()) {
			useKit(TWO_TOOLS, null, 'FakeExtension');
			MigrationKitService.extensionOverride.put('FakeExtension', new FakeExtension());
			MigrationKitService.KitView view = MigrationController.getKit(KIT);
			Assert.areEqual(3, view.steps[0].checkSource, 'The kit counts what to move');
			Assert.areEqual(3, view.steps[0].checkDone, 'And what is moved');
			Assert.isTrue(view.steps[0].verified, 'They agree');
			Assert.isFalse(view.steps[1].verified, 'Its other step has no check');
		}
	}

	@IsTest
	static void onlyAdministratorsCanRunAMigration() {
		System.runAs(TestUsers.standardUser('Migrationless')) {
			useKit(TWO_TOOLS, ONE_ITEM, null);
			String message;
			try {
				MigrationController.setToolStep(KIT, 'one', true);
			} catch (AuraHandledException refused) {
				message = refused.getMessage();
			}
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_Migration_ErrorNoPermission'),
				message,
				'Refused in words'
			);
		}
	}

	@IsTest
	static void namesResolveThroughDescribeAndValuesReadAsAFileWould() {
		System.runAs(TestUsers.admin()) {
			Assert.areEqual(
				'Account.Name',
				MigrationKitService.path(Contact.SObjectType, 'Account.Name', false),
				'A relationship then a field'
			);
			Assert.areEqual(
				'2026-11-11',
				MigrationKitService.text(Date.newInstance(2026, 11, 11)),
				'ISO date'
			);
			Assert.areEqual('12.50', MigrationKitService.text(12.50), 'Plain number');
			Assert.areEqual('', MigrationKitService.text(null), 'Blank for nothing');
			Assert.areEqual(
				MigrationKitService.REVIEW,
				MigrationKitService.importStatus('Dry run complete'),
				'Preview done'
			);
			Assert.areEqual(
				MigrationKitService.DONE,
				MigrationKitService.importStatus('Complete'),
				'Loaded'
			);
			Assert.areEqual(
				MigrationKitService.RUNNING,
				MigrationKitService.importStatus('Committing'),
				'Loading'
			);
			Assert.areEqual(
				MigrationKitService.FAILED,
				MigrationKitService.importStatus('Undo failed'),
				'Stuck'
			);
		}
	}

	@IsTest
	static void aLinkedColumnPointsAtWhatTheEarlierStepMoved() {
		System.runAs(TestUsers.admin()) {
			Import_Template__c template = ImportTemplateService.createObjectTemplate(
				'Migration link test',
				'Contact'
			);
			List<Contact> people = new List<Contact>{
				new Contact(LastName = 'Source'),
				new Contact(LastName = 'Moved'),
				new Contact(LastName = 'Notmoved')
			};
			insert people;
			Migration_Run__c run = new Migration_Run__c(Kit__c = KIT, Status__c = 'In Progress');
			insert run;
			Import_Batch__c batch = ImportBatchService.create(
				template.Id,
				null,
				'Earlier step',
				null,
				null,
				null,
				false
			);
			update new Import_Batch__c(
				Id = batch.Id,
				Migration_Run__c = run.Id,
				Migration_Step__c = 'first'
			);
			// Rows are written by the data job in system mode; admins only read them.
			insert as system new Import_Row__c(
				Import_Batch__c = batch.Id,
				Row_Number__c = 2,
				Status__c = 'Created',
				Row_Key__c = ImportRowFilter.digestOfValues(
					new List<String>{ String.valueOf(people[0].Id) }
				),
				Gift_Id__c = people[1].Id
			);
			MigrationKitService.Step step = (MigrationKitService.Step) JSON.deserialize(
				'{"key":"second","kind":"import","links":[{"column":"Parent","step":"first"}]}',
				MigrationKitService.Step.class
			);
			List<Map<String, Object>> rows = new List<Map<String, Object>>{
				new Map<String, Object>{ 'Parent' => String.valueOf(people[0].Id) },
				new Map<String, Object>{ 'Parent' => String.valueOf(people[2].Id) },
				new Map<String, Object>{ 'Parent' => '' }
			};

			MigrationKitService.link(step, run.Id, rows);

			Assert.areEqual(people[1].Id, rows[0].get('Parent'), 'The moved record replaces it');
			Assert.areEqual(
				String.valueOf(people[2].Id),
				rows[1].get('Parent'),
				'A source record not moved is left, so its lookup finds nothing'
			);
			Assert.areEqual('', rows[2].get('Parent'), 'A blank stays blank');
		}
	}

	@IsTest
	static void aLinkToALaterStepAndANotEqualsFilterAreRead() {
		System.runAs(TestUsers.admin()) {
			useKit(
				'[{"key":"one","kind":"tool","tab":"Rollup_Builder",' +
					'"links":[{"column":"X","step":"two"}]},' +
					'{"key":"two","kind":"tool","tab":"Rollup_Builder"}]',
				null,
				null
			);
			Assert.isNotNull(MigrationController.getKit(KIT).problem, 'Links point backwards only');

			insert new List<Contact>{
				new Contact(FirstName = 'Keep', LastName = LAST_NAME),
				new Contact(FirstName = 'Drop', LastName = LAST_NAME)
			};
			MigrationKitService.Step step = (MigrationKitService.Step) JSON.deserialize(
				'{"key":"s","kind":"import","source":"Contact","filters":[' +
					'{"field":"FirstName","value":"Drop","op":"notEquals"},' +
					'{"field":"LastName","value":"' +
					LAST_NAME +
					'"}]}',
				MigrationKitService.Step.class
			);
			Assert.areEqual(
				1,
				new MigrationKitService.Source(step).count(),
				'notEquals leaves the named value out'
			);
		}
	}

	/** A kit extension that checks only the step named one. */
	private class FakeExtension implements MigrationKitExtension {
		public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
			return null;
		}
		public MigrationCheck verify(String stepKey) {
			return stepKey == 'one' ? new MigrationCheck(3, 3) : null;
		}
	}
}
