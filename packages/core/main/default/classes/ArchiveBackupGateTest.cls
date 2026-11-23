/**
 * The backup before every archive rule run (D-223, ADR-0240 amendment AR-15): the archive starts
 * only from a backup saved in full; a backup that is not saved skips the run and logs it; Skip
 * Backup Before Archive starts the run at once, saying who turned it on and when.
 *
 * The big object is replaced by `ArchiveStoreMemory`, and each archive link is run in turn by the
 * test, since an Apex test can neither write a big object nor chain queueables.
 */
@IsTest(testFor='ApexClass:ArchiveBackupGate, ApexClass:BackupSetService, ApexClass:FindExportBatch')
private class ArchiveBackupGateTest {
	@TestSetup
	// runs-as: deploying user (creates the test users themselves)
	static void createUsers() {
		TestUsers.admin();
		archivist();
	}

	private static final String VOLUNTEERS = JSON.serialize(
		new Map<String, Object>{
			'version' => 1,
			'object' => 'Contact',
			'fields' => new List<Object>{ 'LastName' },
			'filter' => new Map<String, Object>{
				'version' => 1,
				'conditions' => new List<Object>{
					new Map<String, Object>{
						'id' => 1,
						'field' => 'Title',
						'operator' => 'equals',
						'value' => 'Volunteer'
					}
				}
			}
		}
	);

	private static User archivist() {
		return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' });
	}

	private static void makePeople() {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		insert new List<Contact>{
			TestDataFactory.person(new Contact(LastName = 'Staff Person', Title = 'Staff')),
			TestDataFactory.person(new Contact(LastName = 'Archived One', Title = 'Volunteer')),
			TestDataFactory.person(new Contact(LastName = 'Archived Two', Title = 'Volunteer'))
		};
	}

	/** A Big Object rule on the volunteers, saved as the running person. */
	private static Saved_Query__c rule() {
		ArchiveRules.Rule settings = new ArchiveRules.Rule();
		settings.destination = ArchiveRules.BIG_OBJECT;
		Saved_Query__c query = new Saved_Query__c(
			Name = 'Old Volunteers',
			Object_Name__c = 'Contact',
			Query_JSON__c = ArchiveRules.withRule(VOLUNTEERS, settings)
		);
		insert as user query;
		return query;
	}

	private static void drain() {
		Integer ran = 0;
		while (!BigObjectArchiveJob.queuedForTest.isEmpty()) {
			((Queueable) BigObjectArchiveJob.queuedForTest.remove(0)).execute(null);
			ran++;
			System.Assert.isTrue(ran < 50, 'The chain ends');
		}
	}

