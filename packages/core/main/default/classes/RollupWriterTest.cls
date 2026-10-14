/**
 * The changed-only write of BarnCRM's own rollup engine (rollup proposal S5, "Changed-only
 * writes"): a record is saved only when a total changed, and values are compared as stored.
 */
@IsTest(testFor='ApexClass:RollupWriter')
private class RollupWriterTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /**
     * The freshness stamp is written wherever the entity has one that is not calculated,
     * whatever the running user may edit: the Rollup Queue runs as the Automated Process user,
     * and import undo reads the stamp to tell a rollup's save from an edit (ADR-NEXT).
     */
    @IsTest
    static void theStampIsFoundByTheFieldNotTheUsersAccess() {
        User noAccess = TestUsers.standardUser('Stamp');
        System.runAs(noAccess) {
            Schema.SObjectField onContact = RollupWriter.freshnessField(Contact.SObjectType);
            Schema.SObjectField declared = Contact.SObjectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .fields.getMap()
                .get(RollupService.FRESHNESS_FIELD);
            Assert.areEqual(declared, onContact, 'Found when Contact has it, whoever runs.');
            Assert.isNull(
                RollupWriter.freshnessField(Rollup_Queue__c.SObjectType),
                'None where the entity has none.'
            );
            Assert.areEqual(
                0,
                RollupWriter.writeTotals(null, null, null, Datetime.now()).written.size(),
                'Nothing to write, nothing written.'
            );
            RollupWriter.insertDefinitions(new List<Rollup_Definition__c>());
            RollupWriter.stampDefinitions(new Map<Id, Datetime>());
        }
    }

    @IsTest
    static void valuesAreComparedAsTheyWouldBeStored() {
        System.runAs(TestUsers.admin()) {
            Schema.DescribeFieldResult wholeNumber = Account.Member_Count__c.getDescribe();
            Assert.isTrue(
                (Decimal) RollupWriter.coerce(wholeNumber, 33.333) == 33,
                'Rounded to the scale'
            );
            Assert.isTrue(RollupWriter.sameValue(1.0, 1.00), 'Scale alone is no change');
            Assert.isTrue(RollupWriter.sameValue(3, 3.0), 'A whole number and a decimal');
            Assert.isFalse(RollupWriter.sameValue(null, 0), 'Blank and zero differ');
            Assert.areEqual(
                Date.newInstance(2024, 1, 2),
                RollupWriter.coerce(
                    Account.Anniversary__c.getDescribe(),
                    Datetime.newInstance(2024, 1, 2, 10, 0, 0)
                ),
                'A datetime into a date attribute'
            );
        }
    }

    @IsTest
    static void onlyRecordsWithAChangedTotalAreSaved() {
        System.runAs(TestUsers.admin()) {
            Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId();
            Account same = new Account(
                Name = 'Same',
                RecordTypeId = organizationType,
                Member_Count__c = 2
            );
            Account changed = new Account(
                Name = 'Changed',
                RecordTypeId = organizationType,
                Member_Count__c = 2
            );
            insert new List<Account>{ same, changed };
            Set<Id> both = new Set<Id>{ same.Id, changed.Id };
            Map<Id, SObject> stored = new Map<Id, SObject>(
                [SELECT Id, Member_Count__c FROM Account WHERE Id IN :both]
            );
            Map<Id, Map<Schema.SObjectField, Object>> computed = new Map<Id, Map<Schema.SObjectField, Object>>{
                same.Id => new Map<Schema.SObjectField, Object>{ Account.Member_Count__c => 2.0 },
                changed.Id => new Map<Schema.SObjectField, Object>{ Account.Member_Count__c => 5 }
            };

            RollupWriter.TotalsWrite result = RollupWriter.writeTotals(
                Account.SObjectType,
                stored,
                computed,
                Datetime.now()
            );

            Assert.areEqual(new Set<Id>{ changed.Id }, result.written, 'Only the changed record');
            Assert.areEqual(
                5,
                [SELECT Member_Count__c FROM Account WHERE Id = :changed.Id].Member_Count__c,
                'Saved'
            );
        }
    }
}
