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
