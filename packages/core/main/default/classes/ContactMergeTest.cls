/**
 * A merge of two people with the platform's own merge (C-20, R-DP4). The platform deletes the
 * merged-away person and moves what looked up to them onto the survivor; these tests assert
 * that household membership follows too, and that no household is tidied away by a merge,
 * because what was credited to it would lose its household.
 */
@IsTest(testFor='ApexClass:ContactTriggerHandler')
private class ContactMergeTest {
    private static Id householdOf(Id contactId) {
        return [SELECT AccountId FROM Contact WHERE Id = :contactId].AccountId;
    }

    private static List<Household_Member__c> currentRowsOf(Id contactId) {
        return [
            SELECT Household__c, Is_Primary__c
            FROM Household_Member__c
            WHERE Contact__c = :contactId AND End_Date__c = NULL
        ];
    }

    /** Exactly one current primary member, and the household's Primary Contact names them. */
    private static void assertOnePrimaryMirrored(Id householdId, Id personId) {
        List<Household_Member__c> primaries = [
            SELECT Contact__c
            FROM Household_Member__c
            WHERE
                Household__c = :householdId
                AND Is_Primary__c = TRUE
                AND (End_Date__c = NULL
                OR End_Date__c > TODAY)
        ];
        Assert.areEqual(1, primaries.size(), 'The household keeps exactly one current primary.');
        Assert.areEqual(personId, primaries[0].Contact__c, 'And it is the survivor.');
        Assert.areEqual(
            personId,
            [SELECT Primary_Contact__c FROM Account WHERE Id = :householdId].Primary_Contact__c,
            'Its Primary Contact mirrors the primary member (ADR-0044).'
        );
    }

    private static Decimal memberCount(Id householdId) {
        return [SELECT Member_Count__c FROM Account WHERE Id = :householdId].Member_Count__c;
    }

    @IsTest
    static void inContactModeTheMergedAwayPersonsHouseholdIsKept() {
        System.runAs(TestUsers.admin()) {
            // Delete Empty Households is on: an ordinary delete would tidy the household away.
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Okafor');
            Contact bea = HouseholdTestDataFactory.newContact('Bea', 'Lindqvist');
            insert new List<Contact>{ ana, bea };
            Id survivorHousehold = householdOf(ana.Id);
            Id otherHousehold = householdOf(bea.Id);
            Assert.areNotEqual(survivorHousehold, otherHousehold, 'Each started in a household.');

            Test.startTest();
            Database.merge(ana, bea.Id);
            Test.stopTest();

            Assert.areEqual(
                ana.Id,
                [SELECT MasterRecordId FROM Contact WHERE Id = :bea.Id ALL ROWS].MasterRecordId,
                'Bea was merged into Ana.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :otherHousehold],
                'The emptied household is kept for a person to merge, not tidied away.'
            );
            Assert.areEqual(0, memberCount(otherHousehold), 'And it counts nobody.');
            Assert.areEqual(survivorHousehold, householdOf(ana.Id), 'Ana stays where she was.');
        }
    }

