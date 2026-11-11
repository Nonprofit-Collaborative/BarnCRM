/**
 * The V4S Migration Kit (MIG-03, canonical model R-MK1): every step reads as a step, its links
 * point at earlier steps, its shipped template is copied into the org and loads a Volunteers
 * object, and a shift's end and status are worked out from the V4S start and length. V4S itself
 * is not needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:V4sMigrationKit')
private class V4sMigrationKitTest {
	private static final List<String> STEPS = new List<String>{
		'jobs',
		'shifts',
		'signups',
		'hours'
	};

	@IsTest
	static void eachStepHasItsTemplateAndLinksBackwards() {
		System.runAs(TestUsers.adminWith('Volunteers_Admin')) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(V4sMigrationKit.KIT);
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
					template.Target_Object__c.startsWith('Volunteer_'),
					key + ' loads one Volunteers object'
				);
				Set<String> extra = key == V4sMigrationKit.SHIFTS
					? new Set<String>{ V4sMigrationKit.END_COLUMN, V4sMigrationKit.STATUS_COLUMN }
					: new Set<String>();
				for (
					ImportMapping.Column column : ImportMapping.parse(
							template.Column_Mapping_JSON__c
						)
						.getColumns()
				) {
					String heading = column.getSource();
					Assert.isTrue(
						extra.contains(heading) || step.fields.contains(heading),
						key + ' maps only what it reads: ' + heading
					);
				}
			}
		}
	}

	@IsTest
	static void aShiftEndsItsLengthAfterItStartsAndIsCompletedOnceStarted() {
		Datetime starts = Datetime.newInstanceGmt(2026, 3, 14, 9, 0, 0);
		Assert.areEqual(
			JSON.serialize(starts.addMinutes(150)).remove('"'),
			V4sMigrationKit.endOf(starts, 2.5),
			'two and a half hours'
		);
		Assert.areEqual(
			JSON.serialize(starts.addMinutes(60)).remove('"'),
			V4sMigrationKit.endOf(starts, null),
			'a shift with no length is one hour'
		);
		Assert.areEqual('', V4sMigrationKit.endOf(null, 2), 'no start, no end');
		Assert.areEqual(
			'Completed',
			V4sMigrationKit.statusOf(starts, starts.addDays(1)),
			'past shift'
		);
		Assert.areEqual('Open', V4sMigrationKit.statusOf(starts, starts.addDays(-1)), 'future');
	}

	@IsTest
	static void otherStepsKeepTheDefaultRowsAndTheKitHasNoCheckOfItsOwn() {
		V4sMigrationKit extension = new V4sMigrationKit();
		Assert.isNull(extension.rows('jobs', new List<SObject>()), 'default rows');
		Assert.isNull(extension.verify('hours'), 'counts are compared');
	}
}
