/**
 * The V4S Migration Kit (MIG-03, canonical model R-MK1): every step reads as a step, its links
 * point at earlier steps, its shipped template is copied into the org and loads a Volunteers
 * object, and a shift's end and status are worked out from the V4S start and length. V4S itself
 * is not needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:V4sMigrationKit')
private class V4sMigrationKitTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Volunteers_Admin');
	}

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
		// runs-as: deploying user (pure date arithmetic, no record or permission is read)
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
	static void theShiftsStepIsRefusedWithoutV4sAndLongShiftsRoundToMinutes() {
		System.runAs(TestUsers.adminWith('Volunteers_Admin')) {
			try {
				Assert.isNotNull(
					new V4sMigrationKit().rows(V4sMigrationKit.SHIFTS, new List<SObject>()),
					'staged'
				);
			} catch (Exception refused) {
				Assert.isTrue(
					refused.getMessage().contains('this org does not have'),
					'names what is missing: ' + refused.getMessage()
				);
			}
		}
		Datetime starts = Datetime.newInstanceGmt(2026, 3, 14, 9, 0, 0);
		Assert.areEqual(
			JSON.serialize(starts.addMinutes(60)).remove('"'),
			V4sMigrationKit.endOf(starts, 0),
			'a zero length is one hour'
		);
		Assert.areEqual(
			JSON.serialize(starts.addMinutes(45)).remove('"'),
			V4sMigrationKit.endOf(starts, 0.75),
			'three quarters of an hour'
		);
		Assert.areEqual('Open', V4sMigrationKit.statusOf(null, starts), 'no start is open');
	}

	@IsTest
	static void shiftRowsGetAnEndAndAStatusFromTheirStartAndLength() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		Datetime starts = Datetime.newInstanceGmt(2026, 3, 14, 9, 0, 0);
		List<Map<String, Object>> rows = new List<Map<String, Object>>{
			new Map<String, Object>{
				'GW_Volunteers.Start_Date_Time__c' => JSON.serialize(starts).remove('"'),
				'GW_Volunteers.Duration__c' => '2'
			},
			new Map<String, Object>{
				'GW_Volunteers.Start_Date_Time__c' => '',
				'GW_Volunteers.Duration__c' => ''
			}
		};
		V4sMigrationKit.shapeShifts(rows);
		Assert.areEqual(
			JSON.serialize(starts.addMinutes(120)).remove('"'),
			rows[0].get(V4sMigrationKit.END_COLUMN),
			'a two hour shift'
		);
		Assert.areEqual('Completed', rows[0].get(V4sMigrationKit.STATUS_COLUMN), 'long past');
		Assert.areEqual('', rows[1].get(V4sMigrationKit.END_COLUMN), 'no start, no end');
		Assert.areEqual('Open', rows[1].get(V4sMigrationKit.STATUS_COLUMN), 'no start is open');
	}

	@IsTest
	static void otherStepsKeepTheDefaultRowsAndTheKitHasNoCheckOfItsOwn() {
		// runs-as: deploying user (returns before any record or permission is read)
		V4sMigrationKit extension = new V4sMigrationKit();
		Assert.isNull(extension.rows('jobs', new List<SObject>()), 'default rows');
		Assert.isNull(extension.verify('hours'), 'counts are compared');
	}
}
