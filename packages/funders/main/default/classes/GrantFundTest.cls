/**
 * Restricted funds (F-03, R-FE1, R-FE2, R-GN8, R-GP3): the ledger totals and a balance below zero;
 * a received payment of a restricted grant writes its Received entry and the entry follows it,
 * also for staff, who cannot set the entry's Payment themselves; entries typed by hand are left
 * alone; the Giving Fund is a fund's record identifier, and the card works with or without Giving.
 */
@IsTest(
	testFor='ApexClass:GrantFundService, ApexClass:GrantFundController, ApexClass:GrantPaymentService'
)
private class GrantFundTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWithInstalledModules();
		TestUsers.standardUserWith(
			'Gfundstaff',
			new List<String>{ 'BarnCRM_Read_Only', 'Funders_Staff' }
		);
		TestUsers.standardUserWith(
			'Gfundreader',
			new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
		);
		TestUsers.standardUser('Gfundnoaccess');
	}

	private static Grant__c restrictedAward() {
		Account funder = GrantTestData.funder('Lakeside Foundation');
		Grant__c grant = GrantTestData.grant('Literacy', funder.Id, GrantService.STAGE_AWARDED);
		grant.Amount_Awarded__c = 20000;
		grant.Restricted__c = true;
		insert grant;
		return grant;
	}

	private static Grant_Payment__c payment(Id grantId, Decimal amount, String status) {
		return new Grant_Payment__c(
			Grant__c = grantId,
			Due_Date__c = Date.newInstance(2027, 1, 1),
			Amount__c = amount,
			Status__c = status
		);
	}

	private static Grant__c totals(Id grantId) {
		return [
			SELECT
				Restricted_Received__c,
				Restricted_Spent__c,
				Restricted_Released__c,
				Restricted_Balance__c
			FROM Grant__c
			WHERE Id = :grantId
			WITH SYSTEM_MODE
		];
	}

	private static List<Grant_Fund_Entry__c> entries(Id grantId) {
		return [
			SELECT Type__c, Amount__c, Entry_Date__c, Grant_Payment__c
			FROM Grant_Fund_Entry__c
			WHERE Grant__c = :grantId
			WITH SYSTEM_MODE
			ORDER BY Amount__c
		];
	}

	@IsTest
	static void theTotalsAndBalanceFollowTheEntries() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = restrictedAward();

			Test.startTest();
			insert new List<Grant_Fund_Entry__c>{
				new Grant_Fund_Entry__c(
					Grant__c = grant.Id,
					Type__c = 'Received',
					Amount__c = 1000
				),
				new Grant_Fund_Entry__c(Grant__c = grant.Id, Type__c = 'Spent', Amount__c = 1500),
				new Grant_Fund_Entry__c(Grant__c = grant.Id, Type__c = 'Released', Amount__c = 200)
			};
			String refusal;
			try {
				insert new Grant_Fund_Entry__c(Grant__c = grant.Id, Amount__c = 0);
			} catch (DmlException e) {
				refusal = e.getDmlType(0).name();
			}
			Test.stopTest();

			Grant__c saved = totals(grant.Id);
			Assert.areEqual(1000, saved.Restricted_Received__c, 'Received is summed');
			Assert.areEqual(1500, saved.Restricted_Spent__c, 'Spent is summed');
			Assert.areEqual(200, saved.Restricted_Released__c, 'Released is summed');
			Assert.areEqual(-700, saved.Restricted_Balance__c, 'A balance below zero is shown');
			Assert.areEqual('FIELD_CUSTOM_VALIDATION_EXCEPTION', refusal, 'R-FE1: above zero');
			Assert.areEqual(
				Date.today(),
				entries(grant.Id)[0].Entry_Date__c,
				'The entry date defaults to today'
			);
		}
	}

	@IsTest
	static void aReceivedPaymentWritesItsEntryAndTheEntryFollowsIt() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = restrictedAward();
			Grant_Fund_Entry__c typed = new Grant_Fund_Entry__c(
				Grant__c = grant.Id,
				Type__c = 'Received',
				Amount__c = 50
			);
			insert typed;
			Grant_Payment__c first = payment(grant.Id, 5000, GrantPaymentService.STATUS_EXPECTED);
			Grant_Payment__c second = payment(grant.Id, 7000, GrantPaymentService.STATUS_RECEIVED);
			second.Received_Date__c = Date.newInstance(2027, 2, 1);

			Test.startTest();
			insert new List<Grant_Payment__c>{ first, second };
			Integer afterInsert = entries(grant.Id).size();
			GrantPaymentService.markReceived(first.Id);
			update new Grant_Payment__c(
				Id = second.Id,
				Amount__c = 8000,
				Received_Date__c = Date.newInstance(2027, 3, 1)
			);
			List<Grant_Fund_Entry__c> followed = entries(grant.Id);
			update new Grant_Payment__c(
				Id = first.Id,
				Status__c = GrantPaymentService.STATUS_CANCELLED
			);
			delete second;
			Test.stopTest();

			Assert.areEqual(2, afterInsert, 'The hand-typed entry and the received payment');
			Assert.areEqual(3, followed.size(), 'Marking received adds an entry');
			Assert.areEqual(first.Id, followed[1].Grant_Payment__c, 'Linked to its payment');
			Assert.areEqual(Date.today(), followed[1].Entry_Date__c, 'Dated when received');
			Assert.areEqual(8000, followed[2].Amount__c, 'A changed amount is followed');
			Assert.areEqual(Date.newInstance(2027, 3, 1), followed[2].Entry_Date__c, 'And date');
			List<Grant_Fund_Entry__c> left = entries(grant.Id);
			Assert.areEqual(1, left.size(), 'Cancelled and deleted payments lose their entries');
			Assert.areEqual(typed.Id, left[0].Id, 'The hand-typed entry is never touched');
			Assert.areEqual(50, totals(grant.Id).Restricted_Received__c, 'Totals follow too');
		}
	}

	@IsTest
	static void aGrantThatIsNotRestrictedGetsNoEntries() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = restrictedAward();
			update new Grant__c(Id = grant.Id, Restricted__c = false);

			Test.startTest();
			insert payment(grant.Id, 5000, GrantPaymentService.STATUS_RECEIVED);
			Test.stopTest();

			Assert.isTrue(entries(grant.Id).isEmpty(), 'Only a restricted grant has a ledger');
		}
	}

	@IsTest
	static void staffMarkingAPaymentReceivedGetsTheEntry() {
		Grant__c grant;
		Grant_Payment__c expected;
		System.runAs(TestUsers.adminWithInstalledModules()) {
			grant = restrictedAward();
			expected = payment(grant.Id, 3000, GrantPaymentService.STATUS_EXPECTED);
			insert expected;
		}
		User staff = [SELECT Id FROM User WHERE LastName = 'Gfundstaff' WITH SYSTEM_MODE LIMIT 1];
		Boolean canSetPayment;

		Test.startTest();
		System.runAs(staff) {
			canSetPayment = Schema.SObjectType.Grant_Fund_Entry__c.fields.Grant_Payment__c.isUpdateable();
			GrantPaymentService.markReceived(expected.Id);
		}
		Test.stopTest();

		Assert.isFalse(canSetPayment, 'Staff cannot set the Payment themselves');
		List<Grant_Fund_Entry__c> written = entries(grant.Id);
		Assert.areEqual(1, written.size(), 'BarnCRM writes the entry for them');
		Assert.areEqual(expected.Id, written[0].Grant_Payment__c, 'Linked to the payment');
	}

	@IsTest
	static void theFundIsAFundsRecordIdentifier() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = restrictedAward();
			Schema.SObjectType fundType = NamespaceUtil.packagedObjectType('Fund__c');

			Test.startTest();
			GrantFundController.FundCard card = GrantFundController.getFund(grant.Id);
			String refusedText;
			try {
				update new Grant__c(Id = grant.Id, Fund_Id__c = 'not an id');
			} catch (DmlException e) {
				refusedText = e.getDmlMessage(0);
			}
			String refusedGrant;
			try {
				GrantFundController.setFund(grant.Id, grant.Id);
			} catch (AuraHandledException e) {
				refusedGrant = e.getMessage();
			}
			if (fundType == null) {
				Test.stopTest();
				Assert.isFalse(card.available, 'Without Giving there is nothing to choose');
				Assert.areEqual(
					BarnHelp.text('Funders', 'Funders_Grant_BadFund'),
					refusedText,
					'Text is refused'
				);
				Assert.areEqual(
					BarnHelp.text('Funders', 'Funders_Grant_BadFund'),
					refusedGrant,
					'And so is saving'
				);
				return;
			}
			SObject fund = fundType.newSObject();
			fund.put('Name', 'Literacy Fund');
			insert fund;
			GrantFundController.setFund(grant.Id, String.valueOf(fund.Id).left(15));
			GrantFundController.FundCard chosen = GrantFundController.getFund(grant.Id);
			GrantFundController.setFund(grant.Id, '');
			Test.stopTest();

			Assert.isTrue(card.available, 'Funds can be chosen');
			Assert.isTrue(card.canEdit, 'By the admin');
			Assert.areEqual(
				Schema.SObjectType.Grant__c.fields.Fund_Id__c.getLabel(),
				card.title,
				'Titled by the field label'
			);
			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Grant_BadFund'),
				refusedText,
				'Text is refused'
			);
			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Grant_BadFund'),
				refusedGrant,
				'A grant is not a fund'
			);
			Assert.areEqual(String.valueOf(fund.Id), chosen.fundId, 'Stored in 18 characters');
			Assert.areEqual('Literacy Fund', chosen.fundName, 'Shown by name');
			Assert.isFalse(chosen.missing, 'It is there');
			Assert.isNull(
				[SELECT Fund_Id__c FROM Grant__c WHERE Id = :grant.Id WITH SYSTEM_MODE].Fund_Id__c,
				'Cleared'
			);
		}
	}

	@IsTest
	static void aReaderIsRefusedSavingTheFund() {
		Grant__c grant;
		System.runAs(TestUsers.adminWithInstalledModules()) {
			grant = restrictedAward();
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Gfundreader' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			Test.startTest();
			GrantFundController.FundCard card = GrantFundController.getFund(grant.Id);
			String refusal;
			try {
				GrantFundController.setFund(grant.Id, '');
			} catch (AuraHandledException e) {
				refusal = e.getMessage();
			}
			Test.stopTest();

			Assert.isFalse(card.canEdit, 'A reader cannot edit the card');
			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Pipeline_ErrorNoPermission'),
				refusal,
				'A reader is refused'
			);
		}
	}

	@IsTest
	static void aPersonWithoutAccessGetsTheLoadFailureMessage() {
		Grant__c grant;
		System.runAs(TestUsers.adminWithInstalledModules()) {
			grant = restrictedAward();
		}
		User nobody = [
			SELECT Id
			FROM User
			WHERE LastName = 'Gfundnoaccess'
			WITH SYSTEM_MODE
			LIMIT 1
		];
		System.runAs(nobody) {
			Test.startTest();
			String message;
			try {
				GrantFundController.getFund(grant.Id);
			} catch (AuraHandledException e) {
				message = e.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Fund_LoadFailed'),
				message,
				'The card says it did not load'
			);
		}
	}

	@IsTest
	static void savingToAGrantThatHasGoneShowsTheDatabaseMessage() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = restrictedAward();
			Id gone = grant.Id;
			delete grant;

			Test.startTest();
			String message;
			try {
				GrantFundController.setFund(gone, '');
			} catch (AuraHandledException e) {
				message = e.getMessage();
			}
			Test.stopTest();

			Assert.isNotNull(message, 'Saving to a deleted grant is refused with a message');
		}
	}

	@IsTest
	static void aGrantThePersonCannotSeeGivesAnEmptyCard() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = restrictedAward();
			Id gone = grant.Id;
			delete grant;

			Test.startTest();
			GrantFundController.FundCard card = GrantFundController.getFund(gone);
			Test.stopTest();

			Assert.isFalse(card.available, 'Nothing to show');
			Assert.isNull(card.fundId, 'No fund');
		}
	}
}
