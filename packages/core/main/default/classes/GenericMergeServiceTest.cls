/**
 * Generic Record Merge (C-62, R-DP11, R-DP12): only offered objects, the merge rules' choice
 * in the comparison, related records moved, the other record in the Recycle Bin, a journal
 * row, and undo putting it all back. Import mappings stand in for any BarnCRM object: Core
 * ships them, admins may edit, delete and restore them, and import jobs link to them.
 */
@IsTest(testFor='ApexClass:GenericMergeService, ApexClass:GenericMergeController')
private class GenericMergeServiceTest {
	private static final String MAPPING = 'Import_Template__c';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void turnOn(Boolean enabled) {
		BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
		settings.Generic_Merge_Enabled__c = enabled;
		settings.Merge_Default_Rule__c = MergeRuleService.NOT_BLANK;
		HouseholdTestDataFactory.save(settings);
	}

	private static Import_Template__c mapping(String name, String description) {
		Import_Template__c template = ImportTestDataFactory.template(
			ImportTestDataFactory.donorMapping(),
			ImportTemplateService.RULE_EMAIL
		);
		template.Name = name;
		template.Description__c = description;
		update template;
		return template;
	}

	private static Boolean isDeleted(Id recordId) {
		return [
			SELECT IsDeleted
			FROM Import_Template__c
			WHERE Id = :recordId
			WITH SYSTEM_MODE
			ALL ROWS
		]
		.IsDeleted;
	}

	@IsTest
	static void offersBarnObjectsButNotLogsOrPeople() {
		System.runAs(TestUsers.admin()) {
			turnOn(true);
			Test.startTest();
			Map<String, String> offered = GenericMergeService.objects();
			Test.stopTest();

			Assert.isNotNull(
				GenericMergeService.offeredType(MAPPING),
				'An import mapping is a BarnCRM object an admin may merge'
			);
			Assert.isTrue(
				offered.containsKey(String.valueOf(Import_Template__c.SObjectType)),
				'The list offers it'
			);
			Assert.isNull(
				GenericMergeService.offeredType('Merge_Journal__c'),
				'The merge journal is BarnCRM bookkeeping, never merged'
			);
			Assert.isNull(
				GenericMergeService.offeredType('Contact'),
				'People keep their own merge'
			);
		}
	}

	@IsTest
	static void refusesWhileOffAndForAPairOfOneRecord() {
		System.runAs(TestUsers.admin()) {
			turnOn(false);
			Import_Template__c first = mapping('Gifts 2025', null);
			Import_Template__c second = mapping('Gifts 2025 copy', null);
			Test.startTest();
			try {
				GenericMergeService.compare(MAPPING, first.Id, second.Id);
				Assert.fail('Merge Records is off');
			} catch (DuplicateService.DuplicateException expected) {
				Assert.isTrue(expected.getMessage().contains('off'), expected.getMessage());
			}
			turnOn(true);
			try {
				GenericMergeService.compare(MAPPING, first.Id, first.Id);
				Assert.fail('A record cannot be merged with itself');
			} catch (DuplicateService.DuplicateException expected) {
				Assert.isTrue(
					expected.getMessage().contains('two different'),
					expected.getMessage()
				);
			}
			Test.stopTest();
		}
	}

	@IsTest
	static void comparisonStartsFromTheMergeRules() {
		System.runAs(TestUsers.admin()) {
			turnOn(true);
			Import_Template__c first = mapping('Gifts 2025', null);
			Import_Template__c second = mapping('Gifts 2025 copy', 'Year-end gifts');
			Test.startTest();
			GenericMergeService.Comparison compared = GenericMergeService.compare(
				MAPPING,
				first.Id,
				second.Id
			);
			Test.stopTest();

			Assert.areEqual('Gifts 2025', compared.firstName, 'The first record by name');
			GenericMergeService.FieldRow description;
			for (GenericMergeService.FieldRow row : compared.fields) {
				Assert.areNotEqual(
					'template_key__c',
					MergeRuleService.bare(row.name).toLowerCase(),
					'A unique field is never offered: the kept record keeps its own'
				);
				if (MergeRuleService.bare(row.name).equalsIgnoreCase('Description__c')) {
					description = row;
				}
			}
			Assert.isNotNull(description, 'Description is compared');
			Assert.isTrue(description.differs, 'Blank against a value differs');
			Assert.isTrue(
				description.takeSecond,
				'Under Not blank the other value fills the kept record\'s blank'
			);
		}
	}

