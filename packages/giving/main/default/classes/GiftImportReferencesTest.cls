/**
 * Finding the funds and appeals an imported row names (R-GI3, R-GI4).
 */
@IsTest(testFor='ApexClass:GiftImportReferences')
private class GiftImportReferencesTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static GiftImportRow row(Map<String, String> gift, Map<String, String> allocation) {
		Map<String, String> values = new Map<String, String>{
			'Amount__c' => '100',
			'Gift_Date__c' => '2026-03-15',
			'Type__c' => 'Cash'
		};
		values.putAll(gift);
		return new GiftImportRow(
			new Import_Row__c(),
			new Map<String, Map<String, String>>{ 'Gift' => values, 'Allocation' => allocation }
		);
	}

	private static GiftImportRow fundRow(String fund) {
		return row(new Map<String, String>(), new Map<String, String>{ 'Fund' => fund });
	}

	@IsTest
	static void aFundIsFoundByNameCodeOrIdAndMayBeClosed() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Fund__c general = GivingTestDataFactory.insertDefaultFund();
			Fund__c closed = new Fund__c(
				Name = 'Old Roof',
				Accounting_Code__c = 'R-99',
				Active__c = false
			);
			insert closed;
			List<GiftImportRow> rows = new List<GiftImportRow>{
				fundRow('general'),
				fundRow('r-99'),
				fundRow(String.valueOf(closed.Id)),
				fundRow('Nowhere')
			};

			GiftImportReferences.resolve(rows);

			Assert.areEqual(general.Id, rows[0].singleFund.fundId, 'By name, any capitals.');
			Assert.areEqual(
				closed.Id,
				rows[1].singleFund.fundId,
				'By accounting code, though closed.'
			);
			Assert.areEqual(closed.Id, rows[2].singleFund.fundId, 'By identifier.');
			Assert.isTrue(rows[3].error.contains('Nowhere'), 'A fund that is not there is named.');
		}
	}

	@IsTest
	static void twoFundsWithOneNameAreNotGuessedBetween() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.insertDefaultFund();
			insert new List<Fund__c>{
				new Fund__c(Name = 'Scholarships', Active__c = true, Accounting_Code__c = 'S-1'),
				new Fund__c(Name = 'Scholarships', Active__c = true, Accounting_Code__c = 'S-2')
			};
			List<GiftImportRow> rows = new List<GiftImportRow>{
				fundRow('Scholarships'),
				fundRow('S-2')
			};

			GiftImportReferences.resolve(rows);

			Assert.isTrue(
				rows[0]
					.error.startsWith(
						BarnHelp.text('Giving', 'Giving_Import_ErrorFundAmbiguous')
							.substringBefore('{0}')
					),
				'The name is ambiguous: ' + rows[0].error
			);
			Assert.isNull(rows[1].error, 'The code is not.');
		}
	}

	@IsTest
	static void anAppealIsFoundByName() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.insertDefaultFund();
			Appeal__c spring = GivingTestDataFactory.buildAppeal('Spring Appeal');
			insert spring;
			List<GiftImportRow> rows = new List<GiftImportRow>{
				row(
					new Map<String, String>{ 'Appeal' => 'spring appeal' },
					new Map<String, String>()
				),
				row(new Map<String, String>{ 'Appeal' => 'Autumn' }, new Map<String, String>())
			};

			GiftImportReferences.resolve(rows);

			Assert.areEqual(spring.Id, rows[0].appealId, 'Found.');
			Assert.isTrue(
				rows[1].error.contains('Autumn'),
				'An appeal that is not there is named.'
			);
		}
	}

	@IsTest
	static void aBrandIsFoundByNameOrIdAndTwoOfOneNameAreNotGuessed() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.insertDefaultFund();
			Brand__c thrift = new Brand__c(Name = 'Barn Thrift');
			insert new List<Brand__c>{
				thrift,
				new Brand__c(Name = 'Chapter'),
				new Brand__c(Name = 'Chapter')
			};
			List<GiftImportRow> rows = new List<GiftImportRow>();
			for (String word : new List<String>{ 'barn thrift', thrift.Id, 'Chapter', 'Nowhere' }) {
				rows.add(
					row(new Map<String, String>{ 'Brand' => word }, new Map<String, String>())
				);
			}

			GiftImportReferences.resolve(rows);

			Assert.areEqual(thrift.Id, rows[0].brandId, 'By name, any capitals.');
			Assert.areEqual(thrift.Id, rows[1].brandId, 'By identifier.');
			Assert.isTrue(rows[2].error.contains('More than one brand'), rows[2].error);
			Assert.isTrue(rows[3].error.contains('Nowhere'), 'A brand that is not there is named.');
			Assert.isFalse(
				rows[0].notLoaded.contains('Gift.brand'),
				'The column is read as a brand, not skipped as a field'
			);
		}
	}

	@IsTest
	static void aGiftWithNoFundNeedsADefaultFund() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			List<GiftImportRow> rows = new List<GiftImportRow>{
				row(new Map<String, String>(), new Map<String, String>())
			};

			GiftImportReferences.resolve(rows);

			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_Gift_DefaultFundMissing'),
				rows[0].error,
				'Said in the dry run, before the gift trigger would.'
			);
		}
	}
}
