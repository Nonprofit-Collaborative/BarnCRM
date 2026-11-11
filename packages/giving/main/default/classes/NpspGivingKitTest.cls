/**
 * The NPSP Funds, Levels and Recurring Donations kit (MIG-05, canonical model R-MK1): every step
 * reads as an import step, its shipped template is copied into the org, loads a Giving object
 * and names only columns the step reads, and both recurring steps make recurring commitments.
 * NPSP itself is not needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:NpspGivingKit, ApexClass:MigrationKitService')
private class NpspGivingKitTest {
	private static final String KIT = 'NPSP_Giving_Setup';
	private static final Map<String, String> TARGET_BY_STEP = new Map<String, String>{
		'funds' => 'Fund__c',
		'levels' => 'Donor_Level__c',
		'recurringPeople' => 'Commitment__c',
		'recurringOrganizations' => 'Commitment__c'
	};

	@IsTest
	static void eachStepHasItsTemplateAndLoadsItsGivingObject() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(KIT);
			ImportTemplateService.materializeDefaults();
			for (String key : TARGET_BY_STEP.keySet()) {
				MigrationKitService.Step step = MigrationKitService.stepNamed(kit, key);
				Assert.areEqual(MigrationKitService.KIND_IMPORT, step.kind, key + ' loads');
				Import_Template__c template = [
					SELECT Column_Mapping_JSON__c, Target_Object__c
					FROM Import_Template__c
					WHERE Template_Key__c = :step.templateKey
					WITH SYSTEM_MODE
				];
				Assert.isTrue(
					template.Target_Object__c.endsWith(TARGET_BY_STEP.get(key)),
					key + ' loads ' + TARGET_BY_STEP.get(key)
				);
				ImportMapping mapping = ImportMapping.parse(template.Column_Mapping_JSON__c);
				for (ImportMapping.Column column : mapping.getColumns()) {
					String heading = column.getSource();
					Assert.isTrue(
						step.fields.contains(heading) || heading == NpspGivingKit.START_COLUMN,
						key + ' maps only what it reads: ' + heading
					);
				}
				if (key.startsWith('recurring')) {
					Assert.isTrue(
						template.Column_Mapping_JSON__c.contains('Record.Donor_'),
						key + ' names the donor'
					);
				}
			}
		}
	}

	@IsTest
	static void aRecurringDonationStartsAtItsNextPayment() {
		Date established = Date.newInstance(2019, 1, 15);
		Date nextPayment = Date.newInstance(2026, 12, 15);
		Assert.areEqual('2026-12-15', NpspGivingKit.startOf(nextPayment, established), 'next');
		Assert.areEqual('2019-01-15', NpspGivingKit.startOf(null, established), 'closed one');
		Assert.areEqual('', NpspGivingKit.startOf(null, null), 'neither');
		NpspGivingKit extension = new NpspGivingKit();
		Assert.isNull(extension.rows('funds', new List<SObject>()), 'default rows');
		Assert.isNull(extension.verify('levels'), 'counts are compared');
	}
}
