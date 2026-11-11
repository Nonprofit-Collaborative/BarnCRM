/**
 * The PMM Migration Kit (MIG-09, canonical model R-MK1): every step reads as a step, its links
 * point at earlier steps, and its shipped template is copied into the org, loads a Programs
 * object, names only columns the step reads, and keeps one row per Id where a later step links
 * to it. PMM itself is not needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:MigrationKitService, ApexClass:ImportTemplateService')
private class PmmMigrationKitTest {
	private static final String KIT = 'PMM_Programs';
	private static final List<String> STEPS = new List<String>{
		'programs',
		'cohorts',
		'services',
		'enrollments',
		'deliveries'
	};

	@IsTest
	static void eachStepHasItsTemplateAndLinksBackwards() {
		System.runAs(TestUsers.adminWith('Programs_Admin')) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(KIT);
			ImportTemplateService.materializeDefaults();
			Set<String> earlier = new Set<String>();
			for (String key : STEPS) {
				MigrationKitService.Step step = MigrationKitService.stepNamed(kit, key);
				Assert.areEqual(MigrationKitService.KIND_IMPORT, step.kind, key + ' loads');
				for (
					MigrationKitService.Link link : step.links == null
						? new List<MigrationKitService.Link>()
						: step.links
				) {
					Assert.isTrue(earlier.contains(link.step), key + ' links an earlier step');
					Assert.isTrue(step.fields.contains(link.column), key + ' reads the column');
				}
				earlier.add(key);
				Import_Template__c template = [
					SELECT Column_Mapping_JSON__c, Target_Object__c
					FROM Import_Template__c
					WHERE Template_Key__c = :step.templateKey
					WITH SYSTEM_MODE
				];
				Assert.isTrue(
					template.Target_Object__c.endsWith('__c'),
					key + ' loads one Programs object'
				);
				ImportMapping mapping = ImportMapping.parse(template.Column_Mapping_JSON__c);
				for (ImportMapping.Column column : mapping.columns) {
					Assert.isTrue(
						column.source == 'Id' || step.fields.contains(column.source),
						key + ' maps only what it reads: ' + column.source
					);
				}
				// Every step but the last is linked to by a later one.
				if (key != 'deliveries') {
					Assert.areEqual(
						new List<String>{ 'Id' },
						mapping.uniqueBy,
						key + ' keeps one row per Id, so later steps find what it made'
					);
				}
			}
		}
	}
}
