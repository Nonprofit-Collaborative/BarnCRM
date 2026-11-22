/**
 * The Off Platform destination of an archive rule (R-SQ17, R-SQ18, ADR-0240): offered only while a
 * module's backup destination is installed, refused with the reason otherwise, and an archive
 * started through it is an Archive by Query whose file goes off platform.
 */
@IsTest(testFor='ApexClass:OffPlatformArchiveDestination')
private class OffPlatformArchiveDestinationTest {
	@TestSetup
	// runs-as: deploying user (creates the test users themselves)
	static void createUsers() {
		TestUsers.admin();
		archivist();
	}

	private static final String VOLUNTEERS = JSON.serialize(
		new Map<String, Object>{
			'version' => 1,
			'object' => 'Contact',
			'fields' => new List<Object>{ 'LastName' },
			'filter' => new Map<String, Object>{
				'version' => 1,
				'conditions' => new List<Object>{
					new Map<String, Object>{
						'id' => 1,
						'field' => 'Title',
						'operator' => 'equals',
						'value' => 'Volunteer'
					}
				}
			}
		}
	);

	private static User archivist() {
		return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' });
	}

	/** Stands in for a module's ready destination. */
	private class ReadyDestination implements OffPlatformDestination {
		public String key() {
			return OffPlatformSendBatch.OFF_PLATFORM;
		}
		public String notReady() {
			return null;
		}
		public String send(String fileName, Blob body) {
			return null;
		}
		public Integer partChars() {
			return null;
		}
	}

	@IsTest
	static void withoutADestinationTheChoiceIsRefusedWithTheReason() {
		System.runAs(archivist()) {
			ModuleExtensions.stubForTest(OffPlatformDestination.class, 'Connector', null, true);
			OffPlatformArchiveDestination destination = new OffPlatformArchiveDestination();
			System.Assert.areEqual(ArchiveRules.OFF_PLATFORM, destination.key(), 'Its key');
			String reason = destination.unavailableReason();
			System.Assert.areEqual(
				BarnHelp.text('Core', 'Core_ArchiveRules_OffPlatformMissing'),
				reason,
				'Says no destination is installed'
			);
			try {
				destination.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 1));
				System.Assert.fail('A run without a destination is refused');
			} catch (ArchiveRules.ArchiveRuleException expected) {
				System.Assert.areEqual(reason, expected.getMessage(), 'With the same reason');
			}
			System.Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c WITH SYSTEM_MODE], 'No job started');
		}
	}

	@IsTest
	static void withADestinationAnArchiveByQueryStartsForOffPlatform() {
		System.runAs(TestUsers.admin()) {
			DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
			insert TestDataFactory.person(new Contact(LastName = 'Archived One', Title = 'Volunteer'));
		}
		System.runAs(archivist()) {
			ModuleExtensions.stubForTest(OffPlatformDestination.class, 'Connector', new ReadyDestination(), true);
			OffPlatformArchiveDestination destination = new OffPlatformArchiveDestination();
			System.Assert.isNull(destination.unavailableReason(), 'Offered while ready');
			Import_Batch__c job = destination.start(new ArchiveRun(null, 'Old Volunteers', VOLUNTEERS, 'Contact', 1));
			System.Assert.isNotNull(job.Id, 'A job is saved');
			Import_Batch__c saved = [SELECT Operation_JSON__c FROM Import_Batch__c WHERE Id = :job.Id WITH SYSTEM_MODE];
			System.Assert.isTrue(
				saved.Operation_JSON__c.contains(OffPlatformSendBatch.OFF_PLATFORM),
				'The file goes off platform: ' + saved.Operation_JSON__c
			);
		}
	}
}
