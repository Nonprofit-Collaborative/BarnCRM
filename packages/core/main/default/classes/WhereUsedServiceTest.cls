/**
 * Where Used (C-59): that each kind of Core setup record is found by the field it names, through
 * columns, filters, sorts, lookups, related records, import columns and matching fields; that a
 * whole object finds what works on it; that a private query of someone else is listed by owner
 * only; that a module's extension is asked and one that fails marks the answer incomplete; and
 * that the controller refuses a person without Manage BarnCRM Settings and an unknown name.
 *
 * Runs as permission-set users. Merge rules and matching sources are injected, since custom
 * metadata cannot be inserted in a test.
 */
@IsTest(
    testFor='ApexClass:WhereUsedService, ApexClass:WhereUsedController, ApexClass:WhereUsedExtensions, ApexClass:WhereUsedSelector'
)
private class WhereUsedServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** A module stand-in that reports one record for any target. */
    private class FakeExtension implements WhereUsedExtension {
        public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
            return new List<WhereUsedService.Reference>{
                new WhereUsedService.Reference(
                        'fake',
                        'Module Things',
                        'Fake ' + target.objectName,
                        null
                    )
                    .addPart('Field')
            };
        }
    }

    /** A module stand-in that fails. */
    private class BrokenExtension implements WhereUsedExtension {
        public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
            throw new System.TypeException('broken');
        }
    }

    private static void noModules() {
        WhereUsedExtensions.noneForTest = true;
        MatchSourceSelector.allSourcesOverride = new List<Match_Source__mdt>();
        WhereUsedSelector.mergeRulesOverride = new List<Merge_Rule__mdt>();
    }

    private static Saved_Query__c query(String name, String objectName, String json) {
        return new Saved_Query__c(
            Name = name,
            Object_Name__c = objectName,
            Query_JSON__c = json,
            Shared__c = true
        );
    }

    private static Import_Template__c template(String name, String mapping) {
        return new Import_Template__c(
            Name = name,
            Template_Key__c = 'where_used_' + name.replace(' ', '_'),
            Column_Mapping_JSON__c = mapping,
            Default_Values_JSON__c = '{"version":1,"defaults":[]}',
            Person_Mode__c = ImportTemplateService.PERSON_MODE_CONTACTS,
            Is_Package_Default__c = false,
            Active__c = true
        );
    }

    private static List<WhereUsedService.Reference> ofKind(
        WhereUsedService.Result result,
        String kind
    ) {
        List<WhereUsedService.Reference> found = new List<WhereUsedService.Reference>();
        for (WhereUsedService.Reference reference : result.references) {
            if (reference.kind == kind) {
                found.add(reference);
            }
        }
        return found;
    }

    private static WhereUsedService.Reference named(WhereUsedService.Result result, String name) {
        for (WhereUsedService.Reference reference : result.references) {
            if (reference.name == name) {
                return reference;
            }
        }
        return null;
    }

    @IsTest
    static void savedQueriesAreFoundByEveryPartThatNamesTheField() {
        System.runAs(TestUsers.admin()) {
            noModules();
            insert as system new List<Saved_Query__c>{
                query(
                    'Columns',
                    'Contact',
                    '{"version":1,"object":"Contact","fields":["LastName","Email"]}'
                ),
                query(
                    'Filter',
                    'Contact',
                    '{"version":1,"object":"Contact","fields":["LastName"],"filter":{"version":1,"conditions":[{"id":1,"field":"Email","operator":"is null"}]}}'
                ),
                query(
                    'Sort And Summary',
                    'Contact',
                    '{"version":1,"object":"Contact","fields":["LastName"],"orderBy":[{"field":"Email","direction":"ASC"}],"aggregate":{"function":"count","groupBy":"Email"}}'
                ),
                query(
                    'Parent Path',
                    'Affiliation__c',
                    '{"version":1,"object":"Affiliation__c","fields":["Contact__r.Email"]}'
                ),
                query(
                    'Related',
                    'Account',
                    '{"version":1,"object":"Account","fields":["Name"],"related":[{"object":"Contact","field":"AccountId","has":true,"filter":{"version":1,"conditions":[{"id":1,"field":"Email","operator":"is not null"}]}}]}'
                ),
                query(
                    'Children',
                    'Account',
                    '{"version":1,"object":"Account","fields":["Name"],"children":[{"relationship":"Contacts","fields":["Email"],"limit":5}]}'
                ),
                query(
                    'Unrelated',
                    'Contact',
                    '{"version":1,"object":"Contact","fields":["LastName"]}'
                ),
                query('Broken', 'Contact', 'not json')
            };

            Test.startTest();
            WhereUsedService.Result result = WhereUsedController.findReferences('Contact', 'email');
            Test.stopTest();

            Assert.areEqual('Contact', result.objectName);
            Assert.areEqual('Email', result.fieldName, 'The field is named as describe names it.');
            Assert.isFalse(result.deletable, 'A standard field cannot be deleted.');
            Assert.areEqual(
                6,
                ofKind(result, WhereUsedService.KIND_SAVED_QUERY).size(),
                'Every query naming Email.'
            );
            Assert.areEqual(
                new List<String>{ System.Label.Core_WhereUsed_PartColumns },
                named(result, 'Columns').parts
            );
            Assert.areEqual(
                new List<String>{ System.Label.Core_WhereUsed_PartFilter },
                named(result, 'Filter').parts
            );
            Assert.areEqual(
                new List<String>{
                    System.Label.Core_WhereUsed_PartSort,
                    System.Label.Core_WhereUsed_PartSummary
                },
                named(result, 'Sort And Summary').parts
            );
            Assert.areEqual(
                new List<String>{ System.Label.Core_WhereUsed_PartColumns },
                named(result, 'Parent Path').parts,
                'A path through a lookup reaches the field.'
            );
            Assert.areEqual(
                new List<String>{ System.Label.Core_WhereUsed_PartRelated },
                named(result, 'Related').parts
            );
            Assert.areEqual(
                new List<String>{ System.Label.Core_WhereUsed_PartChildren },
                named(result, 'Children').parts
            );
            Assert.isNull(named(result, 'Unrelated'));
            Assert.isNull(named(result, 'Broken'), 'An unreadable document matches nothing.');
            WhereUsedService.Reference columns = named(result, 'Columns');
            Assert.areEqual(NamespaceUtil.qualify('Find'), columns.editTab);
            Assert.areEqual(
                columns.recordId,
                columns.editState.get(NamespaceUtil.stateKey('savedQueryId'))
            );
            Assert.areEqual(System.Label.Core_WhereUsed_BreaksSavedQuery, columns.breaks);
            Assert.areEqual(
                '/lightning/n/' +
                    NamespaceUtil.qualify('Find') +
                    '?' +
                    NamespaceUtil.stateKey('savedQueryId') +
                    '=' +
                    columns.recordId,
                columns.editUrl
            );
            Assert.areEqual(
                '/lightning/n/' +
                    NamespaceUtil.qualify('Find') +
                    '?' +
                    NamespaceUtil.stateKey('object') +
                    '=Contact',
                result.findUrl
            );
        }
    }

    @IsTest
    static void aLookupFieldIsFoundThroughItsRelationshipName() {
        System.runAs(TestUsers.admin()) {
            noModules();
            insert as system query(
                'Parent Path',
                'Affiliation__c',
                '{"version":1,"object":"Affiliation__c","fields":["Contact__r.Email"]}'
            );

            WhereUsedService.Result result = WhereUsedService.find('Affiliation__c', 'Contact__c');

            Assert.areEqual(
                1,
                result.references.size(),
                'Contact__r.Email travels through Contact__c.'
            );
        }
    }

    @IsTest
    static void aPrivateQueryOfSomeoneElseIsListedByOwnerOnly() {
        User owner;
        System.runAs(TestUsers.admin()) {
            owner = TestUsers.standardUserWith('Owen', new List<String>{ 'BarnCRM_Admin' });
        }
        System.runAs(owner) {
            Saved_Query__c secret = query(
                'Secret Plans',
                'Contact',
                '{"version":1,"object":"Contact","fields":["Email"]}'
            );
            secret.Shared__c = false;
            insert as system secret;
        }
        System.runAs(TestUsers.admin()) {
            noModules();

            WhereUsedService.Result result = WhereUsedService.find('Contact', 'Email');

            Assert.areEqual(1, result.references.size(), 'Private queries are counted.');
            WhereUsedService.Reference reference = result.references[0];
            Assert.isFalse(reference.name.contains('Secret'), 'The name is not shown.');
            Assert.isNull(reference.recordId);
            Assert.isNull(reference.editTab, 'Nothing to open.');
        }
    }

    @IsTest
    static void transformsMappingsRulesSourcesAndSettingsAreFound() {
        System.runAs(TestUsers.admin()) {
            noModules();
            insert as system new Saved_Transform__c(
                Name = 'Tidy Titles',
                Object_Name__c = 'Contact',
                Definition_JSON__c = '{"version":1,"object":"Contact","changes":[{"field":"Title","action":"copy","source":"Department"}]}'
            );
            insert as system new List<Import_Template__c>{
                template(
                    'People',
                    '{"version":1,"columns":[{"source":"Job","target":"Contact1.Department"},{"source":"Mail","target":"Contact1.Email"}],"defaults":[]}'
                ),
                template(
                    'Gifts Only',
                    '{"version":1,"columns":[{"source":"Amount","target":"Gift.Amount__c"}]}'
                )
            };
            Import_Template__c oneObject = template(
                'Affiliations',
                '{"version":1,"columns":[{"source":"Who","target":"Record.Contact__c","lookupField":"Department"}]}'
            );
            oneObject.Target_Object__c = 'Affiliation__c';
            insert as system oneObject;
            WhereUsedSelector.mergeRulesOverride = new List<Merge_Rule__mdt>{
                new Merge_Rule__mdt(
                    MasterLabel = 'Department Rule',
                    Field_Name__c = 'Department',
                    Active__c = true
                )
            };
            MatchSourceSelector.allSourcesOverride = new List<Match_Source__mdt>{
                new Match_Source__mdt(
                    MasterLabel = 'By Department',
                    Object_Name__c = 'Contact',
                    Value_Field__c = 'Department'
                )
            };

            WhereUsedService.Result result = WhereUsedService.find('Contact', 'Department');

            Assert.areEqual(
                new List<String>{ System.Label.Core_WhereUsed_PartChanges },
                named(result, 'Tidy Titles').parts,
                'A copy source names the field.'
            );
            Assert.areEqual(
                new List<String>{
                    String.format(System.Label.Core_WhereUsed_PartColumn, new List<Object>{ 'Job' })
                },
                named(result, 'People').parts
            );
            Assert.isNotNull(
                named(result, 'Affiliations'),
                'A lookup field names its parent by the field.'
            );
            Assert.isNull(named(result, 'Gifts Only'), 'Core does not read a module entity.');
            Assert.areEqual(1, ofKind(result, WhereUsedService.KIND_MERGE_RULE).size());
            Assert.areEqual(1, ofKind(result, WhereUsedService.KIND_MATCH_SOURCE).size());
            Assert.areEqual(
                NamespaceUtil.qualify('Duplicate_Matching'),
                named(result, 'By Department').editTab
            );
        }
    }

    @IsTest
    static void aMergeRuleOnAnAddressFindsItsParts() {
        System.runAs(TestUsers.admin()) {
            noModules();
            WhereUsedSelector.mergeRulesOverride = new List<Merge_Rule__mdt>{
                new Merge_Rule__mdt(
                    MasterLabel = 'Mailing',
                    Field_Name__c = 'MailingAddress',
                    Active__c = true
                )
            };

            WhereUsedService.Result result = WhereUsedService.find('Contact', 'MailingCity');

            Assert.areEqual(
                1,
                ofKind(result, WhereUsedService.KIND_MERGE_RULE).size(),
                'MailingCity is part of MailingAddress.'
            );
        }
    }

    @IsTest
    static void theAddressCardSettingIsFound() {
        String status = Address__c.Status__c.getDescribe().getName();
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Address_Card_Fields__c = 'Name, ' + status;
            upsert as system settings;
            SettingsService.clearCaches();
            noModules();

            WhereUsedService.Result result = WhereUsedService.find('Address__c', status);
            WhereUsedService.Result other = WhereUsedService.find('Address__c', 'Type__c');

            List<WhereUsedService.Reference> found = ofKind(result, WhereUsedService.KIND_SETTING);
            Assert.areEqual(1, found.size());
            Assert.areEqual(NamespaceUtil.qualify('BarnCRM_Settings'), found[0].editTab);
            Assert.areEqual('Addresses', found[0].editState.get(NamespaceUtil.stateKey('section')));
            Assert.isTrue(result.deletable, 'A custom field of the org can be deleted in Setup.');
            Assert.areEqual(0, ofKind(other, WhereUsedService.KIND_SETTING).size());
        }
    }

    @IsTest
    static void namePatternsAreFoundByTheFieldsTheirBlanksRead() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Household_Name_Pattern__c = 'The {!LastName} Household';
            settings.Formal_Greeting_Pattern__c = '{FirstName} {LastName}';
            settings.Informal_Greeting_Pattern__c = null;
            upsert as system settings;
            SettingsService.clearCaches();
            noModules();

            List<WhereUsedService.Reference> lastName = ofKind(
                WhereUsedService.find('Contact', 'LastName'),
                WhereUsedService.KIND_SETTING
            );
            List<WhereUsedService.Reference> firstName = ofKind(
                WhereUsedService.find('Contact', 'FirstName'),
                WhereUsedService.KIND_SETTING
            );
            List<WhereUsedService.Reference> salutation = ofKind(
                WhereUsedService.find('Contact', 'Salutation'),
                WhereUsedService.KIND_SETTING
            );

            Assert.areEqual(2, lastName.size(), 'The name pattern and the formal greeting.');
            Assert.areEqual(
                2,
                firstName.size(),
                'The formal greeting, and the informal one through its default.'
            );
            Assert.areEqual(0, salutation.size(), 'No pattern in use reads the salutation.');
            Assert.areEqual(System.Label.Core_WhereUsed_BreaksPattern, lastName[0].breaks);
            Assert.areEqual(
                'People and Households',
                lastName[0].editState.get(NamespaceUtil.stateKey('section'))
            );
        }
    }

    @IsTest
    static void aWholeObjectFindsWhatWorksOnIt() {
        System.runAs(TestUsers.admin()) {
            noModules();
            insert as system new List<Saved_Query__c>{
                query(
                    'Through Contact',
                    'Address__c',
                    '{"version":1,"object":"Address__c","fields":["Contact__r.LastName"]}'
                ),
                query(
                    'Not Contact',
                    'Address__c',
                    '{"version":1,"object":"Address__c","fields":["City__c"]}'
                )
            };

            WhereUsedService.Result result = WhereUsedService.find('Contact', null);

            Assert.isNull(result.fieldName);
            Assert.isFalse(result.deletable);
            Assert.areEqual(1, result.references.size(), 'Only the query that reaches Contact.');
            Assert.areEqual('Through Contact', result.references[0].name);
        }
    }

    @IsTest
    static void modulesAreAskedAndAFailingOneMarksTheAnswerIncomplete() {
        System.runAs(TestUsers.admin()) {
            noModules();
            WhereUsedExtensions.overrides.put('RollupsWhereUsedExtension', new FakeExtension());
            WhereUsedExtensions.overrides.put('GivingWhereUsedExtension', new BrokenExtension());

            WhereUsedService.Result result = WhereUsedService.find('Contact', 'Email');

            Assert.areEqual(1, ofKind(result, 'fake').size(), 'The working module is heard.');
            Assert.isTrue(result.incomplete, 'The failing one is reported.');
        }
    }

    @IsTest
    static void aModuleThatIsNotThereIsSkipped() {
        System.runAs(TestUsers.admin()) {
            WhereUsedExtensions.overrides.clear();
            Map<String, WhereUsedExtension> found = WhereUsedExtensions.findAll();
            for (WhereUsedExtension extension : found.values()) {
                Assert.isNotNull(extension, 'Only installed extensions are returned.');
            }
            Assert.isTrue(found.size() <= WhereUsedExtensions.EXTENSION_CLASSES.size());
        }
    }

    @IsTest
    static void unknownNamesAndMissingPermissionAreRefused() {
        User reader;
        System.runAs(TestUsers.admin()) {
            reader = TestUsers.standardUserWith('Rhea', new List<String>{ 'BarnCRM_Read_Only' });
        }
        System.runAs(TestUsers.admin()) {
            noModules();
            for (
                List<String> names : new List<List<String>>{
                    new List<String>{ 'Not_An_Object__c', null },
                    new List<String>{ 'Contact', 'Not_A_Field__c' }
                }
            ) {
                try {
                    WhereUsedController.findReferences(names[0], names[1]);
                    Assert.fail('An unknown name is refused: ' + names);
                } catch (AuraHandledException expected) {
                    Assert.isTrue(expected.getMessage().contains('Not_A'), expected.getMessage());
                }
            }
        }
        System.runAs(reader) {
            try {
                WhereUsedController.findReferences('Contact', 'Email');
                Assert.fail('A person without Manage BarnCRM Settings is refused.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    System.Label.Core_WhereUsed_ErrorNoPermission,
                    expected.getMessage()
                );
            }
        }
    }
}
