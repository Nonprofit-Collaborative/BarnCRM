/**
 * The NPSP Gifts kit (MIG-05, canonical model R-MK1): every step reads as an import step whose
 * shipped template is copied into the org, loads what it should and names only columns the step
 * reads or the extension adds; a won Opportunity's row names its donor by record Id, its payment
 * method and its split; a soft credit's role and amount follow BarnCRM's. NPSP itself is not
 * needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:NpspGiftsKit, ApexClass:MigrationKitService')
private class NpspGiftsKitTest {
	private static final Set<String> ADDED = new Set<String>{
		'Donor',
		'ContactId',
		'OrganizationId',
		'OpportunityId',
		'Method',
		'Reference',
		'Fund1',
		'Fund2',
		'Fund3',
		'Fund4',
		'Fund5',
		'Amount1',
		'Amount2',
		'Amount3',
		'Amount4',
		'Amount5',
		'CreditRole',
		'CustomRole',
		'Amount'
	};

	@IsTest
	static void eachStepHasItsTemplateAndNamesOnlyWhatItReads() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(NpspGiftsKit.KIT);
			ImportTemplateService.materializeDefaults();
			Map<String, String> targetByStep = new Map<String, String>{
				'appeals' => 'Appeal__c',
				'contactCredits' => 'Soft_Credit__c',
				'organizationContacts' => 'Soft_Credit__c',
				'accountCredits' => 'Soft_Credit__c'
			};
			List<String> keys = new List<String>(targetByStep.keySet());
			keys.add('gifts');
			for (String key : keys) {
				MigrationKitService.Step step = MigrationKitService.stepNamed(kit, key);
				Assert.areEqual(MigrationKitService.KIND_IMPORT, step.kind, key + ' loads');
				Import_Template__c template = [
					SELECT Column_Mapping_JSON__c, Target_Object__c
					FROM Import_Template__c
					WHERE Template_Key__c = :step.templateKey
					WITH SYSTEM_MODE
				];
				if (targetByStep.containsKey(key)) {
					Assert.isTrue(
						template.Target_Object__c.endsWith(targetByStep.get(key)),
						key + ' loads ' + targetByStep.get(key)
					);
				}
				for (
					ImportMapping.Column column : ImportMapping.parse(
							template.Column_Mapping_JSON__c
						)
						.getColumns()
				) {
					String heading = column.getSource();
					Assert.isTrue(
						step.fields.contains(heading) || ADDED.contains(heading) || heading == 'Id',
						key + ' maps only what it reads: ' + heading
					);
				}
			}
		}
	}

	@IsTest
	static void anIndividualsGiftNamesItsContactMethodAndSplit() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Map<String, Object> row = new Map<String, Object>{
			'Id' => '006000000000001AAA',
			'Amount' => '300',
			'AccountId' => '001000000000001AAA',
			'npsp.Primary_Contact__c' => '003000000000001AAA',
			'Account.npe01.SYSTEM_IsIndividual__c' => 'true'
		};
		NpspGiftsKit.giftRow(
			row,
			new List<String>{ 'Check', '1201' },
			new List<NpspGiftsKit.Part>{
				new NpspGiftsKit.Part('Building Fund', 200),
				new NpspGiftsKit.Part('General Fund', 100)
			}
		);
		Assert.areEqual('Contact1', row.get('Donor'), 'a person gives');
		Assert.areEqual('003000000000001AAA', row.get('ContactId'), 'the primary contact');
		Assert.areEqual('', row.get('OrganizationId'), 'no organization');
		Assert.areEqual('006000000000001AAA', row.get('OpportunityId'), 'keeps its Opportunity');
		Assert.areEqual('Check', row.get('Method'), 'paid by check');
		Assert.areEqual('1201', row.get('Reference'), 'check number');
		Assert.areEqual('Building Fund', row.get('Fund1'), 'largest part first');
		Assert.areEqual('200', row.get('Amount1'), 'its amount');
		Assert.areEqual('100', row.get('Amount2'), 'second part');
	}

	@IsTest
	static void anOrganizationsGiftWithOneFundAndNoPayment() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Map<String, Object> row = new Map<String, Object>{
			'Id' => '006000000000002AAA',
			'Amount' => '500',
			'AccountId' => '001000000000002AAA',
			'npsp.Primary_Contact__c' => '003000000000002AAA',
			'Account.npe01.SYSTEM_IsIndividual__c' => 'false'
		};
		NpspGiftsKit.giftRow(
			row,
			null,
			new List<NpspGiftsKit.Part>{ new NpspGiftsKit.Part('Building Fund', 500) }
		);
		Assert.areEqual('Organization', row.get('Donor'), 'the organization gives');
		Assert.areEqual('001000000000002AAA', row.get('OrganizationId'), 'its account');
		Assert.areEqual('Other', row.get('Method'), 'no paid payment');
		Assert.areEqual('Building Fund', row.get('Fund1'), 'one fund');
		Assert.isFalse(row.containsKey('Amount1'), 'the whole gift, not a split');
	}

	@IsTest
	static void aSplitKeepsAtMostFivePartsAndBlankAmounts() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		List<NpspGiftsKit.Part> parts = new List<NpspGiftsKit.Part>();
		for (Integer index = 1; index <= 6; index++) {
			parts.add(new NpspGiftsKit.Part('Fund ' + index, index == 2 ? null : index * 10));
		}
		Map<String, Object> many = new Map<String, Object>();
		NpspGiftsKit.putSplit(many, parts, '210');
		Assert.areEqual('Fund 5', many.get('Fund5'), 'the fifth part is kept');
		Assert.isFalse(many.containsKey('Fund6'), 'the sixth part is dropped');
		Assert.areEqual('', many.get('Amount2'), 'a part with no amount is blank');
		Assert.areEqual('50', many.get('Amount5'), 'its amount as text');

		Map<String, Object> mismatch = new Map<String, Object>();
		NpspGiftsKit.putSplit(
			mismatch,
			new List<NpspGiftsKit.Part>{ new NpspGiftsKit.Part('Part Fund', 40) },
			'100'
		);
		Assert.areEqual('40', mismatch.get('Amount1'), 'one part of the gift stays a split');

		Map<String, Object> none = new Map<String, Object>();
		NpspGiftsKit.putSplit(none, null, '100');
		NpspGiftsKit.putSplit(none, new List<NpspGiftsKit.Part>(), '100');
		Assert.isTrue(none.isEmpty(), 'no allocations, no columns');
	}

	@IsTest
	static void rowsAreShapedWhenNpspHoldsNoPaymentsAllocationsOrPartialCredits() {
		// runs-as: deploying user (text rows only; without NPSP its objects read as none)
		List<Map<String, Object>> gifts = new List<Map<String, Object>>{
			new Map<String, Object>{
				'Id' => '006000000000003AAA',
				'Amount' => '90',
				'AccountId' => '001000000000003AAA',
				'npsp.Primary_Contact__c' => '',
				'Account.npe01.SYSTEM_IsIndividual__c' => 'true'
			}
		};
		NpspGiftsKit.shapeGifts(gifts);
		Assert.areEqual(
			'Organization',
			gifts[0].get('Donor'),
			'no primary contact, so the account'
		);
		Assert.areEqual('Other', gifts[0].get('Method'), 'no paid payment');
		Assert.areEqual('', gifts[0].get('Reference'), 'no reference');
		Assert.isFalse(gifts[0].containsKey('Fund1'), 'no allocations, no split');

		List<Map<String, Object>> credits = new List<Map<String, Object>>{
			new Map<String, Object>{
				'OpportunityId' => '006000000000003AAA',
				'ContactId' => '003000000000003AAA',
				'Role' => 'Influencer',
				'Opportunity.Amount' => '90'
			},
			new Map<String, Object>{
				'OpportunityId' => '006000000000003AAA',
				'npsp.Role__c' => 'Friend'
			}
		};
		NpspGiftsKit.shapeCredits(credits);
		Assert.areEqual('Influencer', credits[0].get('CreditRole'), 'a contact credit role');
		Assert.areEqual('90', credits[0].get('Amount'), 'the whole gift without a partial credit');
		Assert.areEqual('Other', credits[1].get('CreditRole'), 'an account credit role');
		Assert.areEqual('Friend', credits[1].get('CustomRole'), 'keeps NPSP name');
	}

	@IsTest
	static void aReadReturnsOnlyWhatTheObjectHoldsAndNothingWithoutIdsOrTheObject() {
		System.runAs(TestUsers.admin()) {
			Contact ana = TestDataFactory.person(new Contact(LastName = 'Giftskit'));
			insert ana;
			String query = 'SELECT Id FROM Contact WHERE Id IN :ids';
			Assert.areEqual(
				1,
				NpspGiftsKit.read('Contact', query, new Set<String>{ ana.Id }).size(),
				'the record is read'
			);
			Assert.isTrue(
				NpspGiftsKit.read('Contact', query, new Set<String>()).isEmpty(),
				'no ids, no query'
			);
			Assert.isTrue(
				NpspGiftsKit.read('npsp~Allocation__c', query, new Set<String>{ ana.Id }).isEmpty(),
				'no NPSP, no records'
			);
		}
	}

	@IsTest
	static void aColumnListsItsDistinctNonBlankValues() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Set<String> values = NpspGiftsKit.column(
			new List<Map<String, Object>>{
				new Map<String, Object>{ 'Id' => 'a' },
				new Map<String, Object>{ 'Id' => 'a' },
				new Map<String, Object>{ 'Id' => '' },
				new Map<String, Object>{ 'Id' => 'b' }
			},
			'Id'
		);
		Assert.areEqual(new Set<String>{ 'a', 'b' }, values, 'distinct and non-blank');
		Map<String, Object> padded = new Map<String, Object>();
		NpspGiftsKit.putRole(padded, '  HONOREE ');
		Assert.areEqual('Honoree', padded.get('CreditRole'), 'trimmed, any case');
	}

	@IsTest
	static void stepsReadingNpspObjectsAreRefusedWithoutThemAndContactCreditsStage() {
		System.runAs(TestUsers.withPermissionSets(
			new List<String>{
				TestUsers.CORE_ADMIN,
				'Rollup_Builder_Admin',
				'Giving_Admin',
				'Salesforce_Records_Sync'
			}
		)) {
			NpspGiftsKit extension = new NpspGiftsKit();
			List<Map<String, Object>> credits = extension.rows(
				'contactCredits',
				new List<SObject>()
			);
			Assert.isTrue(credits.isEmpty(), 'no records, no staged credits');
			for (String key : new List<String>{ 'gifts', 'accountCredits' }) {
				try {
					Assert.isNotNull(extension.rows(key, new List<SObject>()), key);
				} catch (Exception refused) {
					Assert.isTrue(
						refused.getMessage().contains('this org does not have'),
						key + ' names what is missing: ' + refused.getMessage()
					);
				}
			}
		}
	}

	@IsTest
	static void aSoftCreditKeepsBarnRolesAndPartialAmounts() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Map<String, Object> solicitor = new Map<String, Object>{ 'Opportunity.Amount' => '400' };
		NpspGiftsKit.creditRow(solicitor, 'solicitor', null);
		Assert.areEqual('Solicitor', solicitor.get('CreditRole'), 'BarnCRM role');
		Assert.areEqual('', solicitor.get('CustomRole'), 'no custom role');
		Assert.areEqual('400', solicitor.get('Amount'), 'the whole gift');

		Map<String, Object> partial = new Map<String, Object>{ 'Opportunity.Amount' => '400' };
		NpspGiftsKit.creditRow(partial, 'Soft Credit', 150);
		Assert.areEqual('Other', partial.get('CreditRole'), 'not a BarnCRM role');
		Assert.areEqual('Soft Credit', partial.get('CustomRole'), 'keeps the NPSP name');
		Assert.areEqual('150', partial.get('Amount'), 'the partial amount');

		Map<String, Object> ofAccount = new Map<String, Object>{
			'npsp.Role__c' => null,
			'npsp.Amount__c' => '50'
		};
		NpspGiftsKit.creditRow(ofAccount, null, null);
		Assert.areEqual('Soft Credit', ofAccount.get('CustomRole'), 'a blank role');
		Assert.isFalse(ofAccount.containsKey('Amount'), 'an account credit keeps its amount');
		NpspGiftsKit extension = new NpspGiftsKit();
		Assert.isNull(extension.rows('appeals', new List<SObject>()), 'default rows');
		Assert.isNull(extension.verify('gifts'), 'counts are compared');
	}
}
