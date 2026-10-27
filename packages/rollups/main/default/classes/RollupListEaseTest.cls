/**
 * The rollup list's plain sentence (U1), recalculation status (U6) and conflicts (U7), from the
 * Apex side. Core holds no giving objects, so organizations count their child organizations
 * (`ParentId`) into Account fields, as the Builder's own tests do.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(
    testFor='ApexClass:RollupSentence, ApexClass:RollupStatus, ApexClass:RollupConflicts, ApexClass:RollupController'
)
private class RollupListEaseTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static Integer fakeIds = 0;

    /** An unsaved definition with an Id, so pairs can be compared without the save's checks. */
    private static Rollup_Definition__c rollup(String name, String targetField, Boolean active) {
        fakeIds++;
        String prefix = Rollup_Definition__c.SObjectType.getDescribe().getKeyPrefix();
        return new Rollup_Definition__c(
            Id = Id.valueOf(prefix + String.valueOf(fakeIds).leftPad(12, '0')),
            Name = name,
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = targetField,
            Mode__c = RollupService.MODE_BOTH,
            Active__c = active
        );
    }

    private static String nameIs(String value) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Name',
                        'operator' => 'equals',
                        'value' => value
                    }
                }
            }
        );
    }

    private static String label(Schema.SObjectField field) {
        return field.getDescribe().getLabel();
    }

    // -------------------------------------------------------------------------------- sentence

    @IsTest
    static void aCountReadsAsASentenceByLabels() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            String sentence = RollupSentence.of(rollup('Children', 'Member_Count__c', true));

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_SentenceRecords,
                    new List<String>{
                        Label.Core_RollupEase_CalcCount,
                        Account.SObjectType.getDescribe().getLabelPlural(),
                        label(Account.ParentId).removeEndIgnoreCase(' ID'),
                        label(Account.Member_Count__c),
                        Account.SObjectType.getDescribe().getLabel()
                    }
                ),
                sentence,
                'U1: labels, never API names'
            );
        }
    }

    @IsTest
    static void aSumNamesItsFieldAndWhatLimitsTheRecords() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c definition = rollup('Staff', 'AnnualRevenue', true);
            definition.Aggregate__c = 'SUM';
            definition.Source_Field__c = 'NumberOfEmployees';
            definition.Filter_JSON__c = nameIs('A');
            definition.Fiscal_Year_Aware__c = true;
            definition.Fiscal_Year_Offset__c = -1;
            definition.Row_Limit__c = 3;

            String sentence = RollupSentence.of(definition);

            System.Assert.isTrue(
                sentence.startsWith(
                    String.format(
                        Label.Core_RollupEase_CalcSum,
                        new List<String>{ label(Account.NumberOfEmployees) }
                    )
                ),
                sentence
            );
            System.Assert.isTrue(sentence.contains(Label.Core_RollupEase_SentenceConditions));
            System.Assert.isTrue(sentence.contains(Label.Core_RollupEase_SentenceLastYear));
            System.Assert.isTrue(
                sentence.contains(
                    String.format(
                        Label.Core_RollupEase_SentenceLimit,
                        new List<String>{ (3).format() }
                    )
                )
            );
        }
    }

    @IsTest
    static void aHouseholdPathAndAnUnknownObjectStillRead() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            String household = RollupSentence.linkOf(
                Account.SObjectType,
                'Primary_Contact__c > ' + RollupPath.TOKEN_HOUSEHOLD
            );
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_LinkHousehold,
                    new List<String>{ label(Account.Primary_Contact__c).removeEndIgnoreCase(' ID') }
                ),
                household
            );
            Rollup_Definition__c gone = rollup('Gone', 'Total__c', true);
            gone.Source_Object__c = 'Not_An_Object__c';
            gone.Target_Object__c = 'Not_An_Object__c';
            String sentence = RollupSentence.of(gone);
            System.Assert.isTrue(sentence.contains('Not_An_Object__c'), 'Named by its API name');
            System.Assert.isTrue(sentence.contains('Total__c'), sentence);
            System.Assert.areEqual('MEDIAN', RollupSentence.calculation('MEDIAN', 'Amount'));
        }
    }

    // ---------------------------------------------------------------------------------- status

    @IsTest
    static void eachStateSaysWhereTheRecalculationStands() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c active = rollup('On', 'Member_Count__c', true);
            System.Assert.areEqual(
                RollupStatus.LEVEL_OFF,
                RollupStatus.stateOf(rollup('Off', 'Member_Count__c', false), true, 5, 5).level
            );
            RollupStatus.State failed = RollupStatus.stateOf(active, true, 5, 2);
            System.Assert.areEqual(RollupStatus.LEVEL_FAILED, failed.level, 'Failures come first');
            System.Assert.areEqual(
                String.format(Label.Core_RollupEase_StatusFailed, new List<String>{ (2).format() }),
                failed.text
            );
            System.Assert.areEqual(
                RollupStatus.LEVEL_RUNNING,
                RollupStatus.stateOf(active, true, 5, null).level
            );
            System.Assert.areEqual(
                RollupStatus.LEVEL_WAITING,
                RollupStatus.stateOf(active, false, 5, 0).level
            );
            System.Assert.areEqual(
                RollupStatus.LEVEL_CLEAR,
                RollupStatus.stateOf(active, false, null, null).level
            );
        }
    }

    @IsTest
    static void queuedRecordsCountForTheRollupsTheyAreFor() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c named = rollup('Named', 'Member_Count__c', true);
            Rollup_Definition__c other = rollup('Other', 'NumberOfEmployees', true);
            Rollup_Definition__c elsewhere = rollup('Elsewhere', 'Member_Count__c', true);
            elsewhere.Target_Object__c = 'Contact';
            insert new List<Rollup_Queue__c>{
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = 'x',
                    Record_Count__c = 4,
                    Status__c = RollupQueue.STATUS_PENDING,
                    Definition_Ids__c = String.valueOf(named.Id) + ', not an id'
                ),
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = 'y',
                    Record_Count__c = 3,
                    Status__c = RollupQueue.STATUS_PENDING
                ),
                new Rollup_Queue__c(
                    Target_Object__c = 'Account',
                    Record_Ids__c = 'z',
                    Record_Count__c = 2,
                    Status__c = RollupQueue.STATUS_FAILED,
                    Definition_Ids__c = String.valueOf(other.Id)
                )
            };

            Map<Id, RollupStatus.State> states = RollupStatus.of(
                new List<Rollup_Definition__c>{ named, other, elsewhere }
            );

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_StatusWaiting,
                    new List<String>{ (7).format() }
                ),
                states.get(named.Id).text,
                'Its own entry and the one for every rollup on Account'
            );
            System.Assert.areEqual(RollupStatus.LEVEL_FAILED, states.get(other.Id).level);
            System.Assert.areEqual(
                RollupStatus.LEVEL_CLEAR,
                states.get(elsewhere.Id).level,
                'Nothing waits for a rollup on another object'
            );
        }
    }

    // ------------------------------------------------------------------------------- conflicts

    @IsTest
    static void twoActiveRollupsOnOneFieldOverwriteEachOther() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c one = rollup('One', 'Member_Count__c', true);
            Rollup_Definition__c two = rollup('Two', 'member_count__c', true);
            Rollup_Definition__c off = rollup('Off', 'Member_Count__c', false);

            Map<Id, List<String>> found = RollupConflicts.of(
                new List<Rollup_Definition__c>{ one, two, off }
            );

            System.Assert.areEqual(
                String.format(Label.Core_RollupEase_ConflictOverwrites, new List<String>{ 'Two' }),
                found.get(one.Id)[0]
            );
            System.Assert.isTrue(
                found.get(off.Id)
                    .contains(
                        String.format(
                            Label.Core_RollupEase_ConflictBlocked,
                            new List<String>{ 'One' }
                        )
                    ),
                'A rollup switched off says what blocks it'
            );
        }
    }

    @IsTest
    static void differentRecordsAreFineAndTheSameCalculationIsADuplicate() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert new Account(Name = 'Only A');
            Rollup_Definition__c forA = rollup('For A', 'Member_Count__c', true);
            forA.Target_Filter_JSON__c = nameIs('Only A');
            Rollup_Definition__c forB = rollup('For B', 'Member_Count__c', true);
            forB.Target_Filter_JSON__c = nameIs('Only B');
            Rollup_Definition__c copy = rollup('Copy', 'NumberOfEmployees', true);
            copy.Target_Filter_JSON__c = nameIs('Only A');

            Map<Id, List<String>> found = RollupConflicts.of(
                new List<Rollup_Definition__c>{ forA, forB, copy }
            );

            System.Assert.isFalse(found.containsKey(forB.Id), 'No record is both A and B');
            System.Assert.areEqual(
                String.format(Label.Core_RollupEase_ConflictDuplicate, new List<String>{ 'For A' }),
                found.get(copy.Id)[0]
            );
        }
    }

    @IsTest
    static void theActiveSwitchRefusesASecondRollupForTheSameRecords() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c active = rollup('Children', 'Member_Count__c', true);
            Rollup_Definition__c off = rollup('Children again', 'Member_Count__c', false);
            active.Id = null;
            off.Id = null;
            active.Definition_Key__c = 'Test_On';
            off.Definition_Key__c = 'Test_Off';
            insert new List<Rollup_Definition__c>{ active, off };

            String refusal;
            try {
                RollupController.setActive(off.Id, true);
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_ConflictBlocked,
                    new List<String>{ 'Children' }
                ),
                refusal
            );
            System.Assert.isFalse(
                [SELECT Active__c FROM Rollup_Definition__c WHERE Id = :off.Id].Active__c
            );
            RollupController.setActive(active.Id, false);
            RollupController.setActive(off.Id, true);
            System.Assert.isTrue(
                [SELECT Active__c FROM Rollup_Definition__c WHERE Id = :off.Id].Active__c,
                'Once the other is off it switches on'
            );
        }
    }

    // ------------------------------------------------------------------------------------ page

    @IsTest
    static void thePageCarriesTheSentenceStatusAndGroup() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c saved = rollup('Children', 'Member_Count__c', false);
            saved.Id = null;
            saved.Definition_Key__c = 'Test_Children';
            insert saved;

            RollupController.RollupView view = RollupController.getPage().rollups[0];

            System.Assert.areEqual(RollupSentence.of(saved), view.sentence);
            System.Assert.areEqual(
                Account.SObjectType.getDescribe().getLabel(),
                view.targetObjectLabel
            );
            System.Assert.areEqual(RollupStatus.LEVEL_OFF, view.statusLevel);
            System.Assert.isTrue(view.conflicts.isEmpty());
        }
    }
}
