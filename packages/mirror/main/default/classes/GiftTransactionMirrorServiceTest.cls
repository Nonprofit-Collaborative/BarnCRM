/**
 * The Gift Transaction mirror (X-07, canonical model Section 29C1) as Maria sees it.
 *
 * The test org has no Nonprofit Cloud, so the present path runs against stand-ins of the same
 * shape (`GiftTransactionMirrorSchema.useStandIns`, ADR-0157 decision 9): Gift for Gift
 * Transaction, Gift Allocation for Gift Transaction Designation, Fund for Gift Designation, and
 * the paid status is Received. The mirror's real dynamic queries and DML run against them. The
 * absent path is forced with `absentForTest`, so it is proved on an org with Nonprofit Cloud too.
 */
@IsTest(
	testFor='ApexClass:GiftTransactionMirrorService,ApexClass:GiftTransactionMirrorSelector, ApexClass:GiftTransactionMirrorTriggerHandler'
)
private class GiftTransactionMirrorServiceTest {
	private static final String LOG_CONTEXT = 'Gift Transaction mirror';
	private static final Date GIFT_DATE = Date.newInstance(2026, 9, 20);

	@TestSetup
	static void setup() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.ensureDefaultFund();
			GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
			Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
			settings.Gift_Transaction_Mirror_Direction__c = GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS;
			settings.Gift_Transaction_Mirror_Status__c = 'Received';
			settings.Gift_Transaction_Mirror_Start__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0);
			upsert settings;
		}
	}

	/** Maria: an administrator who runs the mirror. */
	private static User maria() {
		return TestDataFactory.createUserOnTheRunningUsersProfile(
			'Maria',
			new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Salesforce_Records_Sync' }
		);
	}

	private static Contact luis() {
		return [
			SELECT Id, AccountId
			FROM Contact
			WHERE LastName = 'Garcia'
			WITH SYSTEM_MODE
			LIMIT 1
		];
	}

	private static Gift__c insertGift(Decimal amount) {
		Gift__c gift = GivingTestDataFactory.buildGift(luis().Id, amount);
		gift.Gift_Date__c = GIFT_DATE;
		insert as user gift;
		return reread(gift.Id);
	}

	private static Gift__c reread(Id giftId) {
		return (Gift__c) Database.queryWithBinds(
			'SELECT ' +
				GiftTransactionMirrorSelector.GIFT_FIELDS +
				' FROM Gift__c WHERE Id = :giftId',
			new Map<String, Object>{ 'giftId' => giftId },
			AccessLevel.SYSTEM_MODE
		)[0];
	}

	/** The stand-in Gift Transaction: a gift. */
	private static Gift__c standIn(String giftTransactionId) {
		return [
			SELECT Id, Donor_Account__c, Gift_Date__c, Amount__c, Status__c
			FROM Gift__c
			WHERE Id = :giftTransactionId
			WITH SYSTEM_MODE
		];
	}

	private static List<Gift_Allocation__c> designationsOf(String giftTransactionId) {
		return [
			SELECT Fund__c, Amount__c
			FROM Gift_Allocation__c
			WHERE Gift__c = :giftTransactionId
			WITH SYSTEM_MODE
		];
	}

	private static List<Error_Log__c> warnings() {
		return [
			SELECT Message__c
			FROM Error_Log__c
			WHERE Context__c = :LOG_CONTEXT AND Severity__c = 'Warning'
			WITH SYSTEM_MODE
		];
	}

	private static void setPaidStatus(String status) {
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		settings.Gift_Transaction_Mirror_Status__c = status;
		upsert as system settings;
	}

	// --------------------------------------------------------------------------- absent path

	@IsTest
	static void withoutNonprofitCloudNothingIsCopiedOrChecked() {
		System.runAs(maria()) {
			Gift__c gift = insertGift(100);
			GiftTransactionMirrorSchema.absentForTest = true;

			Assert.isFalse(
				GiftTransactionMirrorService.isAvailable(),
				'Without Gift Transaction the mirror is unavailable (R-GT1).'
			);
			Assert.isFalse(
				GiftTransactionMirrorService.isOn(),
				'A chosen direction does not switch it on.'
			);
			Assert.isFalse(GiftTransactionMirrorService.canRun(), 'No run could work.');
			Assert.isFalse(
				GiftTransactionMirrorSchema.canWriteDesignations(),
				'Nor write designations.'
			);
			Assert.isNull(GiftTransactionMirrorSchema.objectName(), 'No object name is resolved.');
			Assert.isTrue(
				GiftTransactionMirrorSchema.creatable().isEmpty(),
				'No field is writable.'
			);
			Assert.isFalse(
				GiftTransactionMirrorSchema.isActiveStatus('Paid'),
				'No status is known.'
			);

			GiftTransactionMirrorService.Result result = GiftTransactionMirrorService.copyGifts(
				new List<Gift__c>{ gift }
			);
			Assert.areEqual(
				0,
				result.created + result.failed + result.unchanged,
				'A run copies nothing.'
			);

			gift.Gift_Transaction_Id__c = 'anything typed';
			update as user gift;
			Assert.areEqual(
				'anything typed',
				reread(gift.Id).Gift_Transaction_Id__c,
				'A typed link is not checked (R-GT9).'
			);
			delete as user gift;
		}
		Assert.areEqual(0, warnings().size(), 'And nothing is logged.');
	}

	// ------------------------------------------------------------------- settings and readiness

	@IsTest
	static void settingsReadWithDefaultsAndReadiness() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Assert.areEqual(
				GiftTransactionMirrorService.GIFTS_TO_GIFT_TRANSACTIONS,
				GiftTransactionMirrorService.direction()
			);
			Assert.isTrue(GiftTransactionMirrorService.isOn(), 'Available and chosen: on.');
			Assert.isTrue(GiftTransactionMirrorService.canRun(), 'Maria can run it.');
			Assert.areEqual(Date.newInstance(2026, 1, 1), GiftTransactionMirrorService.startDate());
			Assert.isNull(
				GiftTransactionMirrorService.notReadyReason(),
				'Status and start date are set.'
			);

			setPaidStatus(null);
			Assert.areEqual(
				'Paid',
				GiftTransactionMirrorService.paidStatus(),
				'Blank reads as the shipped default (R-GT2).'
			);
			setPaidStatus('Settled');
			Assert.isTrue(
				GiftTransactionMirrorService.notReadyReason().contains('Settled'),
				'A status that is not an active value is named.'
			);

			Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
			settings.Gift_Transaction_Mirror_Status__c = 'Received';
			settings.Gift_Transaction_Mirror_Start__c = null;
			settings.Gift_Transaction_Mirror_Direction__c = 'Backwards';
			upsert as system settings;
			Assert.areEqual(
				BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_NoStartDate'),
				GiftTransactionMirrorService.notReadyReason()
			);
			Assert.areEqual(
				GiftTransactionMirrorService.OFF,
				GiftTransactionMirrorService.direction(),
				'An unknown direction is Off.'
			);
			Assert.isFalse(GiftTransactionMirrorService.isOn());
		}
	}

	// ------------------------------------------------------------------------- present path

	@IsTest
	static void aReceivedGiftGetsAGiftTransactionThatFollowsIt() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Gift__c gift = insertGift(100);

			GiftTransactionMirrorService.Result first = GiftTransactionMirrorService.copyGifts(
				new List<Gift__c>{ gift }
			);
			Assert.areEqual(1, first.created, 'One Gift Transaction is created (R-GT4).');
			String linked = reread(gift.Id).Gift_Transaction_Id__c;
			Assert.isNotNull(linked, 'And its identifier is stored on the gift.');
			Gift__c created = standIn(linked);
			Assert.areEqual(
				gift.Household__c,
				created.Donor_Account__c,
				'The donor is the household.'
			);
			Assert.areEqual(GIFT_DATE, created.Gift_Date__c);
			Assert.areEqual(100, created.Amount__c);
			Assert.areEqual('Received', created.Status__c, 'With the paid status.');
			Assert.areEqual(
				0,
				first.designated,
				'A Gift Transaction that has a designation gets none (R-GT5).'
			);

			GiftTransactionMirrorService.Result again = GiftTransactionMirrorService.copyGifts(
				new List<Gift__c>{ reread(gift.Id) }
			);
			Assert.areEqual(1, again.unchanged, 'An unchanged gift writes nothing.');

			gift = reread(gift.Id);
			gift.Amount__c = 150;
			update as user gift;
			GiftTransactionMirrorService.Result changed = GiftTransactionMirrorService.copyGifts(
				new List<Gift__c>{ reread(gift.Id) }
			);
			Assert.areEqual(1, changed.updated, 'A changed amount follows the gift.');
			Assert.areEqual(150, standIn(linked).Amount__c);
		}
	}

	@IsTest
	static void designationsFollowLinkedFundsOnly() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Fund__c designation = new Fund__c(Name = 'Stand-in Designation', Active__c = true);
			Fund__c unlinked = new Fund__c(Name = 'Unlinked Fund', Active__c = true);
			insert as user new List<Fund__c>{ designation, unlinked };
			Fund__c defaultFund = GivingTestDataFactory.ensureDefaultFund();
			defaultFund.Gift_Designation_Id__c = designation.Id;
			update as user defaultFund;

			Gift__c designated = insertGift(100);
			Gift__c undesignated = insertGift(40);
			update as user new Gift_Allocation__c(
				Id = [
					SELECT Id
					FROM Gift_Allocation__c
					WHERE Gift__c = :undesignated.Id
					WITH SYSTEM_MODE
					LIMIT 1
				]
				.Id,
				Fund__c = unlinked.Id
			);

			// The stand-in Gift Transactions are gifts: keep Giving from allocating them itself.
			AutomationControl.bypass('Gift_Core_Rules');
			GiftTransactionMirrorService.Result result = GiftTransactionMirrorService.copyGifts(
				new List<Gift__c>{ reread(designated.Id), reread(undesignated.Id) }
			);
			AutomationControl.clearBypass('Gift_Core_Rules');

			Assert.areEqual(2, result.created);
			Assert.areEqual(1, result.designated, 'The linked fund becomes a designation (R-GT5).');
			Assert.areEqual(1, result.undesignated, 'The unlinked fund is counted, not guessed.');
			List<Gift_Allocation__c> written = designationsOf(
				reread(designated.Id).Gift_Transaction_Id__c
			);
			Assert.areEqual(1, written.size());
			Assert.areEqual(designation.Id, written[0].Fund__c);
			Assert.areEqual(100, written[0].Amount__c);
			Assert.isTrue(designationsOf(reread(undesignated.Id).Gift_Transaction_Id__c).isEmpty());
		}
	}

	@IsTest
	static void giftsThatCannotBeCopiedAreCountedAndLogged() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Gift__c noAccount = insertGift(10);
			noAccount.Household__c = null;
			Gift__c invalid = insertGift(20);
			invalid.Gift_Transaction_Id__c = 'not an id';
			Gift__c gone = insertGift(30);
			Gift__c deleted = insertGift(1);
			delete as user deleted;
			gone.Gift_Transaction_Id__c = deleted.Id;
			Gift__c pending = insertGift(40);
			pending.Status__c = 'Pending';

			GiftTransactionMirrorService.Result result = GiftTransactionMirrorService.copyGifts(
				new List<Gift__c>{ noAccount, invalid, gone, pending }
			);
			Assert.areEqual(0, result.created);
			Assert.areEqual(
				3,
				result.failed,
				'No account, an invalid link and a missing Gift Transaction.'
			);
			Assert.areEqual(1, result.unchanged, 'A pending gift is not copied (R-GT3).');

			Test.startTest();
			result.writeRefusals();
			Test.stopTest();
		}
		String logged = String.valueOf(warnings());
		Assert.isTrue(logged.contains('no Donor Account and no Household'), logged);
		Assert.isTrue(logged.contains('15 or 18 characters'), logged);
		Assert.isTrue(logged.contains('deleted or is not visible'), logged);
	}

	@IsTest
	static void aGiftThatCannotTakeItsLinkLeavesNoGiftTransaction() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Gift__c gift = insertGift(100);
			delete as user new Gift__c(Id = gift.Id);
			Integer before = [SELECT COUNT() FROM Gift__c WITH SYSTEM_MODE];

			GiftTransactionMirrorService.Result result = GiftTransactionMirrorService.copyGifts(
				new List<Gift__c>{ gift }
			);
			Assert.areEqual(0, result.created, 'The link could not be stored (R-GT7).');
			Assert.areEqual(1, result.failed);
			Assert.isTrue(result.createdFor.isEmpty(), 'So it gets no designations.');
			Assert.areEqual(
				before,
				[SELECT COUNT() FROM Gift__c WITH SYSTEM_MODE],
				'And its Gift Transaction is deleted again.'
			);
		}
	}

	// ------------------------------------------------------------------------ the automation

	@IsTest
	static void aTypedLinkIsCheckedAndADeletedGiftReported() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			Gift__c gift = insertGift(100);
			Gift__c other = insertGift(5);

			gift.Gift_Transaction_Id__c = 'G-000001';
			Database.SaveResult refused = Database.update(gift, false, AccessLevel.USER_MODE);
			Assert.isFalse(
				refused.isSuccess(),
				'A typed value that is not a Gift Transaction is refused (R-GT9).'
			);
			Assert.areEqual(
				BarnHelp.text('Mirror', 'Mirror_GiftTransactionMirror_InvalidGiftTransactionId'),
				refused.getErrors()[0].getMessage()
			);

			gift.Gift_Transaction_Id__c = String.valueOf(other.Id).left(15);
			update as user gift;
			Assert.areEqual(
				String.valueOf(other.Id),
				reread(gift.Id).Gift_Transaction_Id__c,
				'Stored in its 18 character form.'
			);

			gift.Gift_Transaction_Id__c = '  ';
			update as user gift;
			Assert.isNull(reread(gift.Id).Gift_Transaction_Id__c, 'Blank clears the link.');

			gift.Gift_Transaction_Id__c = String.valueOf(other.Id);
			update as user gift;
			Test.startTest();
			delete as user reread(gift.Id);
			Test.stopTest();
		}
		List<Error_Log__c> logged = warnings();
		Assert.areEqual(1, logged.size(), 'One Warning for the deleted gift (R-GT8).');
		Assert.isTrue(logged[0].Message__c.contains('left in place'), logged[0].Message__c);
	}
}
