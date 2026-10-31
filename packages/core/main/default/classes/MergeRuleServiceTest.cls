/**
 * Merge rules (R-DP8): which value wins for each field, the setting for fields with no rule,
 * whole addresses, and the check of a rule saved on the Custom metadata page.
 */
@IsTest(testFor='ApexClass:MergeRuleService')
private class MergeRuleServiceTest {
    private static final String OLD = '2020-01-01T00:00:00.000+0000';
    private static final String LATE = '2024-01-01T00:00:00.000+0000';

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** A person in memory with system dates, which a constructor cannot set. */
    private static Contact person(String created, String modified, Map<String, Object> values) {
        Map<String, Object> raw = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
            'CreatedDate' => created,
            'LastModifiedDate' => modified
        };
        raw.putAll(values);
        return (Contact) JSON.deserialize(JSON.serialize(raw), Contact.class);
    }

    private static Merge_Rule__mdt rule(String fieldName, String ruleName, Boolean active) {
        return new Merge_Rule__mdt(
            Field_Name__c = fieldName,
            Rule__c = ruleName,
            Active__c = active
        );
    }

    private static void useDefault(String ruleName) {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Merge_Default_Rule__c = ruleName;
        HouseholdTestDataFactory.save(settings);
    }

    @IsTest
    static void theDefaultRuleIsNotBlankUntilChanged() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(MergeRuleService.NOT_BLANK, MergeRuleService.defaultRule());
            useDefault('Nonsense');
            Assert.areEqual(MergeRuleService.NOT_BLANK, MergeRuleService.defaultRule());
            useDefault(MergeRuleService.MOST_RECENT);
            Assert.areEqual(MergeRuleService.MOST_RECENT, MergeRuleService.defaultRule());
        }
    }

    @IsTest
    static void notBlankFillsOnlyTheSurvivorsBlanks() {
        System.runAs(TestUsers.admin()) {
            MergeRuleService.rowsForTest = new List<Merge_Rule__mdt>();
            Contact master = person(
                OLD,
                OLD,
                new Map<String, Object>{ 'Email' => 'keep@example.org', 'Title' => null }
            );
            Contact other = person(
                LATE,
                LATE,
                new Map<String, Object>{ 'Email' => 'new@example.org', 'Title' => 'Treasurer' }
            );

            Map<String, Object> won = MergeRuleService.winningValues(
                master,
                other,
                new List<String>{ 'Email', 'Title' }
            );

            Assert.areEqual(new Map<String, Object>{ 'Title' => 'Treasurer' }, won);
        }
    }

    @IsTest
    static void eachRuleChoosesItsValue() {
        System.runAs(TestUsers.admin()) {
            MergeRuleService.rowsForTest = new List<Merge_Rule__mdt>{
                rule('Email', MergeRuleService.MOST_RECENT, true),
                rule('Title', MergeRuleService.OLDEST, true),
                rule('Department', MergeRuleService.MOST_COMPLETE, true),
                rule('Description', MergeRuleService.KEEP_MASTER, true),
                rule('Phone', MergeRuleService.MOST_RECENT, false)
            };
            // The survivor is the newer record here, so Oldest takes the other's value.
            Contact master = person(
                LATE,
                OLD,
                new Map<String, Object>{
                    'Email' => 'old@example.org',
                    'Title' => 'Chair',
                    'Department' => 'Ops',
                    'Description' => null,
                    'Phone' => '1'
                }
            );
            Contact other = person(
                OLD,
                LATE,
                new Map<String, Object>{
                    'Email' => 'new@example.org',
                    'Title' => 'Founder',
                    'Department' => 'Operations',
                    'Description' => 'Notes',
                    'Phone' => '2'
                }
            );

            Map<String, Object> won = MergeRuleService.winningValues(
                master,
                other,
                new List<String>{ 'Email', 'Title', 'Department', 'Description', 'Phone' }
            );

            Assert.areEqual('new@example.org', won.get('Email'), 'Most recent: changed last.');
            Assert.areEqual('Founder', won.get('Title'), 'Oldest record: created first.');
            Assert.areEqual('Operations', won.get('Department'), 'Most complete: the longer.');
            Assert.isFalse(won.containsKey('Description'), 'Keep master keeps even a blank.');
            Assert.isFalse(won.containsKey('Phone'), 'An inactive rule falls back to Not blank.');
        }
    }

    @IsTest
    static void aBlankNeverWinsAndTiesKeepTheSurvivor() {
        System.runAs(TestUsers.admin()) {
            MergeRuleService.rowsForTest = new List<Merge_Rule__mdt>{
                rule('Email', MergeRuleService.MOST_RECENT, true),
                rule('Title', MergeRuleService.MOST_COMPLETE, true)
            };
            Contact master = person(
                OLD,
                OLD,
                new Map<String, Object>{ 'Email' => 'keep@example.org', 'Title' => 'Chair' }
            );
            Contact other = person(
                OLD,
                LATE,
                new Map<String, Object>{ 'Email' => ' ', 'Title' => 'Head' }
            );

            Assert.isTrue(
                MergeRuleService.winningValues(master, other, new List<String>{ 'Email', 'Title' })
                    .isEmpty()
            );
        }
    }

    @IsTest
    static void anAddressMovesWhole() {
        System.runAs(TestUsers.admin()) {
            MergeRuleService.rowsForTest = new List<Merge_Rule__mdt>{
                rule('MailingAddress', MergeRuleService.MOST_RECENT, true)
            };
            Contact master = person(
                OLD,
                OLD,
                new Map<String, Object>{
                    'MailingStreet' => '1 Old Rd',
                    'MailingCity' => 'Oldtown',
                    'MailingPostalCode' => '11111'
                }
            );
            Contact other = person(
                OLD,
                LATE,
                new Map<String, Object>{
                    'MailingStreet' => '2 New St',
                    'MailingCity' => null,
                    'MailingPostalCode' => '22222'
                }
            );

            Map<String, Object> won = MergeRuleService.winningValues(
                master,
                other,
                new List<String>{ 'MailingStreet', 'MailingCity', 'MailingPostalCode' }
            );

            Assert.areEqual('2 New St', won.get('MailingStreet'));
            Assert.isTrue(won.containsKey('MailingCity'), 'The city moves too, even blank.');
            Assert.isNull(won.get('MailingCity'));
            Assert.areEqual('22222', won.get('MailingPostalCode'));
        }
    }

    @IsTest
    static void mergeableFieldsLeaveOutTheHouseholdAndOwner() {
        System.runAs(TestUsers.admin()) {
            List<String> fields = MergeRuleService.mergeableFields();
            Assert.isTrue(fields.contains('Email'));
            Assert.isFalse(fields.contains('AccountId'));
            Assert.isFalse(fields.contains('OwnerId'));
            Assert.isFalse(fields.contains('Name'), 'A compound name is not stored.');
        }
    }

    @IsTest
    static void aPersonWhoCannotEditPeopleHasNoMergeableFields() {
        System.runAs(TestUsers.minimumAccessUserWith('Ruleless', new List<String>())) {
            Assert.isTrue(MergeRuleService.mergeableFields().isEmpty());
        }
    }

    @IsTest
    static void aSaveIsCheckedAgainstPeoplesFields() {
        System.runAs(TestUsers.admin()) {
            MergeRuleService.validate(
                new Map<String, Object>{ 'Field_Name__c' => 'Email', 'Rule__c' => 'Most recent' }
            );
            MergeRuleService.validate(
                new Map<String, Object>{
                    'Field_Name__c' => 'MailingAddress',
                    'Rule__c' => 'Not blank'
                }
            );
            for (
                String refused : new List<String>{
                    'AccountId',
                    'OwnerId',
                    'Not_A_Field__c',
                    'Name',
                    null
                }
            ) {
                try {
                    MergeRuleService.validate(
                        new Map<String, Object>{
                            'Field_Name__c' => refused,
                            'Rule__c' => 'Not blank'
                        }
                    );
                    Assert.fail(refused + ' is refused.');
                } catch (CustomMetadataManagerService.CustomMetadataManagerException expected) {
                    Assert.isTrue(String.isNotBlank(expected.getMessage()));
                }
            }
            try {
                new MergeRuleService.Validator()
                    .validate(
                        new Map<String, Object>{
                            'Field_Name__c' => 'Email',
                            'Rule__c' => 'Coin toss'
                        }
                    );
                Assert.fail('An unknown rule is refused.');
            } catch (CustomMetadataManagerService.CustomMetadataManagerException expected) {
                Assert.areEqual(Label.Core_DuplicateManagement_RuleUnknown, expected.getMessage());
            }
        }
    }

    @IsTest
    static void rulesForManyPairsStayWithinLimits() {
        System.runAs(TestUsers.admin()) {
            MergeRuleService.rowsForTest = new List<Merge_Rule__mdt>{
                rule('Email', MergeRuleService.MOST_RECENT, true)
            };
            List<String> fields = new List<String>{
                'Email',
                'Title',
                'MailingStreet',
                'MailingCity'
            };
            Integer changed = 0;
            for (Integer i = 0; i < 251; i++) {
                Contact master = person(
                    OLD,
                    OLD,
                    new Map<String, Object>{ 'Email' => 'a' + i + '@example.org' }
                );
                Contact other = person(
                    OLD,
                    LATE,
                    new Map<String, Object>{ 'Email' => 'b' + i + '@example.org', 'Title' => 'T' }
                );
                changed += MergeRuleService.winningValues(master, other, fields).size();
            }
            Assert.areEqual(502, changed, 'Each pair takes the newer email and fills the title.');
            Assert.isTrue(Limits.getQueries() < 5, 'Rules cost no query per pair.');
        }
    }
}
