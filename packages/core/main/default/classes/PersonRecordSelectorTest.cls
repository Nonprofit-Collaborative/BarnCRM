/**
 * Reading a person that the org stores as an account. These tests run on every org shape:
 * where the org does not store people that way, the selector returns nothing rather than
 * failing, which is the behavior Core depends on.
 */
@IsTest
private class PersonRecordSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void nothingIsReadWhenTheOrgDoesNotStorePeopleAsAccounts() {
        System.runAs(TestUsers.admin()) {
            HouseholdService.personAccountOverride = false;
            Account organization = new Account(Name = 'Riverside Community Trust');
            insert organization;

            Test.startTest();
            List<HouseholdService.Person> people = PersonRecordSelector.getPersons(
                new Set<Id>{ organization.Id }
            );
            Test.stopTest();

            Assert.areEqual(0, people.size(), 'The person branch does not run on this org shape');
        }
    }

    @IsTest
    static void anEmptyRequestReadsNothing() {
        System.runAs(TestUsers.admin()) {
            HouseholdService.personAccountOverride = true;
            Assert.areEqual(
                0,
                PersonRecordSelector.getPersons(new Set<Id>()).size(),
                'No ids means no query and no rows'
            );
        }
    }

    /**
     * The upkeep read is what household naming and the member count are built from, and it
     * has to work for a user who holds no packaged permission set at all (ADR-0021).
     *
     * The org shape is declared through personAccountOverride, because a Platform only test
     * org has no person accounts to make. Nothing else is substituted: no declared person
     * stands in for the record, so the query really runs and the flag really comes off the
     * account.
     */
    @IsTest
    static void theUpkeepReadSeesAFieldTheReadingUserCannotRead() {
        System.runAs(TestUsers.admin()) {
            HouseholdService.personAccountOverride = true;
            User staff = HouseholdTestDataFactory.standardUser('upk');
            Account person = new Account(Name = 'Maria Garcia');
            // Saved by the same user who reads it back, so that what this measures is field
            // level access and not the org's sharing model.
            System.runAs(staff) {
                insert person;
            }
            update new Account(Id = person.Id, Deceased__c = true);
            List<HouseholdService.Person> people;

            Test.startTest();
            System.runAs(staff) {
                people = PersonRecordSelector.getPersons(new Set<Id>{ person.Id });
            }
            Test.stopTest();

            Assert.areEqual(1, people.size(), 'The read works for a user with no packaged access');
            Assert.isTrue(people[0].isDeceased, 'And it sees the flag the greetings depend on');
        }
    }

    /**
     * The display read, on the same record and the same user: the field the user cannot
     * read is stripped rather than throwing, so the panel still lists the person.
     *
     * Substitution as above: the org shape only.
     */
    @IsTest
    static void theDisplayReadStripsAFieldTheReadingUserCannotRead() {
        System.runAs(TestUsers.admin()) {
            HouseholdService.personAccountOverride = true;
            User staff = HouseholdTestDataFactory.standardUser('disp');
            Account person = new Account(Name = 'Maria Garcia');
            System.runAs(staff) {
                insert person;
            }
            update new Account(Id = person.Id, Deceased__c = true);
            List<HouseholdService.Person> people;

            Test.startTest();
            System.runAs(staff) {
                people = PersonRecordSelector.getPersonsForDisplay(new Set<Id>{ person.Id });
            }
            Test.stopTest();

            Assert.areEqual(1, people.size(), 'The person is still shown');
            Assert.isFalse(
                people[0].isDeceased,
                'A user with no access to the deceased field is not told that she died'
            );
        }
    }

    @IsTest
    static void aDisplayReadOfNobodyReadsNothing() {
        System.runAs(TestUsers.admin()) {
            HouseholdService.personAccountOverride = true;
            Assert.areEqual(
                0,
                PersonRecordSelector.getPersonsForDisplay(new Set<Id>()).size(),
                'No ids means no query and no rows'
            );
        }
    }

    @IsTest
    static void aRecordIsTurnedIntoAPersonWithoutNamingFieldsThatMayNotExist() {
        System.runAs(TestUsers.admin()) {
            Account record = new Account(Name = 'Maria Garcia');
            insert record;

            Test.startTest();
            HouseholdService.Person person = PersonRecordSelector.toPerson(
                [SELECT Id, Name, Preferred_Name__c, Deceased__c FROM Account WHERE Id = :record.Id]
            );
            Test.stopTest();

            Assert.areEqual(record.Id, person.id, 'The person is the record');
            Assert.areEqual(
                HouseholdService.SOURCE_ACCOUNT,
                person.sourceObject,
                'The person came from an account'
            );
            Assert.isFalse(person.isDeceased, 'A missing or empty flag reads as false');
        }
    }

    @IsTest
    static void anOrganizationIsNeverTakenForAPerson() {
        System.runAs(TestUsers.admin()) {
            Account organization = new Account(Name = 'Riverside Community Trust');
            insert organization;

            Test.startTest();
            Boolean isPerson = PersonRecordSelector.isPersonRecord(organization);
            List<SObject> people = PersonRecordSelector.filterPeople(
                new List<SObject>{ organization }
            );
            Test.stopTest();

            Assert.isFalse(isPerson, 'An organization is not a person');
            Assert.areEqual(0, people.size(), 'Nothing is treated as a person');
        }
    }

    @IsTest
    static void nothingAtAllIsHandled() {
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(PersonRecordSelector.isPersonRecord(null), 'No record means no person');
            Assert.areEqual(
                0,
                PersonRecordSelector.filterPeople(null).size(),
                'No list means no people'
            );
        }
    }

    @IsTest
    static void aListOfRecordsIsTurnedIntoPeople() {
        System.runAs(TestUsers.admin()) {
            Account record = new Account(Name = 'Maria Garcia');
            insert record;

            Test.startTest();
            List<HouseholdService.Person> people = PersonRecordSelector.toPersons(
                [SELECT Id, Name, Preferred_Name__c, Deceased__c FROM Account WHERE Id = :record.Id]
            );
            Test.stopTest();

            Assert.areEqual(1, people.size(), 'One record makes one person');
        }
    }

    /**
     * Every attribute the wording is built from, one at a time, on plain accounts with no
     * override of any kind in play. The five Core person fields are on the account object
     * in every org, so this exercises the real comparison rather than a stand-in.
     */
    @IsTest
    static void everyAttributeTheWordingIsBuiltFromCountsAsAChange() {
        System.runAs(TestUsers.admin()) {
            Map<String, Object> changes = new Map<String, Object>{
                'Preferred_Name__c' => 'Mari',
                'Deceased__c' => true,
                'Household_Role__c' => 'Head',
                'Exclude_From_Household_Name__c' => true,
                'Exclude_From_Greetings__c' => true
            };

            Test.startTest();
            Map<String, Boolean> noticed = new Map<String, Boolean>();
            for (String fieldName : changes.keySet()) {
                Account previous = new Account(Name = 'Maria Garcia');
                Account record = new Account(Name = 'Maria Garcia');
                record.put(fieldName, changes.get(fieldName));
                noticed.put(fieldName, PersonRecordSelector.namingChanged(record, previous));
            }
            Test.stopTest();

            for (String fieldName : changes.keySet()) {
                Assert.isTrue(
                    noticed.get(fieldName),
                    'A change to ' + fieldName + ' changes what the household is called'
                );
            }
        }
    }

    @IsTest
    static void aChangeTheWordingIsNotBuiltFromIsIgnored() {
        System.runAs(TestUsers.admin()) {
            Account previous = new Account(Name = 'Maria Garcia', Deceased__c = false);
            Account record = new Account(
                Name = 'Maria Garcia',
                Deceased__c = false,
                BillingCity = 'Riverside',
                Description = 'Met at the gala'
            );

            Test.startTest();
            Boolean noticed = PersonRecordSelector.namingChanged(record, previous);
            Boolean unchanged = PersonRecordSelector.namingChanged(previous, previous);
            Test.stopTest();

            Assert.isFalse(noticed, 'An address or a note is not part of the wording');
            Assert.isFalse(unchanged, 'A record compared with itself has not changed');
        }
    }

    @IsTest
    static void aChangeBackAgainIsNotAChange() {
        System.runAs(TestUsers.admin()) {
            Account previous = new Account(Name = 'Maria Garcia', Household_Role__c = 'Head');
            Account record = new Account(Name = 'Maria Garcia', Household_Role__c = 'Head');

            Test.startTest();
            Boolean noticed = PersonRecordSelector.namingChanged(record, previous);
            Test.stopTest();

            Assert.isFalse(noticed, 'The same value on both sides is not a change');
        }
    }

    @IsTest
    static void nothingToCompareIsNotAChange() {
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(
                PersonRecordSelector.namingChanged(null, new Account(Name = 'Maria Garcia')),
                'No record means nothing changed'
            );
            Assert.isFalse(
                PersonRecordSelector.namingChanged(new Account(Name = 'Maria Garcia'), null),
                'No previous version means nothing to compare with'
            );
        }
    }
}
