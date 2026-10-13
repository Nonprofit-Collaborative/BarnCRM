/**
 * What a one-object load may never write (canonical model R-IT14): the objects the allow-list
 * rule refuses, the fields the package or the platform keeps, every Rollup Definition target,
 * and a household's name.
 */
@IsTest(testFor='ApexClass:DataProtectedFields')
private class DataProtectedFieldsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static String refusal(Schema.SObjectType type) {
        return DataProtectedFields.objectRefusal(type);
    }

    private static String plural(Schema.SObjectType type) {
        return type.getDescribe().getLabelPlural();
    }

    @IsTest
    static void thePackagesBookkeepingIsNeverLoaded() {
        System.runAs(TestUsers.admin()) {
            DataProtectionExtensions.noneForTest = true;
            Test.startTest();
            String batches = refusal(Import_Batch__c.SObjectType);
            List<String> others = new List<String>{
                refusal(Import_Template__c.SObjectType),
                refusal(Import_Row__c.SObjectType),
                refusal(Import_Journal__c.SObjectType),
                refusal(Error_Log__c.SObjectType),
                refusal(Setting_Change__c.SObjectType),
                refusal(Automation_Setting__c.SObjectType),
                refusal(Rollup_Definition__c.SObjectType)
            };
            Test.stopTest();

            Assert.areEqual(
                String.format(
                    Label.Core_Data_ObjectBookkeeping,
                    new List<String>{ plural(Import_Batch__c.SObjectType) }
                ),
                batches,
                'Import batches are the package bookkeeping.'
            );
            for (String other : others) {
                Assert.isNotNull(other, 'Every bookkeeping object is refused.');
            }
        }
    }

    @IsTest
    static void bulkUpdateAndLoadShareOneProtectedList() {
        System.runAs(TestUsers.admin()) {
            DataProtectionExtensions.noneForTest = true;
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            Test.startTest();
            Boolean savedQueries = DataProtectedFields.isBookkeeping(Saved_Query__c.SObjectType);
            Boolean dismissals = DataProtectedFields.isBookkeeping(
                Duplicate_Dismissal__c.SObjectType
            );
            Boolean contacts = DataProtectedFields.isBookkeeping(Contact.SObjectType);
            Boolean users = DataProtectedFields.isSetup(User.SObjectType);
            Boolean accounts = DataProtectedFields.isSetup(Account.SObjectType);
            Boolean sampleKey = DataProtectedFields.isKeptByThePackage(
                Contact.SObjectType,
                Contact.Sample_Data_Key__c.getDescribe()
            );
            Boolean title = DataProtectedFields.isKeptByThePackage(
                Contact.SObjectType,
                Contact.Title.getDescribe()
            );
            Test.stopTest();

            Assert.isTrue(savedQueries, 'Saved queries are the package bookkeeping (from C-35).');
            Assert.isTrue(dismissals, 'Duplicate dismissals are the package bookkeeping.');
            Assert.isFalse(contacts, 'Contacts are the organization records.');
            Assert.isTrue(users, 'Users are managed in Setup.');
            Assert.isFalse(accounts, 'Accounts are not a Setup object.');
            Assert.isTrue(sampleKey, 'The sample data key is kept by the package.');
            Assert.isFalse(title, 'An ordinary field is not kept by the package.');
        }
    }

    @IsTest
    static void setupMembershipSettingsAndEventsAreRefused() {
        System.runAs(TestUsers.admin()) {
            DataProtectionExtensions.noneForTest = true;
            Test.startTest();
            String users = refusal(User.SObjectType);
            String profiles = refusal(Profile.SObjectType);
            String members = refusal(Household_Member__c.SObjectType);
            String settings = refusal(BarnCRM_Settings__c.SObjectType);
            String event = refusal(Error_Log_Event__e.SObjectType);
            String jobs = refusal(AsyncApexJob.SObjectType);
            String missing = refusal(null);
            Test.stopTest();

            Assert.areEqual(
                String.format(
                    Label.Core_Data_ObjectSetup,
                    new List<String>{ plural(User.SObjectType) }
                ),
                users,
                'Users are managed in Setup, never loaded here.'
            );
            Assert.isNotNull(profiles, 'So are profiles.');
            Assert.areEqual(
                String.format(
                    Label.Core_Data_ObjectMembership,
                    new List<String>{ plural(Household_Member__c.SObjectType) }
                ),
                members,
                'Memberships are written by the household service.'
            );
            Assert.isNotNull(settings, 'A custom setting is never loaded.');
            Assert.isNotNull(event, 'Nor a platform event.');
            Assert.areEqual(
                String.format(
                    Label.Core_Data_ObjectNotLoadable,
                    new List<String>{ plural(AsyncApexJob.SObjectType) }
                ),
                jobs,
                'A standard object that is not a business record is refused by the rule.'
            );
            Assert.areEqual(Label.Core_Data_ObjectUnknown, missing, 'Nor an object the org lacks.');
        }
    }

    @IsTest
    static void theOrganizationsOwnRecordsMayBeLoaded() {
        System.runAs(TestUsers.admin()) {
            DataProtectionExtensions.noneForTest = true;
            Test.startTest();
            String affiliations = refusal(Affiliation__c.SObjectType);
            String relationships = refusal(Relationship__c.SObjectType);
            String contacts = refusal(Contact.SObjectType);
            String accounts = refusal(Account.SObjectType);
            String tasks = refusal(Task.SObjectType);
            Test.stopTest();

            Assert.isNull(affiliations, 'A custom object of the org may be loaded.');
            Assert.isNull(relationships, 'Any custom object that is not bookkeeping.');
            Assert.isNull(contacts, 'People are a business record.');
            Assert.isNull(accounts, 'So are accounts.');
            Assert.isNull(tasks, 'And tasks.');
        }
    }

    @IsTest
    static void theFieldsThePackageAndThePlatformKeepAreProtected() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Set<String> accountFields = DataProtectedFields.fieldNames(Account.SObjectType);
            Set<String> contactFields = DataProtectedFields.fieldNames(Contact.SObjectType);
            Set<String> rollupFields = DataProtectedFields.fieldNames(
                Rollup_Definition__c.SObjectType
            );
            Test.stopTest();

            for (
                Schema.SObjectField field : new List<Schema.SObjectField>{
                    Account.Household_Formal_Greeting__c,
                    Account.Household_Informal_Greeting__c,
                    Account.Member_Count__c,
                    Account.Primary_Contact__c,
                    Account.Created_By_Import_Batch__c,
                    Account.Sample_Data__c,
                    Account.CreatedDate,
                    Account.LastModifiedById,
                    Account.Id
                }
            ) {
                Assert.isTrue(
                    accountFields.contains(field.getDescribe().getName().toLowerCase()),
                    field.getDescribe().getName() + ' is kept by BarnCRM or Salesforce.'
                );
            }
            Assert.isTrue(
                contactFields.contains('primary_affiliation__c'),
                'A primary affiliation is kept by the affiliation upkeep.'
            );
            Assert.isTrue(
                rollupFields.contains('last_calculated__c'),
                'A Last Calculated stamp is the package own.'
            );
            Assert.isFalse(accountFields.contains('name'), 'An account name is not kept as such.');
            Assert.isFalse(contactFields.contains('email'), 'Nor an email.');
            Assert.isTrue(
                DataProtectedFields.isProtected(
                    Contact.SObjectType,
                    ' CREATED_BY_IMPORT_BATCH__C '
                ),
                'Asked ignoring case and spaces.'
            );
            Assert.isFalse(
                DataProtectedFields.isProtected(Contact.SObjectType, ''),
                'Nothing named.'
            );
            Assert.isTrue(DataProtectedFields.fieldNames(null).isEmpty(), 'No object, no fields.');
        }
    }

    @IsTest
    static void formulaAndAutoNumberFieldsAreProtected() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Set<String> batchFields = DataProtectedFields.fieldNames(Import_Batch__c.SObjectType);
            Test.stopTest();

            Assert.isTrue(batchFields.contains('name'), 'An auto number name is never written.');
        }
    }

    @IsTest
    static void everyRollupTargetIsProtectedWithoutCode() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>{
                new Rollup_Definition__c(
                    Target_Object__c = 'Contact',
                    Target_Field__c = 'Description'
                ),
                new Rollup_Definition__c(Target_Object__c = 'Account', Target_Field__c = 'Site'),
                new Rollup_Definition__c(Target_Object__c = 'Account', Target_Field__c = null)
            };

            Test.startTest();
            Boolean description = DataProtectedFields.isProtected(
                Contact.SObjectType,
                'Description'
            );
            Boolean site = DataProtectedFields.isProtected(Account.SObjectType, 'Site');
            Boolean title = DataProtectedFields.isProtected(Contact.SObjectType, 'Title');
            Test.stopTest();

            Assert.isTrue(description, 'A rollup target on Contact is protected.');
            Assert.isTrue(site, 'And one on Account.');
            Assert.isFalse(title, 'A field no definition targets is not.');
        }
    }

    @IsTest
    static void aHouseholdsNameIsProtectedAndAnOrganizationsIsNot() {
        System.runAs(TestUsers.admin()) {
            Id householdType = HouseholdService.householdRecordTypeId();
            Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId();

            Test.startTest();
            Boolean household = DataProtectedFields.isProtectedOnRecord(
                Account.SObjectType,
                'Name',
                householdType
            );
            Boolean organization = DataProtectedFields.isProtectedOnRecord(
                Account.SObjectType,
                'Name',
                organizationType
            );
            Boolean other = DataProtectedFields.isProtectedOnRecord(
                Account.SObjectType,
                'Phone',
                householdType
            );
            Test.stopTest();

            Assert.isTrue(household, 'The household naming patterns keep a household name.');
            Assert.isFalse(organization, 'An organization name is its own to change.');
            Assert.isFalse(other, 'Only the name.');
        }
    }
}
