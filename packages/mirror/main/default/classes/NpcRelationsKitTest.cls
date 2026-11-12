/**
 * The Nonprofit Cloud Relationships and Affiliations kit (MIG-02, canonical model R-MK1): both
 * steps read as import steps whose shipped templates are copied into the org, load a Core
 * object and name only columns the step reads or the extension adds; a pair of people held both
 * ways round is copied once; an affiliation with a household or a person account is skipped and
 * its roles read as text. Nonprofit Cloud itself is not needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:NpcRelationsKit, ApexClass:MigrationKitService')
private class NpcRelationsKitTest {
	@IsTest
	static void eachStepHasItsTemplateAndNamesOnlyWhatItReads() {
		System.runAs(TestUsers.admin()) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(NpcRelationsKit.KIT);
			ImportTemplateService.materializeDefaults();
			Map<String, String> targetByStep = new Map<String, String>{
				'relationships' => 'Relationship__c',
				'affiliations' => 'Affiliation__c'
			};
			for (String key : targetByStep.keySet()) {
				MigrationKitService.Step step = MigrationKitService.stepNamed(kit, key);
				Assert.areEqual(MigrationKitService.KIND_IMPORT, step.kind, key + ' loads');
				Import_Template__c template = [
					SELECT Column_Mapping_JSON__c, Target_Object__c
					FROM Import_Template__c
					WHERE Template_Key__c = :step.templateKey
					WITH SYSTEM_MODE
				];
				Assert.isTrue(
					template.Target_Object__c.endsWith(targetByStep.get(key)),
					key + ' loads ' + targetByStep.get(key)
				);
				for (
					ImportMapping.Column column : ImportMapping.parse(
							template.Column_Mapping_JSON__c
						)
						.getColumns()
				) {
					String heading = column.getSource();
					Assert.isTrue(
						step.fields.contains(heading) || heading == 'Role',
						key + ' maps only what it reads: ' + heading
					);
				}
				MigrationCheck check = new NpcRelationsKit().verify(key);
				Assert.areEqual(check.source, check.done, key + ': nothing to copy here');
			}
		}
	}

	@IsTest
	static void aPairHeldBothWaysIsCopiedOnce() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		String ana = '003000000000001AAA';
		String ben = '003000000000002AAA';
		String cara = '003000000000003AAA';
		List<Map<String, Object>> rows = new List<Map<String, Object>>{
			new Map<String, Object>{ 'ContactId' => ana, 'RelatedContactId' => ben },
			new Map<String, Object>{ 'ContactId' => ben, 'RelatedContactId' => ana },
			new Map<String, Object>{ 'ContactId' => cara, 'RelatedContactId' => ana }
		};
		List<Map<String, Object>> kept = NpcRelationsKit.oneSide(
			rows,
			new Set<String>{ ana + ben, ben + ana }
		);
		Assert.areEqual(2, kept.size(), 'Ana and Ben once, Cara and Ana once');
		Assert.areEqual(ana, kept[0].get('ContactId'), 'the side whose person sorts first');
		Assert.areEqual(cara, kept[1].get('ContactId'), 'held one way only');
	}

	@IsTest
	static void anAffiliationWithAHouseholdIsSkipped() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		List<Map<String, Object>> rows = new List<Map<String, Object>>{
			new Map<String, Object>{
				'AccountId' => '001000000000001AAA',
				'Roles' => 'Employee;Board Member'
			},
			new Map<String, Object>{ 'AccountId' => '001000000000002AAA', 'Roles' => null }
		};
		List<Map<String, Object>> kept = NpcRelationsKit.organizations(
			rows,
			new Set<String>{ '001000000000002AAA' }
		);
		Assert.areEqual(1, kept.size(), 'the household is skipped');
		Assert.areEqual('Employee, Board Member', kept[0].get('Role'), 'roles as text');
	}
}
