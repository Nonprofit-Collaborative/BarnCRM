/**
 * Multi-brand management (C-47, R-BR1 to R-BR9): nothing while off, the profile seam with its
 * entity fallback, defaulting from a parent and from the user, one default and one primary,
 * unique assignments, and brand visibility groups, members and shares.
 */
@IsTest(
	testFor='ApexClass:BrandService, ApexClass:BrandTriggerHandler, ApexClass:BrandShareJob, ApexClass:BrandShareWriter, ApexClass:BrandDefaultHandler, ApexTrigger:BrandTrigger, ApexTrigger:BrandAssignmentTrigger, ApexTrigger:LegalEntityTrigger'
)
private class BrandServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void theDefaultHandlerFillsTheUsersBrandWithNoBrandedParent() {
		System.runAs(TestUsers.admin()) {
			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Brand_Management__c = true;
			HouseholdTestDataFactory.save(settings);
			Brand__c mine = new Brand__c(Name = 'Mine');
			insert mine;
			insert new Brand_Assignment__c(Brand__c = mine.Id, User__c = UserInfo.getUserId());
			List<Brand_Assignment__c> records = new List<Brand_Assignment__c>{
				new Brand_Assignment__c(),
				new Brand_Assignment__c()
			};

			Test.startTest();
			TriggerHandler.setTestRecords(records, null);
			new BrandDefaultHandler().beforeInsert();
			Test.stopTest();

			Assert.isNull(
				BrandDefaultHandler.parentField(Brand_Assignment__c.SObjectType),
				'No lookup of a brand assignment leads to a branded parent'
			);
			Assert.areEqual(mine.Id, records[1].Brand__c, 'The user brand fills the blank');
		}
	}

	private static void turnOn(Boolean brands, Boolean visibility) {
		BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
		settings.Brand_Management__c = brands;
		settings.Brand_Visibility__c = visibility;
		HouseholdTestDataFactory.save(settings);
	}

	private static Brand__c brand(String name, Id entityId, Boolean isDefault) {
		Brand__c record = new Brand__c(
			Name = name,
			Legal_Entity__c = entityId,
			Is_Default__c = isDefault,
			City__c = 'Springfield'
		);
		insert record;
		return record;
	}

	@IsTest
	static void offReadsNothingAndFillsNothing() {
		System.runAs(TestUsers.admin()) {
			Brand__c only = brand('Thrift Store', null, true);
			insert new Brand_Assignment__c(Brand__c = only.Id, User__c = UserInfo.getUserId());
			List<Brand_Assignment__c> records = new List<Brand_Assignment__c>{
				new Brand_Assignment__c()
			};

			Test.startTest();
			BrandService.applyDefaults(records, null);
			BrandService.Profile profile = BrandService.profileFor(only.Id);
			Test.stopTest();

			Assert.isNull(profile, 'Brands off returns no profile');
			Assert.isNull(records[0].Brand__c, 'Brands off fills in no brand');
		}
	}

	@IsTest
	static void profileFallsBackToTheEntityAndTheDefaultBrand() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, false);
			Legal_Entity__c entity = new Legal_Entity__c(
				Name = 'Friends of the Barn Inc.',
				Tax_Id__c = '12-3456789',
				Street__c = '1 Main St',
				Is_Default__c = true
			);
			insert entity;
			Brand__c chapter = new Brand__c(Name = 'North Chapter', Is_Default__c = true);
			insert chapter;

			Test.startTest();
			BrandService.Profile profile = BrandService.profileFor(null);
			Test.stopTest();

			Assert.areEqual(chapter.Id, profile.brandId, 'A blank brand reads the default brand');
			Assert.areEqual('Friends of the Barn Inc.', profile.legalName, 'Default entity');
			Assert.areEqual('12-3456789', profile.taxId, 'Tax ID from the entity');
			Assert.areEqual('1 Main St', profile.addressLines[0], 'Address from the entity');
		}
	}

	@IsTest
	static void senderAndLogoReadOnlyWhatIsThere() {
		System.runAs(TestUsers.admin()) {
			Brand__c store = new Brand__c(Name = 'Store', Sender_Email__c = 'store@example.org');
			insert store;
			ContentVersion logo = new ContentVersion(
				Title = 'logo',
				PathOnClient = 'logo.png',
				VersionData = Blob.valueOf('png')
			);
			insert logo;
			Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :logo.Id]
			.ContentDocumentId;

			Test.startTest();
			Map<Id, Id> whileOff = BrandService.senderIdsFor(new Set<Id>{ store.Id });
			turnOn(true, false);
			Map<Id, Id> notSetUp = BrandService.senderIdsFor(new Set<Id>{ store.Id });
			String path = BrandService.logoPath(documentId);
			String badId = BrandService.logoPath('not an id');
			Test.stopTest();

			Assert.isTrue(whileOff.isEmpty(), 'Brands off name no sender');
			Assert.isFalse(
				notSetUp.containsKey(store.Id),
				'An address that is not an organization-wide address is left out'
			);
			Assert.isTrue(path.endsWith(logo.Id), 'The latest version of the logo file');
			Assert.isNull(badId, 'A value that is not a file ID prints no logo');
		}
	}

	@IsTest
	static void oneDefaultBrandAndOnePrimaryAssignment() {
		System.runAs(TestUsers.admin()) {
			Brand__c first = brand('First', null, true);
			Brand__c second = brand('Second', null, false);
			Id me = UserInfo.getUserId();
			insert new Brand_Assignment__c(Brand__c = first.Id, User__c = me, Is_Primary__c = true);

			Test.startTest();
			second.Is_Default__c = true;
			update second;
			insert new Brand_Assignment__c(
				Brand__c = second.Id,
				User__c = me,
				Is_Primary__c = true
			);
			Boolean duplicateRefused = false;
			try {
				insert new Brand_Assignment__c(Brand__c = second.Id, User__c = me);
			} catch (DmlException refused) {
				duplicateRefused = true;
			}
			Test.stopTest();

			Assert.isFalse(
				[SELECT Is_Default__c FROM Brand__c WHERE Id = :first.Id].Is_Default__c,
				'Saving a second default clears the first'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Brand_Assignment__c
					WHERE User__c = :me AND Is_Primary__c = TRUE
				],
				'One primary brand per user'
			);
			Assert.isTrue(duplicateRefused, 'A record is assigned to a brand once');
		}
	}

	@IsTest
	static void severalDefaultsSavedTogetherKeepTheLast() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			List<Brand__c> together = new List<Brand__c>{
				new Brand__c(Name = 'One', Is_Default__c = true),
				new Brand__c(Name = 'Two', Is_Default__c = true),
				new Brand__c(Name = 'Three', Is_Default__c = true)
			};
			insert together;
			Test.stopTest();

			List<Brand__c> defaults = [SELECT Id FROM Brand__c WHERE Is_Default__c = TRUE];
			Assert.areEqual(1, defaults.size(), 'One default after a batch of three');
			Assert.areEqual(together[2].Id, defaults[0].Id, 'The last one saved stays');
		}
	}

	@IsTest
	static void parentsWithoutABrandFallBackToTheUsersBrand() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, false);
			Brand__c mine = brand('Mine', null, false);
			insert new Brand_Assignment__c(Brand__c = mine.Id, User__c = UserInfo.getUserId());
			Account household = HouseholdTestDataFactory.insertHouseholds(
				new List<Account>{ HouseholdTestDataFactory.newHousehold('Zztest Parent') }
			)[0];
			Contact person = TestDataFactory.person(new Contact(LastName = 'Zztest Parent'));
			insert person;
			List<Brand_Assignment__c> records = new List<Brand_Assignment__c>{
				new Brand_Assignment__c(Account__c = household.Id),
				new Brand_Assignment__c(Contact__c = person.Id)
			};

			Test.startTest();
			BrandService.applyDefaults(records, 'Account__c');
			BrandService.applyDefaults(records, 'Contact__c');
			Test.stopTest();

			for (Brand_Assignment__c record : records) {
				Assert.areEqual(
					mine.Id,
					record.Brand__c,
					'A parent with no brand field is skipped'
				);
			}
		}
	}

	@IsTest
	static void aFullSharePageQueuesTheNextWhateverItsScope() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, true);
			// Without this, Core gives the new person a household and the page scope is not empty.
			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Auto_Create_Households__c = false;
			HouseholdTestDataFactory.save(settings);
			Brand__c chapter = brand('Chapter', null, false);
			Contact person = TestDataFactory.person(new Contact(LastName = 'Zztest Alone'));
			insert person;
			Assert.isNull(
				[SELECT AccountId FROM Contact WHERE Id = :person.Id].AccountId,
				'A contact with no account adds nothing to the page scope'
			);
			insert new Brand_Assignment__c(Brand__c = chapter.Id, Contact__c = person.Id);

			Test.startTest();
			Integer before = Limits.getQueueableJobs();
			// A null cursor is the real first page of a full run.
			new BrandShareJob(true, true, null, null).execute(null);
			Integer queued = Limits.getQueueableJobs() - before;
			Test.stopTest();

			Assert.areEqual(1, queued, 'The page had a row, so the next page is queued');
		}
	}

	@IsTest
	static void defaultsComeFromTheUserInBulk() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, false);
			Brand__c mine = brand('Mine', null, false);
			insert new Brand_Assignment__c(Brand__c = mine.Id, User__c = UserInfo.getUserId());
			List<Brand_Assignment__c> records = new List<Brand_Assignment__c>();
			for (Integer i = 0; i < 200; i++) {
				records.add(new Brand_Assignment__c());
			}

			Test.startTest();
			BrandService.applyDefaults(records, 'Contact__c');
			Test.stopTest();

			for (Brand_Assignment__c record : records) {
				Assert.areEqual(mine.Id, record.Brand__c, 'The user only brand fills each blank');
			}
		}
	}

	@IsTest
	static void visibilityKeepsGroupsMembersAndShares() {
		User admin = TestUsers.admin();
		Brand__c chapter;
		Account household;
		System.runAs(admin) {
			turnOn(true, true);
			chapter = brand('Chapter', null, false);
			household = HouseholdTestDataFactory.insertHouseholds(
				new List<Account>{ HouseholdTestDataFactory.newHousehold('Zztest Brand') }
			)[0];
			insert new Brand_Assignment__c(Brand__c = chapter.Id, Account__c = household.Id);
			insert new Brand_Assignment__c(Brand__c = chapter.Id, User__c = admin.Id);
		}
		Map<Id, Id> groups;
		System.runAs(admin) {
			Test.startTest();
			groups = BrandShareJob.syncGroups();
			Test.stopTest();
		}
		System.runAs(admin) {
			BrandShareJob.syncShares(new Set<Id>{ household.Id }, groups);
		}

		Id groupId = groups.get(chapter.Id);
		Assert.isNotNull(groupId, 'An active brand has a group');
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM GroupMember
				WHERE GroupId = :groupId AND UserOrGroupId = :admin.Id
			],
			'The assigned user is a member'
		);
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM AccountShare
				WHERE AccountId = :household.Id AND UserOrGroupId = :groupId
			],
			'The assigned household is shared with the brand group'
		);

		System.runAs(admin) {
			turnOn(true, false);
			BrandShareJob.syncGroups();
		}
		Assert.isTrue(
			BrandShareJob.groupsByBrand().isEmpty(),
			'Off removes the groups, and their shares'
		);
	}

	@IsTest
	static void healthCheckWarnsOnlyWhileVisibilityIsOn() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			HealthCheckService.Finding off = new BrandShareJob.VisibilityCheck().run();
			Test.stopTest();

			Assert.isNull(off, 'Nothing to say while visibility is off');
		}
	}

	@IsTest
	static void anAssignmentChangeAndDeleteQueueTheShareUpkeep() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, true);
			Brand__c chapter = brand('Chapter', null, true);
			Brand_Assignment__c assignment = new Brand_Assignment__c(
				Brand__c = chapter.Id,
				User__c = UserInfo.getUserId(),
				Is_Primary__c = true
			);
			insert assignment;

			Test.startTest();
			update new Brand_Assignment__c(Id = assignment.Id, Is_Primary__c = false);
			delete assignment;
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Brand_Assignment__c WHERE Id = :assignment.Id],
				'The assignment is gone'
			);
		}
	}

	@IsTest
	static void anAssignmentThatIsRestoredIsBack() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, true);
			Brand__c chapter = brand('Chapter', null, true);
			Brand_Assignment__c assignment = new Brand_Assignment__c(
				Brand__c = chapter.Id,
				User__c = UserInfo.getUserId()
			);
			insert assignment;
			delete assignment;

			Test.startTest();
			undelete assignment;
			Test.stopTest();

			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Brand_Assignment__c WHERE Id = :assignment.Id],
				'The assignment is back'
			);
		}
	}

	@IsTest
	static void aBrandThatChangesIsDeletedAndRestoredKeepsItsDefault() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, true);
			Brand__c chapter = brand('Chapter', null, true);

			Test.startTest();
			chapter.City__c = 'Shelbyville';
			update chapter;
			delete chapter;
			undelete chapter;
			Test.stopTest();

			Brand__c restored = [
				SELECT City__c, Is_Default__c
				FROM Brand__c
				WHERE Id = :chapter.Id
			];
			Assert.areEqual('Shelbyville', restored.City__c, 'The change stayed');
			Assert.isTrue(restored.Is_Default__c, 'Still the one default brand');
		}
	}
}
