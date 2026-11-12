/**
 * The soft credit and tribute an imported gift can carry (R-GI5, R-GI6), and what an undo of
 * a gift import keeps (R-GI9). Run as Maria, who holds the admin permission sets.
 */
@IsTest(testFor='ApexClass:GiftImportCredits')
private class GiftImportCreditsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static Import_Template__c template;
	private static Import_Batch__c batch;

	private static User maria() {
		return TestDataFactory.createUser(
			'Maria',
			new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
		);
	}

	/** One row: Ana gives 100 on 15 March, Ben is on the row too, with these extra columns. */
	private static void given(Map<String, String> extra) {
		TestDataFactory.defaultSettings();
		GivingTestDataFactory.insertDefaultFund();
		ImportMapping mapping = new ImportMapping();
		Map<String, String> row = new Map<String, String>{
			'Contact1.Email' => 'ana@example.org',
			'Contact1.LastName' => 'Ramirez',
			'Contact2.Email' => 'ben@example.org',
			'Contact2.LastName' => 'Ramirez',
			'Gift.Amount__c' => '100',
			'Gift.Gift_Date__c' => '2026-03-15',
			'Gift.Type__c' => 'Cash'
		};
		row.putAll(extra);
		for (String target : row.keySet()) {
			mapping.getColumns().add(new ImportMapping.Column(target, target));
		}
		template = ImportTestDataFactory.template(
			mapping.serialize(),
			ImportTemplateService.RULE_EMAIL
		);
		batch = ImportTestDataFactory.batch(template);
		ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });
	}

	private static void commitAsMaria() {
		System.runAs(maria()) {
			Test.startTest();
			ImportRowProcessor.process(
				batch,
				template,
				ImportMapping.parse(template.Column_Mapping_JSON__c),
				ImportTestDataFactory.reload(batch.Id),
				false
			);
			Test.stopTest();
		}
	}

	private static Import_Row__c row() {
		return [
			SELECT
				Status__c,
				Error_Message__c,
				Gift_Id__c,
				Soft_Credit_Id__c,
				Contact_1__c,
				Contact_2__c
			FROM Import_Row__c
			WHERE Import_Batch__c = :batch.Id
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theSecondPersonIsSoftCreditedWithTheWholeGift() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(new Map<String, String>{ 'SoftCredit.Role__c' => 'solicitor' });

			commitAsMaria();

			Import_Row__c after = row();
			Assert.areEqual(
				ImportRowProcessor.STATUS_CREATED,
				after.Status__c,
				'Created: ' + after.Error_Message__c
			);
			Soft_Credit__c credit = [
				SELECT Contact__c, Role__c, Amount__c
				FROM Soft_Credit__c
				WHERE Id = :after.Soft_Credit_Id__c
			];
			Assert.areEqual(after.Contact_2__c, credit.Contact__c, 'Ben is credited.');
			Assert.areEqual('Solicitor', credit.Role__c, 'In any capitals.');
			Assert.isTrue(credit.Amount__c == 100, 'With the whole gift.');
		}
	}

	@IsTest
	static void aCreditThePackageAlreadyMadeIsNotMadeTwice() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(new Map<String, String>{ 'SoftCredit.Role__c' => 'Household Member' });

			commitAsMaria();

			Import_Row__c after = row();
			Assert.areEqual(
				ImportRowProcessor.STATUS_CREATED,
				after.Status__c,
				'Created: ' + after.Error_Message__c
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Soft_Credit__c
					WHERE Contact__c = :after.Contact_2__c AND Role__c = 'Household Member'
				],
				'One household member credit for Ben, however it was made.'
			);
		}
	}

	@IsTest
	static void aTributeComesWithTheGift() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(
				new Map<String, String>{
					'Tribute.Type__c' => 'in memory of',
					'Tribute.Honoree_Name__c' => 'Rosa Ramirez',
					'Tribute.Message__c' => 'With love'
				}
			);

			commitAsMaria();

			Import_Row__c after = row();
			Assert.areEqual(
				ImportRowProcessor.STATUS_CREATED,
				after.Status__c,
				'Created: ' + after.Error_Message__c
			);
			Tribute__c tribute = [SELECT Type__c, Honoree_Name__c, Gift__c FROM Tribute__c];
			Assert.areEqual('In memory of', tribute.Type__c, 'Its type.');
			Assert.areEqual(
				String.valueOf(tribute.Gift__c),
				after.Gift_Id__c,
				'On the row\'s gift.'
			);
		}
	}

	@IsTest
	static void aCreditOrTributeThatCannotBeIsRefusedBeforeTheGift() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(new Map<String, String>{ 'SoftCredit.Role__c' => 'Other' });

			commitAsMaria();

			Import_Row__c after = row();
			Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, after.Status__c, 'Refused.');
			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_Import_ErrorCustomRoleMissing'),
				after.Error_Message__c,
				'Why.'
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'And no gift was made for it.');
		}
	}

	private static void assertRefused(String expectedMessage, String why) {
		Import_Row__c after = row();
		Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, after.Status__c, why);
		Assert.areEqual(expectedMessage, after.Error_Message__c, why);
		Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift is made for it: ' + why);
	}

	@IsTest
	static void aCreditValueThatCannotBeReadIsRefusedWithItsText() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(
				new Map<String, String>{
					'SoftCredit.Role__c' => 'Solicitor',
					'SoftCredit.Amount__c' => 'a lot'
				}
			);

			commitAsMaria();

			assertRefused(
				String.format(
					BarnHelp.text('Giving', 'Giving_Import_ErrorValueUnreadable'),
					new List<String>{ 'a lot', Label.Giving_Import_TargetSoftCreditAmount }
				),
				'An amount that is not a number'
			);
		}
	}

	@IsTest
	static void anUnknownCreditRoleIsRefusedWithWhatIsAccepted() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(new Map<String, String>{ 'SoftCredit.Role__c' => 'Cheerleader' });
			commitAsMaria();
			Import_Row__c role = row();
			Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, role.Status__c, 'Unknown role');
			Assert.isTrue(role.Error_Message__c.contains('Cheerleader'), role.Error_Message__c);
			Assert.isTrue(role.Error_Message__c.contains('Solicitor'), 'Lists what is accepted');
		}
	}

	@IsTest
	static void anUnknownTributeTypeIsRefused() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(
				new Map<String, String>{
					'Tribute.Type__c' => 'in spite of',
					'Tribute.Honoree_Name__c' => 'Rosa Ramirez'
				}
			);
			commitAsMaria();
			Import_Row__c type = row();
			Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, type.Status__c, 'Unknown type');
			Assert.isTrue(type.Error_Message__c.contains('in spite of'), type.Error_Message__c);
		}
	}

	@IsTest
	static void aTributeNeedsItsHonoree() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(new Map<String, String>{ 'Tribute.Type__c' => 'In memory of' });

			commitAsMaria();

			assertRefused(
				BarnHelp.text('Giving', 'Giving_Import_ErrorTributeHonoreeMissing'),
				'A tribute with no honoree'
			);
		}
	}

	@IsTest
	static void theCreditedPartyCanBeTheFirstPerson() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(
				new Map<String, String>{
					'SoftCredit.Role__c' => 'Solicitor',
					'SoftCredit.Party' => ' contact 1 '
				}
			);
			commitAsMaria();
			Import_Row__c first = row();
			Assert.areEqual(
				ImportRowProcessor.STATUS_CREATED,
				first.Status__c,
				'Created: ' + first.Error_Message__c
			);
			Assert.areEqual(
				first.Contact_1__c,
				[SELECT Contact__c FROM Soft_Credit__c WHERE Id = :first.Soft_Credit_Id__c]
				.Contact__c,
				'Ana, the first person, is credited.'
			);
		}
	}

	@IsTest
	static void aCreditToSomeoneOutsideTheFourChoicesIsRefused() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(
				new Map<String, String>{
					'SoftCredit.Role__c' => 'Solicitor',
					'SoftCredit.Party' => 'Neighbour'
				}
			);
			commitAsMaria();
			assertRefused(
				String.format(
					BarnHelp.text('Giving', 'Giving_Import_ErrorSoftCreditPartyChoice'),
					new List<String>{ 'Neighbour' }
				),
				'A choice that is not one of four'
			);
		}
	}

	@IsTest
	static void aCreditToAnOrganizationOrHouseholdTheRowDoesNotHaveIsRefused() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(
				new Map<String, String>{
					'SoftCredit.Role__c' => 'Solicitor',
					'SoftCredit.Party' => 'Organization'
				}
			);

			commitAsMaria();

			assertRefused(
				BarnHelp.text('Giving', 'Giving_Import_ErrorSoftCreditPartyMissing'),
				'The row has no organization'
			);
		}
	}

	@IsTest
	static void aCreditOrTributeThePlatformRefusesFailsItsRowWholly() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(
				new Map<String, String>{
					'Tribute.Type__c' => 'In memory of',
					'Tribute.Honoree_Name__c' => 'R'.repeat(300)
				}
			);

			commitAsMaria();

			Import_Row__c after = row();
			Assert.areNotEqual(
				ImportRowProcessor.STATUS_CREATED,
				after.Status__c,
				'Not created: ' + after.Error_Message__c
			);
			Assert.isTrue(
				after.Error_Message__c.startsWith(
					BarnHelp.text('Giving', 'Giving_Import_ErrorFailed').substringBefore('{0}')
				),
				'Says the gift could not be saved: ' + after.Error_Message__c
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'R-GI7: saved whole or not at all');
			Assert.areEqual(0, [SELECT COUNT() FROM Tribute__c], 'No tribute left behind');
		}
	}

	@IsTest
	static void anUndoKeepsAReceiptedGiftAndItsDonor() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(new Map<String, String>());
			commitAsMaria();
			Import_Row__c after = row();
			Gift__c gift = [SELECT Id, Donor_Contact__c FROM Gift__c WHERE Id = :after.Gift_Id__c];
			insert new Receipt__c(
				Receipt_Number__c = 'R-TEST-1',
				Type__c = 'Per gift',
				Statement_Year__c = 2026,
				Status__c = 'Void',
				Void_Reason__c = 'Issued to the wrong address.',
				Voided_On__c = Datetime.now(),
				Gift__c = gift.Id,
				Donor_Contact__c = gift.Donor_Contact__c,
				Issue_Date__c = Date.today()
			);
			GiftImportProcessor processor = new GiftImportProcessor();

			Map<Id, String> gifts = processor.reasonsToKeep(
				batch.Id,
				Gift__c.SObjectType,
				new Set<Id>{ gift.Id }
			);
			Map<Id, String> people = processor.reasonsToKeep(
				batch.Id,
				Contact.SObjectType,
				new Set<Id>{ gift.Donor_Contact__c, after.Contact_2__c }
			);

			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_Import_UndoKeptReceipted'),
				gifts.get(gift.Id),
				'Even void.'
			);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_Import_UndoKeptDonor'),
				people.get(gift.Donor_Contact__c),
				'Ana.'
			);
			Assert.isTrue(
				processor.taggedObjects().contains(Gift__c.SObjectType),
				'Gifts are what the import tags.'
			);
		}
	}

	@IsTest
	static void anUndoKeepsAGiftAnIssuedStatementLists() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			given(new Map<String, String>());
			commitAsMaria();
			Gift__c gift = [SELECT Id, Donor_Contact__c FROM Gift__c];
			insert new Receipt__c(
				Receipt_Number__c = 'S-TEST-1',
				Type__c = 'Consolidated statement',
				Status__c = 'Issued',
				Statement_Year__c = 2026,
				Donor_Contact__c = gift.Donor_Contact__c,
				Issue_Date__c = Date.today()
			);

			Map<Id, String> keep = new GiftImportProcessor()
				.reasonsToKeep(batch.Id, Gift__c.SObjectType, new Set<Id>{ gift.Id });

			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_Import_UndoKeptStatement'),
				keep.get(gift.Id),
				'The 2026 statement.'
			);
		}
	}
}