	@IsTest
	static void mergeMovesRelatedRecordsJournalsAndUndoes() {
		System.runAs(TestUsers.admin()) {
			turnOn(true);
			Import_Template__c keep = mapping('Gifts 2025', null);
			Import_Template__c other = mapping('Gifts 2025 copy', 'Year-end gifts');
			Import_Batch__c job = ImportTestDataFactory.batch(other);
			String description = Import_Template__c.Description__c.getDescribe().getName();

			Test.startTest();
			GenericMergeService.Outcome outcome = GenericMergeService.mergeRecords(
				MAPPING,
				keep.Id,
				other.Id,
				new List<String>{ description }
			);
			Assert.areEqual(1, outcome.moved, 'The import job moved');
			Assert.areEqual(1, outcome.changed, 'One value changed');
			Assert.isTrue(isDeleted(other.Id), 'The other mapping is in the Recycle Bin');
			Assert.areEqual(
				keep.Id,
				[SELECT Import_Template__c FROM Import_Batch__c WHERE Id = :job.Id WITH SYSTEM_MODE]
				.Import_Template__c,
				'The job now points at the kept mapping'
			);
			Assert.areEqual(
				'Year-end gifts',
				[SELECT Description__c FROM Import_Template__c WHERE Id = :keep.Id WITH SYSTEM_MODE]
				.Description__c,
				'The kept mapping took the chosen value'
			);
			Merge_Journal__c journal = [
				SELECT
					Id,
					Survivor_Id__c,
					Merged_Id__c,
					Merged_Name__c,
					Status__c,
					Changed_Values__c,
					Moved_Records__c,
					Notes__c
				FROM Merge_Journal__c
				WHERE Merged_Id__c = :other.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(AutoMergeService.MERGED, journal.Status__c, 'Journaled as Merged');
			Assert.areEqual('Gifts 2025 copy', journal.Merged_Name__c, 'Named while deleted');

			AutoMergeService.undo(new List<Merge_Journal__c>{ journal });
			Test.stopTest();

			Assert.isFalse(isDeleted(other.Id), 'Undo brings the real record back');
			Assert.areEqual(
				other.Id,
				[SELECT Import_Template__c FROM Import_Batch__c WHERE Id = :job.Id WITH SYSTEM_MODE]
				.Import_Template__c,
				'The job is back on the restored mapping'
			);
			Assert.isNull(
				[SELECT Description__c FROM Import_Template__c WHERE Id = :keep.Id WITH SYSTEM_MODE]
				.Description__c,
				'The kept mapping has its own value back'
			);
			Assert.areEqual(
				AutoMergeService.UNDONE,
				[SELECT Status__c FROM Merge_Journal__c WHERE Id = :journal.Id WITH SYSTEM_MODE]
				.Status__c,
				'Undone in full'
			);
		}
	}

	private static Id fileOn(Id recordId, String title) {
		ContentVersion version = new ContentVersion(
			Title = title,
			PathOnClient = title + '.txt',
			VersionData = Blob.valueOf(title)
		);
		insert version;
		Id documentId = [
			SELECT ContentDocumentId
			FROM ContentVersion
			WHERE Id = :version.Id
			WITH SYSTEM_MODE
		]
		.ContentDocumentId;
		insert new ContentDocumentLink(
			LinkedEntityId = recordId,
			ContentDocumentId = documentId,
			ShareType = 'V'
		);
		return documentId;
	}

	private static Set<Id> filesOn(Id recordId) {
		Set<Id> documents = new Set<Id>();
		for (ContentDocumentLink row : [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :recordId
			WITH SYSTEM_MODE
		]) {
			documents.add(row.ContentDocumentId);
		}
		return documents;
	}

	@IsTest
	static void mergeLinksTheOtherRecordsFilesAndUndoRemovesThem() {
		System.runAs(TestUsers.admin()) {
			turnOn(true);
			Import_Template__c keep = mapping('Gifts 2025', null);
			Import_Template__c other = mapping('Gifts 2025 copy', null);
			Id onlyOther = fileOn(other.Id, 'Only other');
			Id shared = fileOn(other.Id, 'Shared');
			insert new ContentDocumentLink(
				LinkedEntityId = keep.Id,
				ContentDocumentId = shared,
				ShareType = 'V'
			);
			Test.startTest();
			GenericMergeService.Outcome outcome = GenericMergeService.mergeRecords(
				MAPPING,
				keep.Id,
				other.Id,
				new List<String>()
			);
			Assert.areEqual(1, outcome.moved, 'One file linked; the shared one was already there');
			Assert.isTrue(filesOn(keep.Id).contains(onlyOther), 'The kept record has the file');
			Assert.isTrue(filesOn(keep.Id).contains(shared), 'The shared file is still there');
			Merge_Journal__c journal = [
				SELECT Id, Survivor_Id__c, Merged_Id__c, Merged_Name__c, Moved_Records__c, Notes__c
				FROM Merge_Journal__c
				WHERE Merged_Id__c = :other.Id
				WITH SYSTEM_MODE
			];
			Assert.isTrue(
				journal.Moved_Records__c.contains(AutoMergeService.ADDED_FILES),
				'The journal keeps the new file links'
			);
			AutoMergeService.undo(new List<Merge_Journal__c>{ journal });
			Test.stopTest();

			Set<Id> after = filesOn(keep.Id);
			Assert.isFalse(after.contains(onlyOther), 'Undo takes the added link away');
			Assert.isTrue(after.contains(shared), 'A link the merge did not add stays');
			Assert.areEqual(
				AutoMergeService.UNDONE,
				[SELECT Status__c FROM Merge_Journal__c WHERE Id = :journal.Id WITH SYSTEM_MODE]
				.Status__c,
				'Undone in full'
			);
		}
	}

	@IsTest
	static void relatedRecordsOfSeveralObjectsMoveOnePerObject() {
		System.runAs(TestUsers.admin()) {
			Import_Template__c template = mapping('Gifts 2025', null);
			Import_Batch__c earlier = ImportTestDataFactory.batch(template);
			Import_Batch__c to = ImportTestDataFactory.batch(template);
			Account org = new Account(Name = 'Moves', Created_By_Import_Batch__c = earlier.Id);
			insert org;
			Contact person = new Contact(
				LastName = 'Moves',
				Created_By_Import_Batch__c = earlier.Id
			);
			insert person;
			Test.startTest();
			Integer count = GenericMergeService.moveRelated(
				new Map<String, List<Id>>{
					'Account.Created_By_Import_Batch__c' => new List<Id>{ org.Id },
					'Contact.Created_By_Import_Batch__c' => new List<Id>{ person.Id, to.Id }
				},
				to.Id
			);
			Test.stopTest();

			Assert.areEqual(2, count, 'The kept record linked to the other is left');
			Assert.areEqual(
				to.Id,
				[SELECT Created_By_Import_Batch__c FROM Account WHERE Id = :org.Id WITH SYSTEM_MODE]
				.Created_By_Import_Batch__c,
				'The account moved'
			);
			Assert.areEqual(
				to.Id,
				[
					SELECT Created_By_Import_Batch__c
					FROM Contact
					WHERE Id = :person.Id
					WITH SYSTEM_MODE
				]
				.Created_By_Import_Batch__c,
				'The contact moved'
			);
		}
	}

	@IsTest
	static void refusesAFieldOutsideTheChoice() {
		System.runAs(TestUsers.admin()) {
			turnOn(true);
			Import_Template__c keep = mapping('Gifts 2025', null);
			Import_Template__c other = mapping('Gifts 2025 copy', null);
			Test.startTest();
			try {
				GenericMergeService.mergeRecords(
					MAPPING,
					keep.Id,
					other.Id,
					new List<String>{ 'OwnerId' }
				);
				Assert.fail('The owner is never taken from the other record');
			} catch (DuplicateService.DuplicateException expected) {
				Assert.isTrue(expected.getMessage().contains('OwnerId'), expected.getMessage());
			}
			Test.stopTest();
			Assert.isFalse(isDeleted(other.Id), 'Nothing was merged');
		}
	}

	@IsTest
	static void refusesWhenADetailRecordWouldBeDeleted() {
		System.runAs(TestUsers.admin()) {
			Import_Batch__c job = ImportTestDataFactory.batch(mapping('Gifts 2025', null));
			insert new Import_Row__c(
				Import_Batch__c = job.Id,
				Row_Number__c = 2,
				Raw_Values_JSON__c = '{}'
			);
			Test.startTest();
			try {
				GenericMergeService.refuseLostRecords(Import_Batch__c.SObjectType, job.Id);
				Assert.fail('An import row cannot move to another job, so it would be lost');
			} catch (DuplicateService.DuplicateException expected) {
				Assert.isTrue(
					expected.getMessage()
						.contains(
							Import_Row__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
								.getLabelPlural()
						),
					expected.getMessage()
				);
			}
			Test.stopTest();
		}
	}
}
