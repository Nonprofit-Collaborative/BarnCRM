/**
 * What a one-object template may name, read from the running user's describe (canonical model
 * R-IT12 to R-IT14): the objects offered, the fields a column and a lookup may use, the upsert
 * keys, the refusals before any row is read, and a cell read as its field's type.
 *
 * Runs as a minimal-profile user holding only BarnCRM Admin, since what describe answers is
 * that user's access.
 */
@IsTest
private class ImportObjectSchemaTest {
    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static Import_Template__c template(String objectName, String operation, String key) {
        return new Import_Template__c(
            Name = 'One object',
            Target_Object__c = objectName,
            Load_Operation__c = operation,
            Load_Match_Field__c = key
        );
    }

    private static ImportMapping mapping(List<String> attributes) {
        ImportMapping result = new ImportMapping();
        for (String attribute : attributes) {
            result.columns.add(
                new ImportMapping.Column(attribute, ImportMapping.ENTITY_RECORD + '.' + attribute)
            );
        }
        return result;
    }

    private static Set<String> values(List<ImportMapping.Target> targets) {
        Set<String> result = new Set<String>();
        for (ImportMapping.Target target : targets) {
            result.add(target.value.toLowerCase());
        }
        return result;
    }

    @IsTest
    static void theObjectsOfferedAreTheOnesTheRuleAndTheUsersAccessAllow() {
        System.runAs(TestUsers.admin()) {
            DataProtectionExtensions.noneForTest = true;
            Set<String> offered;
            Test.startTest();
            System.runAs(admin()) {
                offered = values(ImportObjectSchema.loadableObjects());
            }
            Test.stopTest();

            String affiliation = Affiliation__c.SObjectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .getName()
                .toLowerCase();
            Assert.isTrue(
                offered.contains(affiliation),
                'An object of the org the user may write.'
            );
            Assert.isTrue(offered.contains('contact'), 'People, for updates.');
            Assert.isFalse(offered.contains('user'), 'Never a setup object.');
            Assert.isFalse(
                offered.contains(
                    Import_Batch__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getName()
                        .toLowerCase()
                ),
                'Never the package bookkeeping.'
            );
        }
    }

    @IsTest
    static void theTemplateSaysWhatItLoadsAndHow() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c people = new Import_Template__c(Name = 'People');
            Import_Template__c load = template('Affiliation__c', 'upsert by external id', null);
            load.Lookup_Not_Found__c = ImportObjectSchema.LOOKUP_LEAVE_EMPTY;

