/**
 * The tidy-up after a Salesforce merge (PEOPLE-15): the platform moves the children without
 * running their triggers, and this settles the survivors once the merge is saved.
 */
@IsTest
private class MergeSettlementTest {
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
}
