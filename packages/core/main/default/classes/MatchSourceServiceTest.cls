/**
 * Match sources: which ones an org can use, and how their values are made comparable
 * (ADR-0133, `0133-related-record-matching.md`).
 */
@IsTest(testFor='ApexClass:MatchSourceService')
private class MatchSourceServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Match_Source__mdt row(
        String developerName,
        String objectName,
        String valueField,
        String postalField,
        String parentField,
        String normalization
    ) {
        // DeveloperName cannot be set on an in-memory row, so the row is read from JSON.
        Map<String, Object> fields = new Map<String, Object>{
            'DeveloperName' => developerName,
            'MasterLabel' => developerName,
            NamespaceUtil.qualify('Object_Name__c') => objectName,
            NamespaceUtil.qualify('Value_Field__c') => valueField,
            NamespaceUtil.qualify('Postal_Code_Field__c') => postalField,
            NamespaceUtil.qualify('Parent_Field__c') => parentField,
            NamespaceUtil.qualify('Normalization__c') => normalization
        };
        return (Match_Source__mdt) JSON.deserialize(
            JSON.serialize(fields),
            Match_Source__mdt.class
        );
    }

    @IsTest
    static void emailsCompareTrimmedAndInLowerCase() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('maria@example.org', MatchSourceService.email('  Maria@Example.ORG '));
            Assert.isNull(MatchSourceService.email('not an email'), 'No @, nothing to compare');
            Assert.isNull(MatchSourceService.email(null), 'Blank');
            Assert.areEqual(
                MatchSourceService.email('maria@example.org'),
                MatchSourceService.key(MatchSourceService.EMAIL, 'MARIA@example.org', null),
                'key() applies the source normalization'
            );
        }
    }

    @IsTest
    static void phonesCompareByDigitsWithoutTheNorthAmericanOne() {
        System.runAs(TestUsers.admin()) {
            String expected = '5551234567';
            Assert.areEqual(expected, MatchSourceService.phone('(555) 123-4567'));
            Assert.areEqual(expected, MatchSourceService.phone('555.123.4567'));
            Assert.areEqual(expected, MatchSourceService.phone('+1 555 123 4567'));
            Assert.areEqual(expected, MatchSourceService.phone('1-555-123-4567'));
            Assert.areEqual(
                '442079460958',
                MatchSourceService.phone('+44 20 7946 0958'),
                'Only an 11 digit number starting 1 loses its first digit'
            );
            Assert.isNull(MatchSourceService.phone('x1234'), 'Too short to say anything');
            Assert.isNull(MatchSourceService.phone(null), 'Blank');
        }
    }

    @IsTest
    static void addressesCompareFoldedStreetAndPostalCode() {
        System.runAs(TestUsers.admin()) {
            String expected = MatchSourceService.address('12 North Main Street, Apt. 4', '02139');
            Assert.areEqual('12 n main st apt 4|02139', expected);
            Assert.areEqual(
                expected,
                MatchSourceService.address('12  n. MAIN st   apartment 4', '02139-4307'),
                'Capitals, punctuation, abbreviations and ZIP+4 do not matter'
            );
            Assert.areEqual(
                '1 high st|SW1A1AA',
                MatchSourceService.address('1 High Street', 'sw1a 1aa'),
                'A postal code loses its spaces and is upper case'
            );
            Assert.isNull(MatchSourceService.address('1 High Street', null), 'No postal code');
            Assert.isNull(MatchSourceService.address(' , ', '02139'), 'No street');
            Assert.isNull(
                MatchSourceService.key('Fax', '1', null),
                'An unknown normalization compares nothing'
            );
        }
    }

    @IsTest
    static void onlySourcesTheOrgCanUseAreUsed() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Usable', 'Address__c', 'Street__c', 'Postal_Code__c', 'Contact__c', 'Address'),
                row('NoObject', 'No_Such_Thing__c', 'Street__c', null, 'Contact__c', 'Email'),
                row('NoField', 'Address__c', 'No_Such_Field__c', null, 'Contact__c', 'Email'),
                row('NotLookup', 'Address__c', 'Street__c', null, 'City__c', 'Email'),
                row('NoPostal', 'Address__c', 'Street__c', null, 'Contact__c', 'Address'),
                row('NoNormalization', 'Address__c', 'Street__c', null, 'Contact__c', null)
            };

            Test.startTest();
            List<MatchSourceService.Source> sources = MatchSourceService.usableSources();
            Test.stopTest();

            Assert.areEqual(1, sources.size(), 'Only the usable source: ' + sources);
            MatchSourceService.Source source = sources[0];
            Assert.areEqual('Usable', source.developerName);
            Assert.areEqual(Address__c.SObjectType, source.objectType, 'Resolved by describe');
            Assert.areEqual(
                String.valueOf(Address__c.Street__c),
                source.valueField,
                'Full field names, prefix included'
            );
            Assert.areEqual(String.valueOf(Address__c.Postal_Code__c), source.postalField);
            Assert.areEqual(String.valueOf(Address__c.Contact__c), source.parentField);
        }
    }

    @IsTest
    static void theShippedAddressSourcesAreUsableEverywhere() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<MatchSourceService.Source> sources = MatchSourceService.usableSources();
            Test.stopTest();

            Set<String> names = new Set<String>();
            for (MatchSourceService.Source source : sources) {
                names.add(source.developerName);
            }
            Assert.isTrue(
                names.containsAll(
                    new Set<String>{
                        'Address_Person',
                        'Address_Household',
                        'Address_Person_Account'
                    }
                ),
                'Core\'s own address object is in every org: ' + names
            );
        }
    }

    // ------------------------------------------------------------------ matching

    private static Set<String> keysOf(List<DuplicateService.Pair> pairs) {
        Set<String> keys = new Set<String>();
        for (DuplicateService.Pair pair : pairs) {
            keys.add(pair.key);
        }
        return keys;
    }

    private static List<SObject> insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(records, options);
        return records;
    }

    @IsTest
    static void peopleSharingAnAddressHeldOnlyOnAddressRecordsArePaired() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row(
                    'Address_Person',
                    'Address__c',
                    'Street__c',
                    'Postal_Code__c',
                    'Contact__c',
                    'Address'
                )
            };
            List<Contact> people = (List<Contact>) insertAllowingDuplicates(
                new List<Contact>{
                    new Contact(FirstName = 'Ana', LastName = 'Ruiz'),
                    new Contact(FirstName = 'Anna', LastName = 'Ruiz-Lopez'),
                    new Contact(FirstName = 'Ben', LastName = 'Okafor')
                }
            );
            insert new List<Address__c>{
                new Address__c(
                    Contact__c = people[0].Id,
                    Street__c = '12 North Main Street',
                    Postal_Code__c = '02139'
                ),
                new Address__c(
                    Contact__c = people[1].Id,
                    Street__c = '12 n. MAIN st',
                    Postal_Code__c = '02139-4307'
                ),
                new Address__c(
                    Contact__c = people[2].Id,
                    Street__c = '99 Elm Road',
                    Postal_Code__c = '02139'
                )
            };

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ people[0].Id, people[1].Id, people[2].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ DuplicateService.pairKey(people[0].Id, people[1].Id) },
                keysOf(pairs),
                'Only the two people at the same address, written two ways'
            );
            Assert.areEqual('Same address on Address_Person', pairs[0].reason, 'Names the source');
            Assert.isNull(pairs[0].ruleName, 'No rule found it');
        }
    }

    @IsTest
    static void householdsWhosePeopleShareAPhoneArePairedWhateverItsFormat() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Phone', 'Contact', 'Phone', null, 'AccountId', 'Phone')
            };
            List<Account> homes = new List<Account>{
                AddressTestDataFactory.newHousehold('Lee Household'),
                AddressTestDataFactory.newHousehold('Li Household'),
                AddressTestDataFactory.newHousehold('Park Household')
            };
            insertAllowingDuplicates(homes);
            List<String> phones = new List<String>{
                '(555) 123-4567',
                '+1 555.123.4567',
                '555 999 0000'
            };
            List<Contact> people = new List<Contact>();
            for (Integer index = 0; index < homes.size(); index++) {
                Contact person = AddressTestDataFactory.newContact(
                    'Sam',
                    'Member' + index,
                    homes[index].Id
                );
                person.Phone = phones[index];
                people.add(person);
            }
            insertAllowingDuplicates(people);

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ homes[0].Id, homes[1].Id, homes[2].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ DuplicateService.pairKey(homes[0].Id, homes[1].Id) },
                keysOf(pairs),
                'The two households with the same number, however it is written'
            );
            Assert.areEqual('Same phone on Member_Phone', pairs[0].reason, 'Names the source');
        }
    }

    @IsTest
    static void aValueHeldByMoreThanTenIsNotUsed() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Email', 'Contact', 'Email', null, 'AccountId', 'Email')
            };
            List<Account> homes = new List<Account>();
            for (Integer index = 0; index <= MatchSourceService.MAX_OWNERS_PER_VALUE; index++) {
                homes.add(AddressTestDataFactory.newHousehold('Office ' + index));
            }
            insertAllowingDuplicates(homes);
            List<Contact> people = new List<Contact>();
            for (Account home : homes) {
                Contact person = AddressTestDataFactory.newContact('Front', 'Desk', home.Id);
                person.Email = 'info@shared-office.example.org';
                people.add(person);
            }
            insertAllowingDuplicates(people);

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ homes[0].Id, homes[1].Id }
            );
            Test.stopTest();

            Assert.isTrue(pairs.isEmpty(), 'A shared mailbox pairs nobody: ' + pairs.size());
        }
    }

    @IsTest
    static void aSourceThatCannotPointAtTheRecordsIsNotAsked() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row(
                    'Address_Household',
                    'Address__c',
                    'Street__c',
                    'Postal_Code__c',
                    'Account__c',
                    'Address'
                )
            };
            Contact person = new Contact(FirstName = 'Ida', LastName = 'Nobody');
            insert person;

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ person.Id }
            );
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.isTrue(pairs.isEmpty(), 'A household source finds no people');
            Assert.isTrue(queries <= 2, 'Only the sources are read, never the rows: ' + queries);
        }
    }
}
