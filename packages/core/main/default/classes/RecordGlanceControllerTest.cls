/**
 * The glance card on Core's record pages shows what installed modules return and nothing of
 * its own (people-14, ADR-0167). No module is present in
 * Core's tests, so extensions are injected by class name, as modules register theirs.
 */
@IsTest(testFor='ApexClass:RecordGlanceController, ApexClass:RecordGlanceExtensions')
private class RecordGlanceControllerTest {
	private static final String GIVING = 'GivingRecordGlanceExtension';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private class StubExtension implements RecordGlanceExtension {
		public RecordGlance.Card glance(Id recordId) {
			return new RecordGlance.Card('stub', 'Stub Card', 'standard:account')
				.addCurrency('Total', 12.5)
				.addNumber('Count', 3)
				.addDate('Last', Date.newInstance(2026, 11, 1))
				.addText('Level', 'Friend')
				.addAction(
					'Go',
					new Map<String, Object>{
						'type' => 'standard__recordPage',
						'attributes' => new Map<String, Object>{ 'recordId' => recordId }
					}
				);
		}
	}

	private class NothingToSay implements RecordGlanceExtension {
		public RecordGlance.Card glance(Id recordId) {
			return null;
		}
	}

	private class FailingExtension implements RecordGlanceExtension {
		public RecordGlance.Card glance(Id recordId) {
			throw new System.QueryException('The extension could not answer');
		}
	}

	private static void only(RecordGlanceExtension extension) {
		RecordGlanceExtensions.noneForTest = true;
		RecordGlanceExtensions.overrides.clear();
		if (extension != null) {
			RecordGlanceExtensions.overrides.put(GIVING, extension);
		}
	}

	@IsTest
	static void coreAloneShowsNoCard() {
		System.runAs(TestUsers.admin()) {
			only(null);
			Assert.isTrue(
				RecordGlanceController.getCards(FakeIds.of(Contact.SObjectType, 1)).isEmpty(),
				'With no module installed the card has nothing to draw'
			);
			Assert.isTrue(RecordGlanceController.getCards(null).isEmpty(), 'No record, no card');
		}
	}

	@IsTest
	static void aModuleCardIsReturnedAsTheModuleBuiltIt() {
		System.runAs(TestUsers.admin()) {
			only(new StubExtension());
			Id recordId = FakeIds.of(Contact.SObjectType, 1);
			List<RecordGlance.Card> cards = RecordGlanceController.getCards(recordId);
			Assert.areEqual(1, cards.size(), 'One card from the one module');
			Assert.areEqual('Stub Card', cards[0].title, 'The module names its card');
			Assert.areEqual(12.5, cards[0].tiles[0].numberValue, 'The figure is passed through');
			Assert.areEqual(
				RecordGlance.KIND_CURRENCY,
				cards[0].tiles[0].kind,
				'Money is marked as money'
			);
			Assert.areEqual(
				RecordGlance.KIND_NUMBER,
				cards[0].tiles[1].kind,
				'A count is a number'
			);
			Assert.areEqual(Date.newInstance(2026, 11, 1), cards[0].tiles[2].dateValue, 'A date');
			Assert.areEqual('Friend', cards[0].tiles[3].textValue, 'A word');
			Assert.isTrue(
				cards[0].actions[0].pageReference.contains(String.valueOf(recordId)),
				'The action carries its page reference as JSON'
			);
		}
	}

	@IsTest
	static void aModuleWithNothingOrAFailureIsLeftOutAndAFailureLogged() {
		System.runAs(TestUsers.admin()) {
			only(new NothingToSay());
			Assert.isTrue(
				RecordGlanceController.getCards(FakeIds.of(Contact.SObjectType, 1)).isEmpty(),
				'A module with nothing to show adds no card'
			);
			only(new FailingExtension());
			Test.startTest();
			Assert.isTrue(
				RecordGlanceController.getCards(FakeIds.of(Contact.SObjectType, 1)).isEmpty(),
				'A failing module adds no card and the page still opens'
			);
			Test.stopTest();
		}
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM Error_Log__c
				WHERE Context__c = 'RecordGlanceExtensions.cardsFor'
				WITH SYSTEM_MODE
			],
			'The failure is logged'
		);
	}

	@IsTest
	static void registeredClassesAreFoundByNameAndUnusableOnesAreAbsent() {
		System.runAs(TestUsers.admin()) {
			RecordGlanceExtensions.overrides.clear();
			RecordGlanceExtensions.noneForTest = false;
			Test.startTest();
			RecordGlanceExtensions.EXTENSION_CLASSES.clear();
			RecordGlanceExtensions.EXTENSION_CLASSES.add('NoSuchClassAnywhere');
			Assert.isTrue(
				RecordGlanceExtensions.installed().isEmpty(),
				'A class that is not installed is absent'
			);
			RecordGlanceExtensions.EXTENSION_CLASSES.clear();
			RecordGlanceExtensions.EXTENSION_CLASSES.add('ExtensionFakeNotAnExtension');
			Assert.isTrue(
				RecordGlanceExtensions.installed().isEmpty(),
				'A class that is not an extension is absent'
			);
			RecordGlanceExtensions.EXTENSION_CLASSES.clear();
			RecordGlanceExtensions.EXTENSION_CLASSES.add('ExtensionFakeUnbuildable');
			Assert.isTrue(
				RecordGlanceExtensions.installed().isEmpty(),
				'A class that cannot be built is absent'
			);
			Test.stopTest();
		}
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM Error_Log__c
				WHERE Context__c = 'RecordGlanceExtensions.resolve'
				WITH SYSTEM_MODE
			],
			'Each unusable class is logged'
		);
	}

	/**
	 * QA review Q1: the glance card is on every person page, so a Read Only user (Standard
	 * User profile, BarnCRM Read Only) gets the module's card just as an admin does.
	 */
	@IsTest
	static void aReadOnlyUserGetsTheModuleCard() {
		User reader;
		System.runAs(TestUsers.admin()) {
			reader = TestDataFactory.createUser('Reader', new List<String>{ 'BarnCRM_Read_Only' });
		}
		List<RecordGlance.Card> cards;
		Test.startTest();
		System.runAs(reader) {
			only(new StubExtension());
			cards = RecordGlanceController.getCards(FakeIds.of(Contact.SObjectType, 1));
		}
		Test.stopTest();

		Assert.areEqual(1, cards.size(), 'The reader sees the module card');
		Assert.areEqual('Stub Card', cards[0].title, 'As the module built it');
	}
}