    @IsTest
    static void inJunctionModeTheSurvivorJoinsTheOtherHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account hers = HouseholdTestDataFactory.newHousehold('The Dupmerge Family');
            Account other = HouseholdTestDataFactory.newHousehold('Dupmerge Household');
            insert new List<Account>{ hers, other };
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Okafor');
            Contact bea = HouseholdTestDataFactory.newContact('Bea', 'Lindqvist');
            insert new List<Contact>{ ana, bea };
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = hers.Id,
                    Contact__c = ana.Id,
                    Is_Primary__c = true
                ),
                new Household_Member__c(
                    Household__c = other.Id,
                    Contact__c = bea.Id,
                    Is_Primary__c = true
                )
            };

            Test.startTest();
            Database.merge(ana, bea.Id);
            Test.stopTest();

            Map<Id, Household_Member__c> rowsByHousehold = new Map<Id, Household_Member__c>();
            for (Household_Member__c row : currentRowsOf(ana.Id)) {
                Assert.isFalse(
                    rowsByHousehold.containsKey(row.Household__c),
                    'One row per household, never two.'
                );
                rowsByHousehold.put(row.Household__c, row);
            }
            Assert.areEqual(
                new Set<Id>{ hers.Id, other.Id },
                rowsByHousehold.keySet(),
                'Ana is now in the household Bea was in, as well as her own.'
            );
            Assert.isTrue(rowsByHousehold.get(hers.Id).Is_Primary__c, 'Her own stays primary.');
            Assert.isTrue(
                rowsByHousehold.get(other.Id).Is_Primary__c,
                'Primary is per household (R-M3): Ana takes the primary Bea held there.'
            );
            assertOnePrimaryMirrored(hers.Id, ana.Id);
            assertOnePrimaryMirrored(other.Id, ana.Id);
            Assert.areEqual(1, memberCount(other.Id), 'The other household counts Ana.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c WHERE Contact__c = :bea.Id],
                'Nothing is left pointing at the merged-away person.'
            );
        }
    }

    @IsTest
    static void inJunctionModeTwoPeopleInOneHouseholdBecomeOneMember() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Dupmerge Family');
            insert household;
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Okafor');
            Contact bea = HouseholdTestDataFactory.newContact('Bea', 'Lindqvist');
            insert new List<Contact>{ ana, bea };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = household.Id, Contact__c = ana.Id),
                new Household_Member__c(Household__c = household.Id, Contact__c = bea.Id)
            };

            Test.startTest();
            Database.merge(ana, bea.Id);
            Test.stopTest();

            Assert.areEqual(1, currentRowsOf(ana.Id).size(), 'Ana is in the household once.');
            Assert.areEqual(1, memberCount(household.Id), 'The household counts one person.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :household.Id],
                'The household is kept.'
            );
        }
    }

    @IsTest
    static void inJunctionModeTheSurvivorAlreadyInTheHouseholdBecomesItsPrimary() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Dupmerge Family');
            insert household;
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Okafor');
            Contact bea = HouseholdTestDataFactory.newContact('Bea', 'Lindqvist');
            insert new List<Contact>{ ana, bea };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = household.Id, Contact__c = ana.Id),
                new Household_Member__c(
                    Household__c = household.Id,
                    Contact__c = bea.Id,
                    Is_Primary__c = true
                )
            };

            Test.startTest();
            Database.merge(ana, bea.Id);
            Test.stopTest();

            Assert.areEqual(1, currentRowsOf(ana.Id).size(), 'Ana keeps her one row.');
            assertOnePrimaryMirrored(household.Id, ana.Id);
        }
    }

    @IsTest
    static void inJunctionModeAnEndedRowDoesNotBlockACurrentOne() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Dupmerge Family');
            insert household;
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Okafor');
            Contact bea = HouseholdTestDataFactory.newContact('Bea', 'Lindqvist');
            insert new List<Contact>{ ana, bea };
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = household.Id,
                    Contact__c = ana.Id,
                    Start_Date__c = Date.today().addYears(-3),
                    End_Date__c = Date.today().addYears(-1)
                ),
                new Household_Member__c(
                    Household__c = household.Id,
                    Contact__c = bea.Id,
                    Is_Primary__c = true
                )
            };

            Test.startTest();
            Database.merge(ana, bea.Id);
            Test.stopTest();

            Assert.areEqual(
                1,
                currentRowsOf(ana.Id).size(),
                'Ana is a current member: her old ended row did not count as already belonging.'
            );
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Household_Member__c WHERE Contact__c = :ana.Id],
                'Her ended row is kept as history.'
            );
            assertOnePrimaryMirrored(household.Id, ana.Id);
            Assert.areEqual(1, memberCount(household.Id), 'The household counts one person.');
        }
    }
}