            Assert.isFalse(
                ImportObjectSchema.loadsOneObject(people),
                'No object, a people mapping.'
            );
            Assert.isTrue(ImportObjectSchema.loadsOneObject(load), 'An object, a one-object load.');
            Assert.areEqual(
                Affiliation__c.SObjectType,
                ImportObjectSchema.typeOf(load),
                'Its type.'
            );
            Assert.isNull(ImportObjectSchema.typeNamed('No_Such_Object__c'), 'An unknown name.');
            Assert.isNull(ImportObjectSchema.typeNamed(' '), 'A blank name.');
            Assert.areEqual(
                ImportObjectSchema.OPERATION_UPSERT,
                ImportObjectSchema.operationOf(load),
                'Read ignoring case.'
            );
            Assert.areEqual(
                ImportObjectSchema.OPERATION_INSERT,
                ImportObjectSchema.operationOf(people),
                'Empty is Insert.'
            );
            Assert.isTrue(ImportObjectSchema.leavesLookupEmpty(load), 'Leave it empty.');
            Assert.isFalse(ImportObjectSchema.leavesLookupEmpty(people), 'Reject is the default.');
            Assert.areEqual(
                new List<String>{ ImportObjectSchema.OPERATION_UPDATE },
                ImportObjectSchema.operationsFor(Contact.SObjectType),
                'People load by Update only.'
            );
            Assert.areEqual(
                3,
                ImportObjectSchema.operationsFor(Affiliation__c.SObjectType).size(),
                'Any other object has all three.'
            );
        }
    }

    @IsTest
    static void anUpsertMatchesOnExternalIdFieldsOnly() {
        System.runAs(TestUsers.admin()) {
            List<ImportMapping.Target> keys;
            String pairKey;
            String role;
            Test.startTest();
            System.runAs(admin()) {
                keys = ImportObjectSchema.keyFields(Duplicate_Dismissal__c.SObjectType);
                pairKey = ImportObjectSchema.keyField(
                    Duplicate_Dismissal__c.SObjectType,
                    ' pair_key__c '
                );
                role = ImportObjectSchema.keyField(Affiliation__c.SObjectType, 'Role__c');
            }
            Test.stopTest();

            Assert.areEqual(1, keys.size(), 'The pair key is the external ID.');
            Assert.isTrue(pairKey.endsWithIgnoreCase('Pair_Key__c'), 'Named as describe names it.');
            Assert.isNull(role, 'A plain text field is not a key.');
            Assert.isNull(
                ImportObjectSchema.keyField(Duplicate_Dismissal__c.SObjectType, ''),
                'Nothing chosen, nothing matched.'
            );
        }
    }

    @IsTest
    static void aColumnMayFillTheFieldsTheUserMayWriteAndNoProtectedOne() {
        System.runAs(TestUsers.admin()) {
            List<ImportMapping.Target> fields;
            Test.startTest();
            System.runAs(admin()) {
                fields = ImportObjectSchema.writableFields(Affiliation__c.SObjectType);
            }
            Test.stopTest();

            Set<String> offered = values(fields);
            Assert.areEqual(
                ImportObjectSchema.ID_ATTRIBUTE,
                fields[0].value,
                'The record ID first.'
            );
            Assert.isTrue(offered.contains('role__c'), 'A text field.');
            Assert.isTrue(offered.contains('start_date__c'), 'A date.');
            Assert.isTrue(offered.contains('contact__c'), 'A lookup.');
            Assert.isFalse(offered.contains('sample_data__c'), 'The sample data mark is kept.');
            Assert.isFalse(offered.contains('createddate'), 'A system field is kept.');
            Assert.isFalse(offered.contains('name'), 'An auto number is never written.');
        }
    }

    @IsTest
    static void aLookupNamesItsParentByIdNameOrAUniqueField() {
        System.runAs(TestUsers.admin()) {
            List<ImportMapping.Target> byContact;
            List<ImportMapping.Target> polymorphic;
            Test.startTest();
            System.runAs(admin()) {
                byContact = ImportObjectSchema.parentFields(
                    Affiliation__c.SObjectType,
                    'Contact__c'
                );
                polymorphic = ImportObjectSchema.parentFields(Task.SObjectType, 'WhoId');
            }
            Test.stopTest();

            Assert.areEqual(ImportObjectSchema.ID_ATTRIBUTE, byContact[0].value, 'ID first.');
            Assert.areEqual('Name', byContact[1].value, 'Then the name.');
            Assert.areEqual(1, polymorphic.size(), 'A lookup to several objects by ID only.');
            Assert.areEqual(
                Contact.SObjectType,
                ImportObjectSchema.parentOf(Affiliation__c.SObjectType, 'contact__c'),
                'The parent, ignoring case.'
            );
            Assert.isNull(
                ImportObjectSchema.parentOf(Affiliation__c.SObjectType, 'Role__c'),
                'Not a lookup.'
            );
            Assert.areEqual(
                'Name',
                ImportObjectSchema.parentField(Account.SObjectType, 'name'),
                'The name field.'
            );
            Assert.isNull(
                ImportObjectSchema.parentField(Account.SObjectType, 'Phone'),
                'A field that does not name one record.'
            );
        }
    }

    @IsTest
    static void aMappingIsSuggestedFromHeadingsNeverGuessed() {
        System.runAs(TestUsers.admin()) {
            ImportMapping suggested;
            Test.startTest();
            System.runAs(admin()) {
                suggested = ImportObjectSchema.suggestMapping(
                    Affiliation__c.SObjectType,
                    new List<String>{
                        'Role',
                        'Start Date',
                        'Contact__c',
                        'Record ID',
                        'Mystery',
                        'role'
                    }
                );
            }
            Test.stopTest();

            List<String> targets = new List<String>();
            for (ImportMapping.Column column : suggested.columns) {
                targets.add(ImportMapping.attributeOf(column.target));
            }
            Assert.isTrue(targets[0].endsWithIgnoreCase('Role__c'), 'By label.');
            Assert.isTrue(targets[1].endsWithIgnoreCase('Start_Date__c'), 'Ignoring spaces.');
            Assert.isTrue(targets[2].endsWithIgnoreCase('Contact__c'), 'By API name.');
            Assert.areEqual(ImportObjectSchema.ID_ATTRIBUTE, targets[3], 'The record ID.');
            Assert.areEqual(
                ImportMapping.TARGET_IGNORE,
                suggested.columns[4].target,
                'Not guessed.'
            );
            Assert.areEqual(
                ImportMapping.TARGET_IGNORE,
                suggested.columns[5].target,
                'A second heading for one field is left alone.'
            );
            Assert.areEqual(
                ImportMapping.ENTITY_RECORD,
                ImportMapping.entityOf(suggested.columns[0].target),
                'Targets are Record fields.'
            );
        }
    }

    @IsTest
    static void aTemplateThatCannotLoadIsRefusedWithAReason() {
        System.runAs(TestUsers.admin()) {
            DataProtectionExtensions.noneForTest = true;
            Map<String, String> refusals = new Map<String, String>();
            ImportMapping withKey = mapping(new List<String>{ 'Pair_Key__c', 'Reason__c' });
            ImportMapping keyForEveryRow = mapping(new List<String>{ 'Reason__c' });
            keyForEveryRow.defaults.add(new ImportMapping.Assignment('Record.Pair_Key__c', 'same'));
            ImportMapping idForEveryRow = mapping(new List<String>{ 'Reason__c' });
            idForEveryRow.defaults.add(
                new ImportMapping.Assignment('Record.Id', 'a0B000000000001')
            );
            String dismissal = 'Duplicate_Dismissal__c';
            String byKey = ImportObjectSchema.OPERATION_UPSERT;
            String byId = ImportObjectSchema.OPERATION_UPDATE;

            Test.startTest();
            System.runAs(admin()) {
                refusals.put(
                    'bookkeeping',
                    ImportObjectSchema.refusal(template('Import_Batch__c', null, null), withKey)
                );
                refusals.put(
                    'insertPeople',
                    ImportObjectSchema.refusal(template('Contact', null, null), withKey)
                );
                refusals.put(
                    'nothing',
                    ImportObjectSchema.refusal(template(dismissal, null, null), new ImportMapping())
                );
                refusals.put(
                    'noId',
                    ImportObjectSchema.refusal(template(dismissal, byId, null), withKey)
                );
                refusals.put(
                    'noKey',
                    ImportObjectSchema.refusal(template(dismissal, byKey, null), withKey)
                );
                refusals.put(
                    'badKey',
                    ImportObjectSchema.refusal(template(dismissal, byKey, 'Reason__c'), withKey)
                );
                refusals.put(
                    'keyUnmapped',
                    ImportObjectSchema.refusal(
                        template(dismissal, byKey, 'Pair_Key__c'),
                        mapping(new List<String>{ 'Reason__c' })
                    )
                );
                refusals.put(
                    'keyForEveryRow',
                    ImportObjectSchema.refusal(
                        template(dismissal, byKey, 'Pair_Key__c'),
                        keyForEveryRow
                    )
                );
                refusals.put(
                    'idForEveryRow',
                    ImportObjectSchema.refusal(template(dismissal, byId, null), idForEveryRow)
                );
                refusals.put(
                    'good',
                    ImportObjectSchema.refusal(template(dismissal, byKey, 'Pair_Key__c'), withKey)
                );
                refusals.put(
                    'updatePeople',
                    ImportObjectSchema.refusal(
                        template('Contact', byId, null),
                        mapping(new List<String>{ 'Id', 'Title' })
                    )
                );
            }
            Test.stopTest();

            Assert.isNotNull(
                refusals.get('bookkeeping'),
                'The package bookkeeping is never loaded.'
            );
            Assert.areEqual(
                String.format(
                    Label.Core_Import_ErrorPeopleUpdateOnly,
                    new List<String>{
                        Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                            .getLabelPlural()
                    }
                ),
                refusals.get('insertPeople'),
                'People are inserted by a people mapping.'
            );
            Assert.areEqual(
                Label.Core_Import_ErrorNothingMapped,
                refusals.get('nothing'),
                'Empty.'
            );
            Assert.areEqual(Label.Core_Import_ErrorIdColumnMissing, refusals.get('noId'), 'No ID.');
            Assert.areEqual(
                Label.Core_Import_ErrorKeyFieldRequired,
                refusals.get('noKey'),
                'No key.'
            );
            Assert.isTrue(
                refusals.get('badKey').contains('Reason__c'),
                'A field that is not an external ID is named.'
            );
            Assert.isTrue(
                refusals.get('keyUnmapped').contains('Pair Key'),
                'The key column is named by its label.'
            );
            Assert.isTrue(
                refusals.get('keyForEveryRow').contains('Pair Key'),
                'The key cannot be a value for every row.'
            );
            Assert.isTrue(
                refusals.get('idForEveryRow').contains(Label.Core_Import_RecordIdOption),
                'Nor the record ID.'
            );
            Assert.isNull(refusals.get('good'), 'A complete upsert loads.');
            Assert.isNull(refusals.get('updatePeople'), 'People may be updated by ID.');
        }
    }

    @IsTest
    static void aUserWithoutAccessIsRefused() {
        System.runAs(TestUsers.admin()) {
            DataProtectionExtensions.noneForTest = true;
            User nobody = TestDataFactory.createUser('Nobody', new List<String>());
            String refused;
            List<ImportMapping.Target> offered;

            Test.startTest();
            System.runAs(nobody) {
                refused = ImportObjectSchema.refusal(
                    template('Duplicate_Dismissal__c', null, null),
                    mapping(new List<String>{ 'Pair_Key__c' })
                );
                offered = ImportObjectSchema.loadableObjects();
            }
            Test.stopTest();

            Assert.isNotNull(refused, 'No access to the object, no load.');
            Assert.isFalse(
                values(offered)
                    .contains(
                        Duplicate_Dismissal__c.SObjectType.getDescribe(
                                SObjectDescribeOptions.DEFERRED
                            )
                            .getName()
                            .toLowerCase()
                    ),
                'Nor is it offered.'
            );
        }
    }

    @IsTest
    static void aCellIsReadAsItsFieldsTypeOrRejected() {
        System.runAs(TestUsers.admin()) {
            Schema.DescribeFieldResult startDate = Affiliation__c.Start_Date__c.getDescribe();
            Schema.DescribeFieldResult primary = Affiliation__c.Is_Primary__c.getDescribe();
            Schema.DescribeFieldResult role = Affiliation__c.Role__c.getDescribe();
            Schema.DescribeFieldResult revenue = Account.AnnualRevenue.getDescribe();
            Schema.DescribeFieldResult employees = Account.NumberOfEmployees.getDescribe();
            Schema.DescribeFieldResult reminder = Task.ReminderDateTime.getDescribe();
            Date day = Date.newInstance(2026, 10, 12);

            Test.startTest();
            Object iso = ImportObjectSchema.typed('2026-10-12', startDate);
            Object local = ImportObjectSchema.typed(day.format(), startDate);
            Object yes = ImportObjectSchema.typed('Yes', primary);
            Object no = ImportObjectSchema.typed('0', primary);
            Object amount = ImportObjectSchema.typed('$1,234.50', revenue);
            Object count = ImportObjectSchema.typed('1,200', employees);
            Object stamp = ImportObjectSchema.typed('2026-10-12T09:30:00Z', reminder);
            String maybe = ImportObjectSchema.unreadable('maybe', primary);
            String letters = ImportObjectSchema.unreadable('twelve', employees);
            String badDate = ImportObjectSchema.unreadable('soon', startDate);
            String tooLong = ImportObjectSchema.unreadable('x'.repeat(256), role);
            String fine = ImportObjectSchema.unreadable('Volunteer', role);
            Test.stopTest();

            Assert.areEqual(day, iso, 'ISO 8601.');
            Assert.areEqual(day, local, 'The user locale.');
            Assert.areEqual(true, yes, 'Yes is checked.');
            Assert.areEqual(false, no, 'Zero is not.');
            Assert.areEqual(1234.50, (Decimal) amount, 'Separators and sign dropped.');
            Assert.areEqual(1200, (Integer) count, 'A whole number.');
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 10, 12, 9, 30, 0),
                stamp,
                'A date and time in ISO 8601.'
            );
            Assert.isTrue(maybe.contains('maybe'), 'Neither yes nor no is named.');
            Assert.isNotNull(letters, 'Letters in a number.');
            Assert.isNotNull(badDate, 'A date that cannot be read.');
            Assert.isTrue(tooLong.contains('255'), 'Longer than the field holds.');
            Assert.isNull(fine, 'A value the field takes.');
        }
    }

    @IsTest
    static void aTimeIsReadOnTheClock() {
        System.runAs(TestUsers.admin()) {
            Schema.DescribeFieldResult opens = BusinessHours.MondayStartTime.getDescribe();

            Assert.areEqual(
                Time.newInstance(9, 30, 0, 0),
                ImportObjectSchema.typed('9:30', opens),
                'h:mm.'
            );
            Assert.isNotNull(ImportObjectSchema.unreadable('25:00', opens), 'Past midnight.');
            Assert.isNotNull(ImportObjectSchema.unreadable('noon', opens), 'Not a time.');
        }
    }
}
