/**
 * Matching Logic's Apex surface (ADR-NEXT): the sources in plain words, the fields an object
 * offers, and "Try a value". Maria holds BarnCRM Admin and BarnCRM Metadata Admin and may
 * change sources; an admin without Metadata Admin reads only; anyone else is refused.
 */
@IsTest(testFor='ApexClass:MatchSourceController')
private class MatchSourceControllerTest {
    @TestSetup
    static void createTestUsers() {
        System.runAs(TestUsers.admin()) {
            maria();
        }
    }

    private static User maria() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Metadata_Admin' }
        );
    }

    private static Map<String, String> personAddress() {
        return new Map<String, String>{
            'Object_Name__c' => 'Address__c',
            'Value_Field__c' => 'Street__c',
            'Postal_Code_Field__c' => 'Postal_Code__c',
            'Parent_Field__c' => 'Contact__c',
            'Normalization__c' => 'Address'
        };
    }

    private static MatchSourceController.SourceView named(
        List<MatchSourceController.SourceView> sources,
        String developerName
    ) {
        for (MatchSourceController.SourceView source : sources) {
            if (source.developerName == developerName) {
                return source;
            }
        }
        return null;
    }

    @IsTest
    static void mariaSeesEverySourceInPlainWordsAndMayChangeThem() {
        System.runAs(maria()) {
            Test.startTest();
            MatchSourceController.View view = MatchSourceController.getView();
            Test.stopTest();

            Assert.isTrue(view.canEdit, 'Metadata Admin may change sources');
            Assert.areEqual(3, view.normalizations.size(), 'Email, Phone and Address');
            Assert.areEqual(
                Label.Core_MatchLogic_CompareEmail,
                view.normalizations[0].label,
                'Each way of comparing is said in words'
            );
            MatchSourceController.SourceView person = named(view.sources, 'Address_Person');
            Assert.isNotNull(person, 'The shipped person address source is listed');
            Assert.isTrue(person.shipped && person.active && person.usable, 'Shipped and in use');
            Assert.isNotNull(person.objectLabel, 'Its object by label');
            Assert.isNotNull(person.valueFieldLabel, 'Its value field by label');
            Assert.isNotNull(person.postalFieldLabel, 'Its postal code field by label');
            Assert.areEqual(Label.Core_MatchLogic_LinksPerson, person.linksTo, 'Tied to a person');
            Assert.areEqual(
                Label.Core_MatchLogic_LinksHousehold,
                named(view.sources, 'Address_Household').linksTo,
                'The household source is tied to a household'
            );
            Integer shipped = 0;
            for (MatchSourceController.SourceView source : view.sources) {
                if (!source.developerName.startsWith(CustomMetadataManagerService.ORG_PREFIX)) {
                    Assert.isTrue(source.shipped, source.developerName + ' must be marked shipped');
                    shipped++;
                }
            }
            Assert.isTrue(shipped >= 6, 'The six shipped match sources are read');
        }
    }

    @IsTest
    static void aSourceTheOrgCannotUseSaysSo() {
        System.runAs(maria()) {
            MatchSourceSelector.allSourcesOverride = (List<Match_Source__mdt>) JSON.deserialize(
                JSON.serialize(
                    new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'DeveloperName' => 'Org_Gone',
                            'MasterLabel' => 'Gone',
                            NamespaceUtil.qualify('Object_Name__c') => 'No_Such_Thing__c',
                            NamespaceUtil.qualify('Value_Field__c') => 'Email__c',
                            NamespaceUtil.qualify('Parent_Field__c') => 'Contact__c',
                            NamespaceUtil.qualify('Normalization__c') => 'Email',
                            NamespaceUtil.qualify('Active__c') => true
                        }
                    }
                ),
                List<Match_Source__mdt>.class
            );

            Test.startTest();
            MatchSourceController.View view = MatchSourceController.getView();
            Test.stopTest();

            Assert.areEqual(1, view.sources.size());
            Assert.isFalse(view.sources[0].usable, 'Its object is not in this org');
            Assert.isNull(view.sources[0].objectLabel, 'Nothing to name');
            Assert.isFalse(view.sources[0].shipped, 'An organization row');
        }
    }

    @IsTest
    static void anAdminWithoutMetadataAdminReadsOnly() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            MatchSourceController.View view = MatchSourceController.getView();
            Test.stopTest();

            Assert.isFalse(view.canEdit, 'Changing a source needs Metadata Admin');
            Assert.isFalse(view.sources.isEmpty(), 'But the sources are listed');
        }
    }

    @IsTest
    static void someoneWithNeitherPermissionIsRefused() {
        User nobody;
        System.runAs(TestUsers.admin()) {
            nobody = TestUsers.standardUser('Nobody');
        }
        System.runAs(nobody) {
            Test.startTest();
            String refusal;
            try {
                MatchSourceController.getView();
            } catch (AuraHandledException expected) {
                refusal = expected.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_MatchLogic_PermissionRequired, refusal);
        }
    }

    @IsTest
    static void anObjectOffersItsTextFieldsAndItsPersonOrHouseholdLookups() {
        System.runAs(maria()) {
            Test.startTest();
            MatchSourceController.ObjectView view = MatchSourceController.describeObject(
                'Address__c'
            );
            String refusal;
            try {
                MatchSourceController.describeObject('No_Such_Thing__c');
            } catch (AuraHandledException expected) {
                refusal = expected.getMessage();
            }
            Test.stopTest();

            Set<String> values = new Set<String>();
            for (MatchSourceController.Choice choice : view.valueFields) {
                values.add(choice.value);
            }
            Set<String> parents = new Set<String>();
            for (MatchSourceController.Choice choice : view.parentFields) {
                parents.add(choice.value);
            }
            Assert.isTrue(values.contains('Street__c'), 'The street is text: ' + values);
            Assert.isTrue(values.contains('Postal_Code__c'), 'So is the postal code');
            Assert.isFalse(values.contains('Contact__c'), 'A lookup is not a value');
            Assert.isTrue(
                parents.containsAll(new Set<String>{ 'Contact__c', 'Account__c' }),
                'The person and household lookups: ' + parents
            );
            Assert.isFalse(parents.contains('Street__c'), 'Text is not a parent');
            Assert.areEqual(
                String.format(
                    Label.Core_MatchSource_NoSuchObject,
                    new List<Object>{ 'No_Such_Thing__c' }
                ),
                refusal
            );
        }
    }

    @IsTest
    static void tryingAValueNamesThePeopleWhoHoldItAsTheScanWould() {
        System.runAs(maria()) {
            Database.DMLOptions options = new Database.DMLOptions();
            options.DuplicateRuleHeader.allowSave = true;
            List<Contact> people = new List<Contact>{
                new Contact(FirstName = 'Ana', LastName = 'Ruiz'),
                new Contact(FirstName = 'Ben', LastName = 'Okafor')
            };
            Database.insert(people, options);
            insert new List<Address__c>{
                new Address__c(
                    Contact__c = people[0].Id,
                    Street__c = '12 North Main Street',
                    Postal_Code__c = '02139'
                ),
                new Address__c(
                    Contact__c = people[1].Id,
                    Street__c = '99 Elm Road',
                    Postal_Code__c = '02139'
                )
            };

            Test.startTest();
            MatchSourceController.TryResult found = MatchSourceController.tryValue(
                'Address (person)',
                personAddress(),
                '12 n. MAIN st',
                '02139-4307'
            );
            MatchSourceController.TryResult nothing = MatchSourceController.tryValue(
                'Address (person)',
                personAddress(),
                '',
                '02139'
            );
            Test.stopTest();

            Assert.areEqual('12 n main st|02139', found.comparedAs, 'Normalized as the scan does');
            Assert.areEqual(1, found.records.size(), 'Only Ana holds it: ' + found.records);
            Assert.areEqual(people[0].Id, found.records[0].value);
            Assert.areEqual(
                Label.Core_Duplicates_ObjectPerson + ': Ana Ruiz',
                found.records[0].label,
                'Named, and said to be a person'
            );
            Assert.isNull(nothing.comparedAs, 'No street, nothing to compare');
            Assert.isTrue(nothing.records.isEmpty(), 'And nobody found');
        }
    }

    @IsTest
    static void tryingASourceASaveWouldRefuseSaysWhy() {
        System.runAs(maria()) {
            Map<String, String> values = personAddress();
            values.put('Postal_Code_Field__c', null);

            Test.startTest();
            String refusal;
            try {
                MatchSourceController.tryValue('Broken', values, '1 Main St', '02139');
            } catch (AuraHandledException expected) {
                refusal = expected.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_MatchSource_PostalRequired, refusal);
        }
    }

    @IsTest
    static void whatASourceIsTiedToAndHowItComparesAreSaidInWords() {
        System.runAs(maria()) {
            Test.startTest();
            String either = MatchSourceController.linksTo(
                new Set<String>{ 'Account', 'Individual' }
            );
            String none = MatchSourceController.linksTo(new Set<String>());
            String phone = MatchSourceController.normalizationText('Phone');
            String address = MatchSourceController.normalizationText('Address');
            Test.stopTest();

            Assert.areEqual(Label.Core_MatchLogic_LinksEither, either);
            Assert.isNull(none);
            Assert.areEqual(Label.Core_MatchLogic_ComparePhone, phone);
            Assert.areEqual(Label.Core_MatchLogic_CompareAddress, address);
        }
    }
}
