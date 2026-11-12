/**
 * The Outbound Funds kit (MIG-11, canonical model R-MK1): every step reads as an import step
 * whose shipped template is copied into the org, loads the Scholarships object it should and
 * names only columns the step reads (or the parent column the extension adds), and a cycle or
 * award row carries its own Id twice, once to link to its parent. Outbound Funds itself is not
 * needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:OutboundFundsKit, ApexClass:MigrationKitService')
private class OutboundFundsKitTest {
	private static final Map<String, String> TARGET_BY_STEP = new Map<String, String>{
		'programs' => 'Award_Program__c',
		'cycles' => 'Award_Cycle__c',
		'applications' => 'Award_Application__c',
		'awards' => 'Award__c',
		'disbursements' => 'Award_Payment__c',
		'requirements' => 'Award_Requirement__c'
	};

	@IsTest
	static void eachStepHasItsTemplateAndLoadsItsScholarshipsObject() {
		System.runAs(TestUsers.adminWith(ScholarshipsTestData.ADMIN_SET)) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(OutboundFundsKit.KIT);
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
				for (
					ImportMapping.Column column : ImportMapping.parse(
							template.Column_Mapping_JSON__c
						)
						.getColumns()
				) {
					String heading = column.getSource();
					Assert.isTrue(
						step.fields.contains(heading) || heading == OutboundFundsKit.PARENT_COLUMN,
						key + ' maps only what it reads: ' + heading
					);
				}
			}
		}
	}

	@IsTest
	static void aCycleRowKeepsItsIdAndLinksToItsProgram() {
		// runs-as: deploying user (no record is read; an empty page stages no rows)
		OutboundFundsKit extension = new OutboundFundsKit();
		Assert.isNull(extension.rows('programs', new List<SObject>()), 'default rows');
		Assert.isNull(extension.verify('awards'), 'counts are compared');
		Migration_Kit__mdt kit = MigrationKitService.kitNamed(OutboundFundsKit.KIT);
		for (String key : new List<String>{ 'cycles', 'awards' }) {
			MigrationKitService.Step step = MigrationKitService.stepNamed(kit, key);
			Assert.isTrue(
				JSON.serialize(step.links).contains('"' + OutboundFundsKit.PARENT_COLUMN + '"'),
				key + ' links its parent column'
			);
		}
	}
}