	private static Import_Batch__c job(String operation) {
		return [
			SELECT Id, Status__c, Run_Log__c, Operation_JSON__c
			FROM Import_Batch__c
			WHERE Operation__c = :operation
			WITH SYSTEM_MODE
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
	}

	@IsTest
	static void aBackupSavedInFullStartsTheArchive() {
		System.runAs(TestUsers.admin()) {
			makePeople();
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		System.runAs(archivist()) {
			Saved_Query__c query = rule();
			Test.startTest();
			ArchiveRuleService.Panel panel = ArchiveController.runRule(query.Id, 2);
			System.Assert.isTrue(panel.rules[0].running, 'Running while its backup is saved');
			System.Assert.isTrue(BigObjectArchiveJob.queuedForTest.isEmpty(), 'Nothing archived before the backup');
			try {
				ArchiveController.runRule(query.Id, 2);
				System.Assert.fail('A second run waits for the backup');
			} catch (AuraHandledException expected) {
				System.Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Refused with a reason');
			}
			// The backup's export runs here; its finish starts the archive.
			Test.stopTest();
			drain();
		}
		Import_Batch__c backup = job(BackupSetService.OPERATION_BACKUP);
		System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, backup.Status__c, backup.Run_Log__c);
		System.Assert.isTrue(
			backup.Run_Log__c.contains(BarnHelp.text('Core', 'Core_ArchiveBackup_LogArchiveStarted')),
			backup.Run_Log__c
		);
		System.Assert.isTrue(backup.Operation_JSON__c.contains('"documents"'), 'The backup files are kept');
		Import_Batch__c archive = job(BigObjectArchiveJob.OPERATION_ARCHIVE);
		System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, archive.Status__c, archive.Run_Log__c);
		System.Assert.isTrue(
			archive.Run_Log__c.contains(
				BarnHelp.text('Core', 'Core_ArchiveBackup_LogBackedUp', new List<Object>{ (2).format() })
			),
			'Says what was backed up: ' + archive.Run_Log__c
		);
		System.Assert.areEqual(2, store.rowsByKey.size(), 'Both volunteers archived');
		System.Assert.areEqual(1, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Only the staff person stays');
	}

	@IsTest
	static void aBackupNotSavedSkipsTheRunAndLogsIt() {
		System.runAs(TestUsers.admin()) {
			makePeople();
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		System.runAs(archivist()) {
			Saved_Query__c query = rule();
			Import_Batch__c backup = ArchiveRuleService.run(query.Id, 2);
			System.Assert.areEqual(
				BackupSetService.OPERATION_BACKUP,
				[
					SELECT Operation__c
					FROM Import_Batch__c
					WHERE Id = :backup.Id
					WITH SYSTEM_MODE
				]
				.Operation__c,
				'The run starts with its backup'
			);
			// The export finishes without saving every part.
			BackupSetService.afterExport(backup.Id, true, 0, 0, null, null, false, null);
			System.Assert.isTrue(BigObjectArchiveJob.queuedForTest.isEmpty(), 'No archive started');
			ArchiveRuleService.Panel panel = ArchiveController.getRules();
			System.Assert.isFalse(panel.rules[0].running, 'The rule is free to run again');
			System.Assert.areEqual(1, panel.runs.size(), 'The skipped run is listed');
			System.Assert.areEqual(ImportBatchService.STATUS_FAILED, panel.runs[0].status, 'As Failed');
			System.Assert.isTrue(
				panel.runs[0].log.contains(BarnHelp.text('Core', 'Core_ArchiveBackup_NotSaved')),
				panel.runs[0].log
			);
		}
		System.Assert.areEqual(0, store.rowsByKey.size(), 'Nothing archived');
		System.Assert.areEqual(3, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Nothing deleted');
		System.Assert.areEqual(
			1,
			[SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'ArchiveBackupGate' WITH SYSTEM_MODE],
			'The Error Log says so'
		);
		System.Assert.areEqual(ImportBatchService.STATUS_FAILED, job(BackupSetService.OPERATION_BACKUP).Status__c);
	}

	@IsTest
	static void skippingTheBackupStartsAtOnceAndSaysWhoTurnedItOn() {
		User admin = TestUsers.admin();
		System.runAs(admin) {
			makePeople();
			SettingsController.saveSettings(new Map<String, Object>{ ArchiveBackupGate.SKIP_KEY => true });
		}
		String adminName = [SELECT Name FROM User WHERE Id = :admin.Id WITH SYSTEM_MODE].Name;
		ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		System.runAs(archivist()) {
			System.Assert.isTrue(ArchiveBackupGate.skipBackup(), 'On');
			System.Assert.isTrue(
				ArchiveBackupGate.turnedOnNote().contains(adminName),
				ArchiveBackupGate.turnedOnNote()
			);
			Saved_Query__c query = rule();
			ArchiveController.runRule(query.Id, 2);
			System.Assert.areEqual(1, BigObjectArchiveJob.queuedForTest.size(), 'The archive started at once');
		}
		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Import_Batch__c WHERE Operation__c = 'Backup' WITH SYSTEM_MODE],
			'No backup'
		);
		String log = job(BigObjectArchiveJob.OPERATION_ARCHIVE).Run_Log__c;
		System.Assert.isTrue(log.contains(adminName), 'The run log names who turned it on: ' + log);
		System.runAs(admin) {
			String note;
			for (SettingsController.SectionModel section : SettingsController.getConsoleModel().sections) {
				for (SettingsController.SettingModel setting : section.settings) {
					if (setting.key == ArchiveBackupGate.SKIP_KEY) {
						note = setting.turnedOnNote;
					}
				}
			}
			System.Assert.isTrue(note != null && note.contains(adminName), 'The console row says who: ' + note);
		}
	}
}
