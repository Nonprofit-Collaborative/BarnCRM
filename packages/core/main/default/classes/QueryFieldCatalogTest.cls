/**
 * The field catalog the filter builder and Find read (canonical model R-R2, plan Section 4.9).
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest(testFor='ApexClass:QueryFieldCatalog')
private class QueryFieldCatalogTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void describesAnObjectWithItsFieldsSortedByLabel() {
        System.runAs(TestUsers.admin()) {
            QueryFieldCatalog.ObjectInfo info = QueryFieldCatalog.getObjectInfo('Affiliation__c');

            System.Assert.isTrue(
                info.apiName.endsWith('Affiliation__c'),
                'The object comes back by its API name'
            );
            System.Assert.isFalse(info.fields.isEmpty(), 'An object the user can read has fields');
            for (Integer index = 1; index < info.fields.size(); index++) {
                System.Assert.isTrue(
                    info.fields[index - 1].label.toLowerCase() <=
                    info.fields[index].label.toLowerCase(),
                    'Fields are sorted by label so the builder can show them as they come'
                );
            }
        }
    }

    @IsTest
    static void aLookupNamesItsParentAndRelationship() {
        System.runAs(TestUsers.admin()) {
            QueryFieldCatalog.FieldInfo contact = field(
                QueryFieldCatalog.describe('Affiliation__c'),
                'Contact__c'
            );

            System.Assert.areEqual('reference', contact.dataType, 'A lookup is a reference');
            System.Assert.areEqual('Contact', contact.referenceTo, 'The parent object is named');
            System.Assert.isTrue(
                contact.relationshipName.endsWith('Contact__r'),
                'The path name a parent field uses is given'
            );
        }
    }

    @IsTest
    static void aPicklistCarriesItsActiveValues() {
        System.runAs(TestUsers.admin()) {
            QueryFieldCatalog.FieldInfo status = field(
                QueryFieldCatalog.describe('Affiliation__c'),
                'Status__c'
            );

            System.Assert.areEqual('picklist', status.dataType, 'Status is a picklist');
            System.Assert.isFalse(status.picklistValues.isEmpty(), 'Its values come with it');
            System.Assert.isTrue(status.filterable, 'A picklist can be filtered on');
        }
    }

    @IsTest
    static void anUnknownOrMalformedObjectIsRefusedInPlainWords() {
        System.runAs(TestUsers.admin()) {
            for (
                String objectName : new List<String>{ 'No_Such_Object__c', 'Account; DELETE', '' }
            ) {
                try {
                    QueryFieldCatalog.getObjectInfo(objectName);
                    System.Assert.fail(
                        'An object that cannot be described is refused: ' + objectName
                    );
                } catch (AuraHandledException refused) {
                    System.Assert.isTrue(
                        String.isNotBlank(refused.getMessage()),
                        'The refusal says what is wrong'
                    );
                }
            }
        }
    }

    @IsTest
    static void resolvesAFieldAndAParentPathTwoLookupsDeep() {
        System.runAs(TestUsers.admin()) {
            System.Assert.areEqual(
                'Name',
                QueryFieldCatalog.resolvePath('Affiliation__c', 'Contact__r.Account.Name')
                    .getName(),
                'A path crosses two lookups and ends on the parent field'
            );
            System.Assert.areEqual(
                Schema.DisplayType.DATE,
                QueryFieldCatalog.resolvePath('Affiliation__c', 'Start_Date__c').getType(),
                'A plain field resolves on the object itself'
            );
        }
    }

    @IsTest
    static void refusesPathsThatAreTooDeepUnknownOrMalformed() {
        System.runAs(TestUsers.admin()) {
            List<String> refusedPaths = new List<String>{
                'Contact__r.Account.Owner.Name',
                'Contact__r.No_Such_Field__c',
                'No_Such_Relationship__r.Name',
                'Status__c; DELETE',
                ''
            };
            for (String path : refusedPaths) {
                try {
                    QueryFieldCatalog.resolvePath('Affiliation__c', path);
                    System.Assert.fail('A path the user cannot follow is refused: ' + path);
                } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
                    System.Assert.isTrue(
                        refused.getMessage().contains(path),
                        'The refusal names the path so the admin can find the condition'
                    );
                }
            }
        }
    }

    /** Describes are read once per object in a transaction, and give the same answers after. */
    @IsTest
    static void anObjectIsDescribedOnceAndAnswersTheSameAfter() {
        System.runAs(TestUsers.admin()) {
            Schema.DescribeSObjectResult first = QueryFieldCatalog.describeObject('Affiliation__c');
            System.Assert.areEqual(
                first,
                QueryFieldCatalog.describeObject('AFFILIATION__C'),
                'The second read, in any case, is the first describe'
            );
            for (Integer index = 0; index < 200; index++) {
                System.Assert.areEqual(
                    'Name',
                    QueryFieldCatalog.resolvePath('Affiliation__c', 'contact__r.ACCOUNT.Name')
                        .getName(),
                    'Every path crossing the same lookups resolves the same way'
                );
            }
            for (Integer attempt = 0; attempt < 2; attempt++) {
                try {
                    QueryFieldCatalog.describeObject('No_Such_Object__c');
                    System.Assert.fail('An unknown object is refused every time');
                } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
                    System.Assert.isTrue(
                        refused.getMessage().contains('No_Such_Object__c'),
                        'A refusal is never cached as an answer'
                    );
                }
            }
        }
    }

    /** One rule for the platform's own tables, standard and custom, and for settings. */
    @IsTest
    static void tellsThePlatformsOwnTablesFromRecords() {
        System.runAs(TestUsers.admin()) {
            System.Assert.isFalse(
                QueryFieldCatalog.isSystemObject(Schema.SObjectType.Account),
                'Account holds records'
            );
            System.Assert.isFalse(
                QueryFieldCatalog.isSystemObject(Schema.SObjectType.Affiliation__c),
                'A package object holds records'
            );
            System.Assert.isTrue(
                QueryFieldCatalog.isSystemObject(Schema.SObjectType.AccountShare),
                'A standard share table'
            );
            System.Assert.isTrue(
                QueryFieldCatalog.isSystemObject(Schema.SObjectType.BarnCRM_Settings__c),
                'A custom setting'
            );
        }
    }

    private static QueryFieldCatalog.FieldInfo field(
        QueryFieldCatalog.ObjectInfo info,
        String apiNameSuffix
    ) {
        for (QueryFieldCatalog.FieldInfo candidate : info.fields) {
            if (candidate.apiName.endsWith(apiNameSuffix)) {
                return candidate;
            }
        }
        System.Assert.fail('Field not described: ' + apiNameSuffix);
        return null;
    }
}
