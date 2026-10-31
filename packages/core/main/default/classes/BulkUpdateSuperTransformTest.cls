/**
 * Super Transform's entry points on the bulk update controller (C-50): the object picker, the
 * live count against the run limit, and the 25-record preview that marks values the run would
 * leave alone. Start, progress and undo are bulk update's own and tested in
 * BulkUpdateControllerTest.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest(
    testFor='ApexClass:BulkUpdateController, ApexClass:BulkUpdateService, ApexClass:BulkUpdateFields'
)
private class BulkUpdateSuperTransformTest {
    private static final Integer HOW_MANY = 30;
    private static final Integer ALREADY = 4;

    /** 30 people at one organization, four already titled Coordinator, and Maria. */
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
            Account organization = new Account(Name = 'Shelbyville Pantry');
            insert organization;
            List<Contact> people = new List<Contact>();
            for (Integer index = 0; index < HOW_MANY; index++) {
                people.add(
                    new Contact(
                        AccountId = organization.Id,
                        LastName = 'Transformtest ' + index,
                        Title = index < ALREADY ? 'Coordinator' : 'Volunteer'
                    )
                );
            }
            insert people;
            TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
            TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Find_And_Export' });
        }
    }

    private static User named(String firstName) {
        String prefix = 'barn-test.' + firstName.toLowerCase() + '.%';
        return [SELECT Id FROM User WHERE Username LIKE :prefix LIMIT 1];
    }

    /** Contacts whose last name starts with the value, or every contact with no value. */
    private static String query(String objectName, String lastNameStart) {
        Map<String, Object> document = new Map<String, Object>{
            'version' => 1,
            'object' => objectName,
            'fields' => new List<Object>{ 'Id' }
        };
        if (lastNameStart != null) {
            document.put(
                'filter',
                new Map<String, Object>{
                    'version' => 1,
                    'conditions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 1,
                            'field' => 'LastName',
                            'operator' => 'starts with',
                            'value' => lastNameStart
                        }
                    }
                }
            );
        }
        return JSON.serialize(document);
    }

    private static final String SET_COORDINATOR = JSON.serialize(
        new List<Object>{
            new Map<String, Object>{
                'field' => 'Title',
                'action' => 'set',
                'value' => 'Coordinator'
            }
        }
    );

    @IsTest
    static void objectsAreThoseABulkUpdateMayWrite() {
        System.runAs(named('Maria')) {
            Set<String> offered = new Set<String>();
            for (FindController.Option option : BulkUpdateController.getObjects()) {
                offered.add(option.value);
            }
            System.Assert.isTrue(offered.contains('Contact'), 'Contacts may be changed');
            System.Assert.isFalse(
                offered.contains(NamespaceUtil.qualify('Import_Batch__c')),
                'The package keeps its own data jobs'
            );
        }
    }

    @IsTest
    static void countMatchesNowAndZeroIsAnAnswer() {
        System.runAs(named('Maria')) {
            DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
            BulkUpdateController.MatchCount counted = BulkUpdateController.countMatches(
                query('Contact', 'Transformtest')
            );
            System.Assert.areEqual(HOW_MANY, counted.count, 'Every test person matches');
            System.Assert.isFalse(counted.overLimit, 'Within the default run limit');
            System.Assert.areEqual(BulkUpdateService.MAX_RUN_LIMIT, counted.runLimit, 'Default');
            System.Assert.isNotNull(counted.objectLabel, 'Names the object');

            BulkUpdateController.MatchCount none = BulkUpdateController.countMatches(
                query('Contact', 'Nobody by this name')
            );
            System.Assert.areEqual(0, none.count, 'No match is a count, not an error');
            System.Assert.isFalse(none.overLimit, 'Nothing is over the limit');
        }
    }

    @IsTest
    static void countSaysWhenMoreMatchThanOneRunMayChange() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
            settings.Bulk_Update_Run_Limit__c = 10;
            TestDataFactory.saveSettings(settings);
        }
        System.runAs(named('Maria')) {
            BulkUpdateController.MatchCount counted = BulkUpdateController.countMatches(
                query('Contact', 'Transformtest')
            );
            System.Assert.areEqual(10, counted.runLimit, 'The setting');
            System.Assert.isTrue(counted.overLimit, 'Thirty is over ten');
            System.Assert.areEqual(11, counted.count, 'Counted one past the limit, no further');
        }
    }

    @IsTest
    static void previewShowsTwentyFiveAndMarksValuesAlreadyHeld() {
        System.runAs(named('Maria')) {
            DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
            BulkUpdateService.Preview shown = BulkUpdateController.previewSample(
                query('Contact', 'Transformtest'),
                SET_COORDINATOR
            );
            System.Assert.areEqual(HOW_MANY, shown.count, 'The count is of every match');
            System.Assert.areEqual(
                BulkUpdateService.MAX_SAMPLE_SIZE,
                shown.sample.size(),
                'At most 25 shown'
            );
            for (BulkUpdateService.SampleRecord record : shown.sample) {
                BulkUpdateService.FieldChange title = record.changes[0];
                System.Assert.areEqual('Coordinator', title.after, 'The value to set');
                System.Assert.areEqual(
                    'Coordinator'.equals(title.before),
                    title.unchanged,
                    'Unchanged exactly when the record already holds the value'
                );
            }
            System.Assert.areEqual(
                [SELECT COUNT() FROM Contact WHERE Title = 'Coordinator' WITH USER_MODE],
                ALREADY,
                'The preview saved nothing'
            );
        }
    }

    @IsTest
    static void serviceHoldsTheSampleSizeInRange() {
        System.runAs(named('Maria')) {
            DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
            String people = query('Contact', 'Transformtest');
            System.Assert.areEqual(
                BulkUpdateService.MAX_SAMPLE_SIZE,
                BulkUpdateService.preview(people, SET_COORDINATOR, 500).sample.size(),
                'Held at 25'
            );
            System.Assert.areEqual(
                1,
                BulkUpdateService.preview(people, SET_COORDINATOR, 0).sample.size(),
                'At least one'
            );
            System.Assert.areEqual(
                BulkUpdateService.SAMPLE_SIZE,
                BulkUpdateService.preview(people, SET_COORDINATOR).sample.size(),
                'The bulk update panel keeps five'
            );
        }
    }

    @IsTest
    static void bookkeepingObjectsAndBadDocumentsAreRefused() {
        System.runAs(named('Maria')) {
            try {
                BulkUpdateController.countMatches(
                    query(NamespaceUtil.qualify('Import_Batch__c'), null)
                );
                System.Assert.fail('Data jobs cannot be changed');
            } catch (AuraHandledException refused) {
                System.Assert.isFalse(
                    refused.getMessage() == System.Label.Core_BulkUpdate_UnexpectedError,
                    'Refused with a reason the person can act on'
                );
            }
            try {
                BulkUpdateController.previewSample(query('Contact', 'Transformtest'), '[]');
                System.Assert.fail('A preview needs a change');
            } catch (AuraHandledException refused) {
                System.Assert.areEqual(
                    System.Label.Core_BulkUpdate_ErrorNoChanges,
                    refused.getMessage(),
                    'Says to choose a change'
                );
            }
        }
    }

    @IsTest
    static void findAloneOpensNoneOfIt() {
        System.runAs(named('David')) {
            String people = query('Contact', 'Transformtest');
            List<String> refusedCalls = new List<String>();
            try {
                BulkUpdateController.getObjects();
            } catch (AuraHandledException refused) {
                refusedCalls.add(refused.getMessage());
            }
            try {
                BulkUpdateController.countMatches(people);
            } catch (AuraHandledException refused) {
                refusedCalls.add(refused.getMessage());
            }
            try {
                BulkUpdateController.previewSample(people, SET_COORDINATOR);
            } catch (AuraHandledException refused) {
                refusedCalls.add(refused.getMessage());
            }
            System.Assert.areEqual(3, refusedCalls.size(), 'Every entry point refuses');
            for (String message : refusedCalls) {
                System.Assert.areEqual(
                    System.Label.Core_BulkUpdate_ErrorNoPermission,
                    message,
                    'Names the permissions'
                );
            }
        }
    }
}
