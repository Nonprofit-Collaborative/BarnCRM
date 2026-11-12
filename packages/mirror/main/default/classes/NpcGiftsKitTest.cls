/**
 * The Nonprofit Cloud Gifts kit (MIG-04, canonical model R-MK1): every step reads as an import
 * step whose shipped template is copied into the org, loads what it should and names only
 * columns the step reads or the extension adds; a paid Gift Transaction's row names its donor,
 * its link and its split; a commitment's type, amount and frequency, and a soft credit's
 * recipient, role and amount follow BarnCRM's; a designation a fund already has is skipped.
 * Nonprofit Cloud itself is not needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:NpcGiftsKit, ApexClass:MigrationKitService')
private class NpcGiftsKitTest {
	private static final Set<String> ADDED = new Set<String>{
		'Id',
		'Donor',
		'ContactId',
		'OrganizationId',
		'AccountId',
		'DonorContact',
		'DonorAccount',
		'GiftTransactionId',
		'Type',
		'Amount',
		'Frequency',
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
		'TributeType',
		'HonoreeName',
		'NotifyName',
		'NotifyMessage',
		'CreditRole',
		'CustomRole'
	};

	@IsTest
	static void eachStepHasItsTemplateAndNamesOnlyWhatItReads() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(NpcGiftsKit.KIT);
			ImportTemplateService.materializeDefaults();
			Map<String, String> targetByStep = new Map<String, String>{
				'appeals' => 'Appeal__c',
				'funds' => 'Fund__c',
				'commitments' => 'Commitment__c',
				'credits' => 'Soft_Credit__c'
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
						step.fields.contains(heading) || ADDED.contains(heading),
						key + ' maps only what it reads: ' + heading
					);
				}
			}
			NpcGiftsKit extension = new NpcGiftsKit();
			Assert.isNull(extension.rows('appeals', new List<SObject>()), 'default rows');
			Assert.isNull(extension.verify('gifts'), 'counts are compared');
			MigrationCheck funds = extension.verify('funds');
			Assert.areEqual(funds.source, funds.done, 'no designation lacks a fund');
		}
	}

	@IsTest
	static void aPersonAccountsGiftNamesItsContactLinkSplitAndTribute() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Map<String, Object> row = new Map<String, Object>{
			'Id' => '6gt000000000001AAA',
			'OriginalAmount' => '300',
			'DonorId' => '001000000000001AAA'
		};
		NpcGiftsKit.giftRow(
			row,
			new Map<String, String>{ '001000000000001AAA' => '003000000000001AAA' },
			new List<NpspGiftsKit.Part>{
				new NpspGiftsKit.Part('Building Fund', 200),
				new NpspGiftsKit.Part('General Fund', 100)
			},
			new List<String>{ 'Memorial', 'Ann Lee', null, 'With love' }
		);
		Assert.areEqual('Contact1', row.get('Donor'), 'a person gives');
		Assert.areEqual('003000000000001AAA', row.get('ContactId'), 'the person contact');
		Assert.areEqual('', row.get('OrganizationId'), 'no organization');
		Assert.areEqual('6gt000000000001AAA', row.get('GiftTransactionId'), 'linked');
		Assert.areEqual('Building Fund', row.get('Fund1'), 'largest part first');
		Assert.areEqual('100', row.get('Amount2'), 'second part');
		Assert.areEqual('Ann Lee', row.get('HonoreeName'), 'the honoree');
		Assert.areEqual('', row.get('NotifyName'), 'no one notified');

		Map<String, Object> business = new Map<String, Object>{
			'Id' => '6gt000000000002AAA',
			'OriginalAmount' => '500',
			'DonorId' => '001000000000002AAA'
		};
		NpcGiftsKit.giftRow(business, new Map<String, String>(), null, null);
		Assert.areEqual('Organization', business.get('Donor'), 'the organization gives');
		Assert.areEqual('001000000000002AAA', business.get('OrganizationId'), 'its account');
		Assert.isFalse(business.containsKey('Fund1'), 'no designation');
	}

	@IsTest
	static void aCommitmentIsRecurringOrAPledgeWithBarnFrequency() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Map<String, Object> recurring = new Map<String, Object>{
			'DonorId' => '001000000000001AAA',
			'ScheduleType' => 'Recurring',
			'NextTransactionAmount' => '25',
			'ExpectedTotalCmtAmount' => '',
			'EffectiveTransactionPeriod' => 'Weekly',
			'EffectiveTransactionInterval' => '2'
		};
		NpcGiftsKit.commitmentRow(
			recurring,
			new Map<String, String>{ '001000000000001AAA' => '003000000000001AAA' }
		);
		Assert.areEqual('Recurring', recurring.get('Type'), 'recurring');
		Assert.areEqual('25', recurring.get('Amount'), 'each installment');
		Assert.areEqual('Every two weeks', recurring.get('Frequency'), 'every other week');
		Assert.areEqual('003000000000001AAA', recurring.get('DonorContact'), 'the person');

		Map<String, Object> pledge = new Map<String, Object>{
			'DonorId' => '001000000000002AAA',
			'ScheduleType' => 'Custom',
			'ExpectedTotalCmtAmount' => '1000'
		};
		NpcGiftsKit.commitmentRow(pledge, new Map<String, String>());
		Assert.areEqual('Pledge', pledge.get('Type'), 'a pledge');
		Assert.areEqual('1000', pledge.get('Amount'), 'the expected total');
		Assert.areEqual('Monthly', pledge.get('Frequency'), 'no period');
		Assert.areEqual('001000000000002AAA', pledge.get('DonorAccount'), 'the organization');

		Assert.areEqual('Quarterly', NpcGiftsKit.frequency('Monthly', '3'), 'every 3 months');
		Assert.areEqual('Twice a year', NpcGiftsKit.frequency('Monthly', '6'), 'every 6 months');
		Assert.areEqual('Yearly', NpcGiftsKit.frequency('Annually', 'x'), 'annual');
	}

	@IsTest
	static void aSoftCreditAndAFundAlreadyThere() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Map<String, Object> credit = new Map<String, Object>{
			'RecipientId' => '001000000000003AAA',
			'Role' => 'Solicitor',
			'SoftCreditAmount' => '',
			'GiftTransaction.OriginalAmount' => '400'
		};
		NpcGiftsKit.creditRow(credit, new Map<String, String>());
		Assert.areEqual('001000000000003AAA', credit.get('AccountId'), 'an organization');
		Assert.areEqual('Solicitor', credit.get('CreditRole'), 'BarnCRM role');
		Assert.areEqual('400', credit.get('Amount'), 'the gift amount');

		List<Map<String, Object>> designations = new List<Map<String, Object>>{
			new Map<String, Object>{ 'Id' => '0gd000000000001AAA', 'Name' => 'Linked' },
			new Map<String, Object>{ 'Id' => '0gd000000000002AAA', 'Name' => ' General Fund' },
			new Map<String, Object>{ 'Id' => '0gd000000000003AAA', 'Name' => 'New Fund' }
		};
		List<Map<String, Object>> kept = NpcGiftsKit.newFunds(
			designations,
			new Set<String>{ '0gd000000000001AAA', 'general fund' }
		);
		Assert.areEqual(1, kept.size(), 'only the designation no fund has');
		Assert.areEqual('New Fund', kept[0].get('Name'), 'a new fund');
	}
}
