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
		'recurringOrganizations' => 'Commitment__c',
		'planTemplates' => 'Stewardship_Plan_Template__c',
		'planSteps' => 'Stewardship_Plan_Step__c'
	};
	/** Columns the extension adds or the template keys on, beyond the fields a step reads. */
	private static final Set<String> ADDED = new Set<String>{
		NpspGivingKit.START_COLUMN,
		NpspGivingKit.FREQUENCY_COLUMN,
		NpspGivingKit.STATUS_COLUMN,
		'Id',
		'Order',
		'AssignTo'
	};

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

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
						step.fields.contains(heading) || ADDED.contains(heading),
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
		// runs-as: deploying user (text choice only, no record or permission is read)
		String established = '2019-01-15';
		String nextPayment = '2026-12-15';
		Assert.areEqual('2026-12-15', NpspGivingKit.startOf(nextPayment, established), 'next');
		Assert.areEqual('2019-01-15', NpspGivingKit.startOf(null, established), 'closed one');
		Assert.areEqual('', NpspGivingKit.startOf(null, null), 'neither');
		Assert.areEqual('Quarterly', NpspGivingKit.frequencyOf('Monthly', '3'), 'every 3 months');
		Assert.areEqual('Twice a year', NpspGivingKit.frequencyOf('Monthly', '6'), 'every 6');
		Assert.areEqual('Monthly', NpspGivingKit.frequencyOf('Monthly', null), 'every month');
		Assert.areEqual('Weekly', NpspGivingKit.frequencyOf('Weekly', '2'), 'kept');
		NpspGivingKit extension = new NpspGivingKit();
		Assert.isNull(extension.rows('funds', new List<SObject>()), 'default rows');
		Assert.isNull(extension.verify('levels'), 'counts are compared');
	}

	@IsTest
	static void anEngagementPlanTaskGetsOrderAndAssignment() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Map<String, Object> assigned = new Map<String, Object>{
			'npsp.Days_After__c' => '14',
			'npsp.Assigned_To__c' => '005000000000001AAA'
		};
		NpspGivingKit.planStep(assigned);
		Assert.areEqual('14', assigned.get('Order'), 'ordered by days after');
		Assert.areEqual('Specific user', assigned.get('AssignTo'), 'its user');
		Map<String, Object> unassigned = new Map<String, Object>{ 'npsp.Days_After__c' => '' };
		NpspGivingKit.planStep(unassigned);
		Assert.areEqual('0', unassigned.get('Order'), 'no days after');
		Assert.areEqual('Record owner', unassigned.get('AssignTo'), 'the record owner');
	}

	@IsTest
	static void theParityStepCountsNothingWithoutNpsp() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			MigrationKitService.Step step = MigrationKitService.stepNamed(
				MigrationKitService.kitNamed(KIT),
				'parity'
			);
			Assert.areEqual('tool', step.kind, 'a tool step');
			MigrationCheck check = new NpspGivingKit().verify('parity');
			Assert.areEqual(0, check.source, 'no NPSP levels or plans in a test org');
			Assert.areEqual(0, check.done, 'nothing to match');
		}
	}
}
