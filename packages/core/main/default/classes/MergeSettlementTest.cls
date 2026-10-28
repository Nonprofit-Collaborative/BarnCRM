/**
 * The tidy-up after a Salesforce merge (PEOPLE-15): the platform moves the children without
 * running their triggers, and this settles the survivors once the merge is saved.
 */
@IsTest(testFor='ApexClass:MergeSettlement')
private class MergeSettlementTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String ADDRESS_PROPAGATION = 'Address_Default_Propagation';

    /** Both sides of each relationship are written here, so the automation is stood down. */
    private static void insertRelationships(List<Relationship__c> rows) {
        AutomationControl.bypass(RelationshipService.AUTOMATION_NAME);
        AutomationControl.bypass(RelationshipService.VALIDATION_AUTOMATION_NAME);
        insert rows;
        AutomationControl.clearBypass(RelationshipService.AUTOMATION_NAME);
        AutomationControl.clearBypass(RelationshipService.VALIDATION_AUTOMATION_NAME);
    }

    private static Address__c defaultAddress(Id contactId, String street, String city) {
        return new Address__c(
            Contact__c = contactId,
            Street__c = street,
            City__c = city,
            Type__c = 'Home',
            Is_Default__c = true
        );
    }

    @IsTest
    static void aNativeHouseholdMergeRecountsAndRenamesTheSurvivor() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account kept = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account other = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert new List<Account>{ kept, other };
            insert new List<Contact>{
                AddressTestDataFactory.newContact('Maria', 'Garcia', kept.Id),
                AddressTestDataFactory.newContact('Wei', 'Lee', other.Id)
            };

            Test.startTest();
            Database.merge(new Account(Id = kept.Id), other.Id);
            Test.stopTest();

            Account saved = [SELECT Name, Member_Count__c FROM Account WHERE Id = :kept.Id];
            Assert.areEqual(2, saved.Member_Count__c, 'Both people are counted');
            Assert.isTrue(
                saved.Name.contains('Lee'),
                'The name takes in the newcomer: ' + saved.Name
            );
        }
    }

    @IsTest
    static void aContactMergeLeavesOneDefaultNoSelfRelationshipAndOnePrimary() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact kept = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact other = HouseholdTestDataFactory.newContact('Ms.', 'Mary', 'Garcia');
            Contact friend = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ kept, other, friend };
            insert defaultAddress(kept.Id, '1 Main Street', 'Oakland');
            insert defaultAddress(other.Id, '2 Oak Avenue', 'Berkeley');
            insertRelationships(
                new List<Relationship__c>{
                    RelationshipTestDataFactory.between(kept, other, 'Sibling'),
                    RelationshipTestDataFactory.between(other, kept, 'Sibling'),
                    RelationshipTestDataFactory.between(kept, friend, 'Friend'),
                    RelationshipTestDataFactory.between(friend, kept, 'Friend'),
                    RelationshipTestDataFactory.between(other, friend, 'Friend'),
                    RelationshipTestDataFactory.between(friend, other, 'Friend')
                }
            );
            List<Account> orgs = RelationshipTestDataFactory.organizations(2, 'Employer');
            Affiliation__c first = RelationshipTestDataFactory.affiliation(kept, orgs[0], 'Staff');
            first.Is_Primary__c = true;
            insert first;
            Affiliation__c second = RelationshipTestDataFactory.affiliation(
                other,
                orgs[1],
                'Staff'
            );
            second.Is_Primary__c = true;
            insert second;

            Test.startTest();
            Database.merge(new Contact(Id = kept.Id), other.Id);
            Test.stopTest();

            List<Address__c> defaults = [
                SELECT City__c
                FROM Address__c
                WHERE Contact__c = :kept.Id AND Is_Default__c = TRUE
            ];
            Assert.areEqual(1, defaults.size(), 'One default address');
            Assert.areEqual(
                'Oakland',
                defaults[0].City__c,
                'The one in the kept person\'s mailing address'
            );
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Address__c WHERE Contact__c = :kept.Id],
                'The other address stays as an ordinary one'
            );
            Integer selfRows = 0;
            Integer toFriend = 0;
            Integer fromFriend = 0;
            for (Relationship__c row : RelationshipTestDataFactory.allRelationships()) {
                if (row.Contact__c == kept.Id && row.Related_Contact__c == kept.Id) {
                    selfRows++;
                } else if (row.Contact__c == kept.Id && row.Related_Contact__c == friend.Id) {
                    toFriend++;
                } else if (row.Contact__c == friend.Id && row.Related_Contact__c == kept.Id) {
                    fromFriend++;
                }
            }
            Assert.areEqual(0, selfRows, 'Nobody is related to themselves');
            Assert.areEqual(1, toFriend, 'One friendship from the kept person');
            Assert.areEqual(1, fromFriend, 'And one back');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Affiliation__c
                    WHERE Contact__c = :kept.Id AND Is_Primary__c = TRUE
                ],
                'One primary affiliation'
            );
        }
    }

    @IsTest
    static void twoHundredSurvivorsEachKeepOneDefault() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');
            insert people;
            List<Address__c> addresses = new List<Address__c>();
            for (Contact person : people) {
                addresses.add(defaultAddress(person.Id, '1 Main Street', 'Oakland'));
                addresses.add(defaultAddress(person.Id, '2 Oak Avenue', 'Berkeley'));
            }
            // Two defaults each, as a merge leaves them: the rule that keeps one is stood down.
            AutomationControl.bypass(ADDRESS_PROPAGATION);
            insert addresses;
            AutomationControl.clearBypass(ADDRESS_PROPAGATION);
            Set<Id> survivors = new Map<Id, Contact>(people).keySet();

            Test.startTest();
            new MergeSettlement(new Set<Id>(), survivors, survivors).execute(null);
            Test.stopTest();

            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Contact__c IN :survivors AND Is_Default__c = TRUE
                ],
                'Every survivor keeps exactly one default'
            );
        }
    }

    @IsTest
    static void aHouseholdMergeLeavesOnePersonOneMembershipAndTheRightCount() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account kept = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account other = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert new List<Account>{ kept, other };
            Contact both = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact onlyOther = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ both, onlyOther };
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = kept.Id,
                    Contact__c = both.Id,
                    Start_Date__c = Date.today().addDays(-10)
                ),
                new Household_Member__c(
                    Household__c = other.Id,
                    Contact__c = both.Id,
                    Is_Primary__c = true,
                    Start_Date__c = Date.today().addDays(-5)
                ),
                new Household_Member__c(
                    Household__c = other.Id,
                    Contact__c = onlyOther.Id,
                    Start_Date__c = Date.today().addDays(-5)
                )
            };

            Test.startTest();
            Database.merge(new Account(Id = kept.Id), other.Id);
            Test.stopTest();

            List<Household_Member__c> rows = [
                SELECT Contact__c, Is_Primary__c, Start_Date__c
                FROM Household_Member__c
                WHERE Household__c = :kept.Id AND Contact__c = :both.Id
            ];
            Assert.areEqual(1, rows.size(), 'The person has one membership in the survivor');
            Assert.areEqual(
                Date.today().addDays(-5),
                rows[0].Start_Date__c,
                'The primary row is the one kept'
            );
            Assert.isTrue(rows[0].Is_Primary__c, 'Primary carries onto the kept row');
            Assert.areEqual(
                2,
                [SELECT Member_Count__c FROM Account WHERE Id = :kept.Id][0].Member_Count__c,
                'Two people, each counted once'
            );
        }
    }

    @IsTest
    static void twoHundredHouseholdsEachKeepOneMembershipPerPerson() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                households.add(HouseholdTestDataFactory.newHousehold('Bulk Family ' + i));
            }
            insert households;
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');
            insert people;
            List<Household_Member__c> rows = new List<Household_Member__c>();
            for (Integer i = 0; i < 200; i++) {
                for (Integer copy = 0; copy < 2; copy++) {
                    rows.add(
                        new Household_Member__c(
                            Household__c = households[i].Id,
                            Contact__c = people[i].Id,
                            Is_Primary__c = copy == 1,
                            Start_Date__c = Date.today().addDays(-copy)
                        )
                    );
                }
            }
            // Two rows each, as a merge leaves them: the upkeep on the rows is stood down.
            AutomationControl.bypass('HouseholdMemberTriggerHandler');
            insert rows;
            AutomationControl.clearBypass('HouseholdMemberTriggerHandler');
            Set<Id> householdIds = new Map<Id, Account>(households).keySet();

            Test.startTest();
            new MergeSettlement(householdIds, new Set<Id>(), new Set<Id>()).execute(null);
            Test.stopTest();

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Household_Member__c WHERE Household__c IN :householdIds],
                'One membership per person'
            );
            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Household_Member__c
                    WHERE Household__c IN :householdIds AND Is_Primary__c = TRUE
                ],
                'The primary flag survives on each kept row'
            );
        }
    }

    @IsTest
    static void aPartThatFailsDoesNotStopTheOthersOrTheNextAttempt() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact kept = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert kept;
            AutomationControl.bypass(ADDRESS_PROPAGATION);
            insert new List<Address__c>{
                defaultAddress(kept.Id, '1 Main Street', 'Oakland'),
                defaultAddress(kept.Id, '2 Oak Avenue', 'Berkeley')
            };
            AutomationControl.clearBypass(ADDRESS_PROPAGATION);
            insertRelationships(
                new List<Relationship__c>{
                    RelationshipTestDataFactory.between(kept, kept, 'Friend')
                }
            );
            Set<Id> ids = new Set<Id>{ kept.Id };

            Test.startTest();
            Test.setReadOnlyApplicationMode(true);
            new MergeSettlement(new Set<Id>(), ids, ids).execute(null);
            Test.setReadOnlyApplicationMode(false);
            Test.stopTest();

            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Contact__c = :kept.Id AND Is_Default__c = TRUE
                ],
                'Where nothing can be saved, nothing is changed and nothing is thrown'
            );
            Assert.areEqual(
                1,
                RelationshipTestDataFactory.allRelationships().size(),
                'The self relationship is still there'
            );

            new MergeSettlement(new Set<Id>(), ids, ids).execute(null);

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Contact__c = :kept.Id AND Is_Default__c = TRUE
                ],
                'The next attempt settles the address'
            );
            Assert.areEqual(
                0,
                RelationshipTestDataFactory.allRelationships().size(),
                'And the self relationship'
            );
        }
    }

    private class Idle implements Queueable {
        public void execute(QueueableContext context) {
            return;
        }
    }

    /** Runs afterMerge from inside a Queueable, where the one chained job is not ours to take. */
    private class MergesInsideAQueueable implements Queueable {
        private final Id survivorId;

        MergesInsideAQueueable(Id survivorId) {
            this.survivorId = survivorId;
        }

        public void execute(QueueableContext context) {
            MergeSettlement.afterMerge(new Set<Id>(), new Set<Id>{ survivorId }, new Set<Id>());
            queuedInsideTheJob = Limits.getQueueableJobs();
        }
    }

    /** The jobs the Queueable above had queued once the merge's tidy-up was asked for. */
    private static Integer queuedInsideTheJob;

    private static List<Error_Log__c> settlementWarnings() {
        return [
            SELECT Message__c, Severity__c
            FROM Error_Log__c
            WHERE Context__c = :Label.Core_Households_ErrorContextMergeSettle
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void nothingToSettleQueuesNothing() {
        System.runAs(TestUsers.admin()) {
            MergeSettlement.afterMerge(new Set<Id>(), new Set<Id>(), new Set<Id>());

            Assert.isNull(MergeSettlement.lastQueued, 'No survivors, no job');
            Assert.areEqual(0, Limits.getQueueableJobs());
        }
    }

    @IsTest
    static void aMergeWithNoQueueableJobsLeftPublishesItsSurvivors() {
        System.runAs(TestUsers.admin()) {
            Contact survivor = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert survivor;
            Test.startTest();
            for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {
                System.enqueueJob(new Idle());
            }

            MergeSettlement.afterMerge(
                new Set<Id>(),
                new Set<Id>{ survivor.Id },
                new Set<Id>{ survivor.Id }
            );
            Test.stopTest();

            Assert.isTrue(
                MergeSettlement.lastQueued.contains(survivor.Id),
                'The subscriber queued the tidy-up once the event was delivered'
            );
            Assert.areEqual(1, MergeSettlement.lastPublished.size(), 'One event names them');
            Assert.areEqual(
                String.valueOf(survivor.Id),
                MergeSettlement.lastPublished[0].Owner_Ids__c,
                'As an owner of addresses'
            );
            Assert.areEqual(
                String.valueOf(survivor.Id),
                MergeSettlement.lastPublished[0].Person_Ids__c,
                'And as a person'
            );
            Assert.isNull(MergeSettlement.lastPublished[0].Household_Ids__c, 'No household');
            Assert.areEqual(0, settlementWarnings().size(), 'Nothing for an administrator to do');
        }
    }

    @IsTest
    static void aMergeInsideAQueueablePublishesAndKeepsItsChain() {
        System.runAs(TestUsers.admin()) {
            Contact survivor = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert survivor;

            Test.startTest();
            System.enqueueJob(new MergesInsideAQueueable(survivor.Id));
            Test.stopTest();

            Assert.areEqual(0, queuedInsideTheJob, 'The running Queueable keeps its chain');
            Assert.areEqual(1, MergeSettlement.lastPublished.size(), 'One event names it');
            Assert.areEqual(
                String.valueOf(survivor.Id),
                MergeSettlement.lastPublished[0].Owner_Ids__c
            );
            Assert.areEqual(0, settlementWarnings().size(), 'No warning: it will be settled');
        }
    }

    @IsTest
    static void aMergeInABackgroundJobIsSettledAfterItCommits() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact kept = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact other = HouseholdTestDataFactory.newContact('Ms.', 'Mary', 'Garcia');
            insert new List<Contact>{ kept, other };
            insert defaultAddress(kept.Id, '1 Main Street', 'Oakland');
            insert defaultAddress(other.Id, '2 Oak Avenue', 'Berkeley');
            insertRelationships(
                new List<Relationship__c>{
                    RelationshipTestDataFactory.between(kept, other, 'Sibling'),
                    RelationshipTestDataFactory.between(other, kept, 'Sibling')
                }
            );

            Test.startTest();
            MergeSettlement.queueableForTest = true;
            Database.merge(new Contact(Id = kept.Id), other.Id);
            MergeSettlement.queueableForTest = null;
            Assert.isNull(MergeSettlement.lastQueued, 'The merge queues nothing itself');
            Assert.areEqual(1, MergeSettlement.lastPublished.size(), 'It publishes one event');
            Test.getEventBus().deliver();
            Assert.isTrue(
                MergeSettlement.lastQueued.contains(kept.Id),
                'The subscriber queues the tidy-up for the survivor'
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Contact__c = :kept.Id AND Is_Default__c = TRUE
                ],
                'One default address'
            );
            Assert.areEqual(
                0,
                RelationshipTestDataFactory.allRelationships().size(),
                'Nobody is related to themselves'
            );
            // The subscriber, and so the job it queues, runs as the Automated Process user;
            // the tidy-up's user mode reads and writes still succeed for it.
            AsyncApexJob job = [
                SELECT CreatedBy.UserType, Status
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'MergeSettlement'
                LIMIT 1
            ];
            Assert.areEqual('AutomatedProcess', job.CreatedBy.UserType, 'Queued by the subscriber');
            Assert.areEqual('Completed', job.Status, 'And it ran to the end');
            Assert.areEqual(0, settlementWarnings().size(), 'Nothing for an administrator to do');
        }
    }

    @IsTest
    static void aHouseholdAndAPersonMergedInABackgroundJobAreSettledAfterItCommits() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account keptHousehold = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account otherHousehold = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert new List<Account>{ keptHousehold, otherHousehold };
            insert new List<Contact>{
                AddressTestDataFactory.newContact('Maria', 'Garcia', keptHousehold.Id),
                AddressTestDataFactory.newContact('Wei', 'Lee', otherHousehold.Id)
            };
            Contact kept = HouseholdTestDataFactory.newContact('Ms.', 'Ana', 'Okafor');
            Contact other = HouseholdTestDataFactory.newContact('Ms.', 'Anna', 'Okafor');
            insert new List<Contact>{ kept, other };
            List<Account> orgs = RelationshipTestDataFactory.organizations(2, 'Employer');
            Affiliation__c first = RelationshipTestDataFactory.affiliation(kept, orgs[0], 'Staff');
            first.Is_Primary__c = true;
            insert first;
            Affiliation__c second = RelationshipTestDataFactory.affiliation(
                other,
                orgs[1],
                'Staff'
            );
            second.Is_Primary__c = true;
            insert second;

            Test.startTest();
            MergeSettlement.queueableForTest = true;
            Database.merge(new Account(Id = keptHousehold.Id), otherHousehold.Id);
            Database.merge(new Contact(Id = kept.Id), other.Id);
            MergeSettlement.queueableForTest = null;
            Test.getEventBus().deliver();
            Test.stopTest();

            Account saved = [
                SELECT Name, Member_Count__c
                FROM Account
                WHERE Id = :keptHousehold.Id
            ];
            Assert.areEqual(2, saved.Member_Count__c, 'Both people are counted');
            Assert.isTrue(saved.Name.contains('Lee'), 'Renamed for the newcomer: ' + saved.Name);
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Affiliation__c
                    WHERE Contact__c = :kept.Id AND Is_Primary__c = TRUE
                ],
                'One primary affiliation'
            );
            Assert.isTrue(
                MergeSettlement.queuedByEvents.containsAll(
                    new Set<Id>{ keptHousehold.Id, kept.Id }
                ),
                'Both were settled through the event'
            );
            for (AsyncApexJob job : [
                SELECT CreatedBy.UserType, Status
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'MergeSettlement'
            ]) {
                Assert.areEqual('AutomatedProcess', job.CreatedBy.UserType);
                Assert.areEqual('Completed', job.Status);
            }
            Assert.areEqual(0, settlementWarnings().size(), 'Nothing for an administrator to do');
        }
    }

    private static List<Contact> peopleNamedInEvents(Integer count) {
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            people.add(HouseholdTestDataFactory.newContact('Ms.', 'Person', 'Number' + i));
        }
        insert people;
        List<Merge_Settlement_Ready__e> events = new List<Merge_Settlement_Ready__e>();
        for (Contact person : people) {
            events.add(
                new Merge_Settlement_Ready__e(
                    Owner_Ids__c = String.valueOf(person.Id),
                    Person_Ids__c = String.valueOf(person.Id)
                )
            );
        }
        EventBus.publish(events);
        return people;
    }

    @IsTest
    static void moreEventsThanJobsLeftAreQueuedOverLaterDeliveries() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Contact> people = peopleNamedInEvents(5);
            MergeSettlement.jobsLeftForTest = 2;

            Test.getEventBus().deliver();
            Assert.areEqual(2, MergeSettlement.queuedByEvents.size(), 'Two jobs fit the first');
            Test.getEventBus().deliver();
            Assert.areEqual(4, MergeSettlement.queuedByEvents.size(), 'The rest are sent again');
            Test.getEventBus().deliver();
            MergeSettlement.jobsLeftForTest = null;
            Test.stopTest();

            Assert.areEqual(
                new Map<Id, Contact>(people).keySet(),
                MergeSettlement.queuedByEvents,
                'Every survivor was queued, none dropped'
            );
            Assert.areEqual(0, settlementWarnings().size(), 'Nothing for an administrator to do');
        }
    }

    @IsTest
    static void noJobLeftAtAllIsRetriedThenNamedInTheErrorLog() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Contact> people = peopleNamedInEvents(1);
            MergeSettlement.jobsLeftForTest = 0;
            MergeSettlement.retriesForTest = 0;
            Test.getEventBus().deliver();
            Assert.areEqual(0, settlementWarnings().size(), 'A first failure asks again');
            MergeSettlement.retriesForTest = 8;
            Test.getEventBus().deliver();
            Test.getEventBus().deliver();
            Test.stopTest();

            Assert.isTrue(
                MergeSettlement.queuedByEvents == null || MergeSettlement.queuedByEvents.isEmpty(),
                'Nothing could be queued'
            );
            List<Error_Log__c> warnings = settlementWarnings();
            Assert.areEqual(1, warnings.size(), 'Named once, after the last retry');
            Assert.isTrue(
                warnings[0].Message__c.contains(String.valueOf(people[0].Id)),
                'So an administrator can check them: ' + warnings[0].Message__c
            );
        }
    }

    @IsTest
    static void manySurvivorsArePublishedTwoHundredToAnEvent() {
        System.runAs(TestUsers.admin()) {
            String prefix = Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getKeyPrefix();
            Set<Id> people = new Set<Id>();
            for (Integer i = 1; i <= 450; i++) {
                people.add(Id.valueOf(prefix + String.valueOf(i).leftPad(12, '0')));
            }
            String accountPrefix = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getKeyPrefix();
            Set<Id> households = new Set<Id>{ Id.valueOf(accountPrefix + '1'.leftPad(12, '0')) };

            MergeSettlement.queueableForTest = true;
            MergeSettlement.afterMerge(households, people, people);

            List<Merge_Settlement_Ready__e> events = MergeSettlement.lastPublished;
            Assert.areEqual(3, events.size(), '450 identifiers make three events');
            Set<Id> carried = new Set<Id>();
            for (Merge_Settlement_Ready__e event : events) {
                List<String> owners = event.Owner_Ids__c.split(',');
                Assert.isTrue(owners.size() <= 200, 'At most 200 to an event');
                Assert.areEqual(event.Owner_Ids__c, event.Person_Ids__c);
                for (String part : owners) {
                    carried.add(Id.valueOf(part));
                }
            }
            Assert.areEqual(people, carried, 'Every survivor is carried once');
            Assert.areEqual(
                String.valueOf(new List<Id>(households)[0]),
                events[0].Household_Ids__c,
                'The household rides in the first event'
            );
            Assert.isNull(events[1].Household_Ids__c, 'And only there');
        }
    }

    @IsTest
    static void aPublishTheOrgRefusesNamesTheSurvivorsInTheErrorLog() {
        System.runAs(TestUsers.admin()) {
            Contact survivor = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert survivor;

            Test.startTest();
            MergeSettlement.queueableForTest = true;
            MergeSettlement.publishFailureForTest = 'Event limit reached';
            MergeSettlement.afterMerge(
                new Set<Id>(),
                new Set<Id>{ survivor.Id },
                new Set<Id>{ survivor.Id }
            );
            Test.stopTest();

            List<Error_Log__c> warnings = settlementWarnings();
            Assert.areEqual(1, warnings.size(), 'The survivors are named once');
            Assert.areEqual(ErrorLogger.SEVERITY_WARNING, warnings[0].Severity__c);
            Assert.isTrue(
                warnings[0].Message__c.contains(String.valueOf(survivor.Id)),
                'So an administrator can check them: ' + warnings[0].Message__c
            );
            Assert.isTrue(
                warnings[0].Message__c.contains('Event limit reached'),
                'With the reason: ' + warnings[0].Message__c
            );
        }
    }

    @IsTest
    static void aPersonAccountSurvivorKeepsTheDefaultInItsMailingAddress() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                // Needs real person accounts; the contact path above runs on every shape.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account kept = personWithMailing('Okafor', '1 Main Street', 'Oakland');
            insert kept;
            Account other = personWithMailing('Lindqvist', '2 Oak Avenue', 'Berkeley');
            insert other;
            List<Address__c> captured = [
                SELECT Id, Person_Account__c
                FROM Address__c
                WHERE
                    Person_Account__c IN :new List<Id>{ kept.Id, other.Id }
                    AND Is_Default__c = TRUE
            ];
            Assert.areEqual(2, captured.size(), 'Each person has a default from their mailing');
            for (Address__c address : captured) {
                if (address.Person_Account__c == kept.Id) {
                    // The other person's default is the newer one, so newest alone would lose.
                    Test.setCreatedDate(address.Id, Datetime.now().addDays(-1));
                }
            }

            Test.startTest();
            Database.merge(kept, other.Id);
            Test.stopTest();

            List<Address__c> defaults = [
                SELECT City__c
                FROM Address__c
                WHERE Person_Account__c = :kept.Id AND Is_Default__c = TRUE
            ];
            Assert.areEqual(1, defaults.size(), 'One default address');
            Assert.areEqual(
                'Oakland',
                defaults[0].City__c,
                'The one in the kept person\'s mailing address, not the newest'
            );
        }
    }

    private static Account personWithMailing(String lastName, String street, String city) {
        Account record = new Account(RecordTypeId = OrgShapeDetector.creatablePersonRecordTypeId());
        record.put('FirstName', 'Pat');
        record.put('LastName', lastName);
        record.put('PersonMailingStreet', street);
        record.put('PersonMailingCity', city);
        record.put('PersonMailingPostalCode', '94612');
        return record;
    }

    @IsTest
    static void aMergeQueuesOneJobNamingItsSurvivors() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact kept = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact other = HouseholdTestDataFactory.newContact('Ms.', 'Mary', 'Garcia');
            insert new List<Contact>{ kept, other };

            Test.startTest();
            Database.merge(new Contact(Id = kept.Id), other.Id);
            Assert.areEqual(
                new Set<Id>{ kept.Id },
                MergeSettlement.lastQueued,
                'The survivor is settled after the merge'
            );
            Test.stopTest();
        }
    }

    /** An event as the platform would deliver it, with the publisher the platform recorded. */
    private static Merge_Settlement_Ready__e deliveredEvent(Id publisherId, Id personId) {
        return (Merge_Settlement_Ready__e) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{
                        'type' => 'Merge_Settlement_Ready__e'
                    },
                    'CreatedById' => publisherId,
                    'Owner_Ids__c' => String.valueOf(personId),
                    'Person_Ids__c' => String.valueOf(personId)
                }
            ),
            Merge_Settlement_Ready__e.class
        );
    }

    @IsTest
    static void readOnlyMayNotPublishTheMergeEvent() {
        System.runAs(TestUsers.admin()) {
            Id readOnlySet = TestUsers.permissionSetsByName(new List<String>{ 'BarnCRM_Read_Only' })
                .get('BarnCRM_Read_Only')
                .Id;
            List<ObjectPermissions> granted = [
                SELECT PermissionsCreate, PermissionsRead
                FROM ObjectPermissions
                WHERE ParentId = :readOnlySet AND SobjectType = 'Merge_Settlement_Ready__e'
                WITH SYSTEM_MODE
            ];
            for (ObjectPermissions row : granted) {
                Assert.isFalse(row.PermissionsCreate, 'Read Only cannot publish it');
                Assert.isFalse(row.PermissionsRead, 'Nor read it');
            }
        }
    }

    @IsTest
    static void onlyRecordsThePublisherMayEditAreSettled() {
        System.runAs(TestUsers.admin()) {
            User reader = TestUsers.minimumAccessUserWith(
                'Reader',
                new List<String>{ 'BarnCRM_Read_Only' }
            );
            Contact person = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert person;

            Test.startTest();
            Set<Id> forReader = MergeSettlement.permittedIds(deliveredEvent(reader.Id, person.Id));
            Set<Id> forAdmin = MergeSettlement.permittedIds(
                deliveredEvent(UserInfo.getUserId(), person.Id)
            );
            Set<Id> forNobody = MergeSettlement.permittedIds(deliveredEvent(null, person.Id));
            Test.stopTest();

            Assert.isTrue(forReader.isEmpty(), 'A publisher who cannot edit it gets nothing');
            Assert.areEqual(new Set<Id>{ person.Id }, forAdmin, 'One who can edit it is trusted');
            Assert.isTrue(forNobody.isEmpty(), 'No publisher is trusted with nothing');
            List<Error_Log__c> warnings = settlementWarnings();
            Assert.areEqual(2, warnings.size(), 'Each refusal is named for an administrator');
            Assert.isTrue(
                warnings[0].Message__c.contains(String.valueOf(person.Id)),
                'Naming the record left alone: ' + warnings[0].Message__c
            );
        }
    }

    @IsTest
    static void anEventPublishedBySomeoneWhoCannotEditQueuesNothing() {
        System.runAs(TestUsers.admin()) {
            User publisher = TestUsers.minimumAccessUserWith(
                'Publisher',
                new List<String>{ 'BarnCRM_Read_Only' }
            );
            Contact person = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert person;

            Test.startTest();
            System.runAs(publisher) {
                // Through the API this is refused for want of Create; Apex may still publish,
                // so the subscriber's own check is what is proven here.
                EventBus.publish(
                    new Merge_Settlement_Ready__e(
                        Owner_Ids__c = String.valueOf(person.Id),
                        Person_Ids__c = String.valueOf(person.Id)
                    )
                );
            }
            Test.getEventBus().deliver();
            Test.stopTest();

            Assert.isTrue(
                MergeSettlement.queuedByEvents == null ||
                !MergeSettlement.queuedByEvents.contains(person.Id),
                'Nothing is settled for records the publisher cannot edit'
            );
        }
    }
}
