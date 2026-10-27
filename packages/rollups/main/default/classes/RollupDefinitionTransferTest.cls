/**
 * Export and import of rollups between orgs (ADR-0136). One org stands in for both: a rollup is
 * exported, deleted, and imported back, and the import is matched by Definition Key. Maria builds
 * rollups, as in `RollupBuilderControllerTest`.
 */
@IsTest(testFor='ApexClass:RollupDefinitionTransfer')
private class RollupDefinitionTransferTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Rollup_Builder_Admin' }
        );
    }

    private static Rollup_Definition__c childCount(String key, String field) {
        return new Rollup_Definition__c(
            Name = 'Child organization count',
            Definition_Key__c = key,
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = field,
            Mode__c = RollupService.MODE_BOTH,
            Active__c = true
        );
    }

    private static Map<String, Object> fileOf(String text) {
        return (Map<String, Object>) JSON.deserializeUntyped(text);
    }

    private static String fileWith(List<Object> rollups) {
        return JSON.serialize(
            new Map<String, Object>{
                'format' => RollupDefinitionTransfer.FORMAT,
                'version' => RollupDefinitionTransfer.FORMAT_VERSION,
                'rollups' => rollups
            }
        );
    }

    @IsTest
    static void exportHoldsOnlyAdminMadeRollupsWithTheirKeysAndNoIdsOrStamps() {
        System.runAs(maria()) {
            Rollup_Definition__c mine = childCount('Custom_Children', 'Member_Count__c');
            mine.Last_Calculated__c = Datetime.now();
            Rollup_Definition__c shipped = childCount('Shipped_Children', 'Member_Count__c');
            shipped.Is_Package_Default__c = true;
            shipped.Active__c = false;
            // The run stamp and the shipped flag are written by the engine and the installer,
            // never by an admin (both are read only in the permission sets), so the test data
            // is written in system mode.
            insert as system new List<Rollup_Definition__c>{ mine, shipped };

            Map<String, Object> file = fileOf(RollupDefinitionTransfer.exportDefinitions(null));

            System.Assert.areEqual(RollupDefinitionTransfer.FORMAT, file.get('format'));
            System.Assert.areEqual(1, file.get('version'), 'The format carries its version');
            List<Object> rollups = (List<Object>) file.get('rollups');
            System.Assert.areEqual(1, rollups.size(), 'A shipped rollup is not exported');
            Map<String, Object> rollup = (Map<String, Object>) rollups[0];
            System.Assert.areEqual('Custom_Children', rollup.get('definitionKey'));
            System.Assert.areEqual('Member_Count__c', rollup.get('targetField'));
            System.Assert.isFalse(rollup.containsKey('recordId'), 'No record Id travels');
            System.Assert.isFalse(rollup.containsKey('lastCalculated'), 'Nor a run stamp');
        }
    }

    @IsTest
    static void anExportedRollupIsCreatedByImportThenUpdatedByItsKey() {
        System.runAs(maria()) {
            Rollup_Definition__c mine = childCount('Custom_Children', 'Member_Count__c');
            insert mine;
            String text = RollupDefinitionTransfer.exportDefinitions(new List<Id>{ mine.Id });
            delete mine;

            List<RollupDefinitionTransfer.TransferRow> preview = RollupDefinitionTransfer.importDefinitions(
                text,
                false
            );
            System.Assert.areEqual(RollupDefinitionTransfer.CREATED, preview[0].outcome);
            System.Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Rollup_Definition__c
                    WHERE Definition_Key__c = 'Custom_Children'
                ],
                'A preview saves nothing'
            );

            RollupDefinitionTransfer.importDefinitions(text, true);
            Rollup_Definition__c created = [
                SELECT Id, Name, Active__c, Is_Package_Default__c
                FROM Rollup_Definition__c
                WHERE Definition_Key__c = 'Custom_Children'
            ];
            System.Assert.isTrue(
                created.Active__c,
                'It keeps its Active value: every check passed'
            );
            System.Assert.isFalse(created.Is_Package_Default__c);

            Map<String, Object> file = fileOf(text);
            ((Map<String, Object>) ((List<Object>) file.get('rollups'))[0]).put('name', 'Children');
            List<RollupDefinitionTransfer.TransferRow> rows = RollupDefinitionTransfer.importDefinitions(
                JSON.serialize(file),
                true
            );
            System.Assert.areEqual(RollupDefinitionTransfer.UPDATED, rows[0].outcome);
            System.Assert.areEqual(
                'Children',
                [SELECT Name FROM Rollup_Definition__c WHERE Id = :created.Id].Name,
                'Matched by Definition Key, the same record is updated'
            );
        }
    }

    @IsTest
    static void eachRollupIsRefusedOnItsOwnWithTheReason() {
        System.runAs(maria()) {
            Rollup_Definition__c shipped = childCount('Shipped_Children', 'Member_Count__c');
            shipped.Is_Package_Default__c = true;
            // The installer writes the shipped flag, never an admin: system mode.
            insert as system shipped;
            Map<String, Object> good = new Map<String, Object>{
                'definitionKey' => 'Custom_Good',
                'name' => 'Good',
                'targetObject' => 'Account',
                'targetField' => 'Member_Count__c',
                'sourceObject' => 'Account',
                'relationshipPath' => 'ParentId',
                'aggregate' => 'COUNT',
                'active' => false
            };
            Map<String, Object> nameless = good.clone();
            nameless.put('definitionKey', 'Custom_Nameless');
            nameless.put('name', '');
            Map<String, Object> newer = good.clone();
            newer.put('definitionKey', 'Custom_Newer');
            newer.put('notAnAttribute', 3);
            Map<String, Object> overlapping = good.clone();
            overlapping.put('definitionKey', 'Custom_Overlap');
            overlapping.put('active', true);

            List<RollupDefinitionTransfer.TransferRow> rows = RollupDefinitionTransfer.importDefinitions(
                fileWith(
                    new List<Object>{ good, good, nameless, newer, shippedEntry(good), overlapping }
                ),
                true
            );

            System.Assert.areEqual(RollupDefinitionTransfer.CREATED, rows[0].outcome);
            System.Assert.areEqual(Label.Core_RollupBuilder_ImportTwice, rows[1].reason);
            System.Assert.areEqual(Label.Core_RollupBuilder_ErrorNameNeeded, rows[2].reason);
            System.Assert.isTrue(rows[3].reason.contains('notAnAttribute'), rows[3].reason);
            System.Assert.areEqual(Label.Core_RollupBuilder_ImportShipped, rows[4].reason);
            System.Assert.areEqual(
                RollupDefinitionTransfer.REFUSED,
                rows[5].outcome,
                'R-R8: an active rollup on the field the shipped one fills is refused'
            );
            System.Assert.areEqual(
                1,
                [SELECT COUNT() FROM Rollup_Definition__c WHERE Definition_Key__c LIKE 'Custom%'],
                'Only the good rollup is saved'
            );
        }
    }

    private static Map<String, Object> shippedEntry(Map<String, Object> good) {
        Map<String, Object> entry = good.clone();
        entry.put('definitionKey', 'Shipped_Children');
        return entry;
    }

    @IsTest
    static void aFileThatIsNotAnExportOrIsNewerIsRefused() {
        System.runAs(maria()) {
            List<String> messages = new List<String>();
            for (
                String text : new List<String>{
                    'not json',
                    '{"format":"something else","version":1,"rollups":[]}',
                    '{"format":"BarnCRM rollups","version":2,"rollups":[]}'
                }
            ) {
                try {
                    RollupDefinitionTransfer.importDefinitions(text, false);
                } catch (AuraHandledException refused) {
                    messages.add(refused.getMessage());
                }
            }
            System.Assert.areEqual(
                new List<String>{
                    Label.Core_RollupBuilder_ImportNotAFile,
                    Label.Core_RollupBuilder_ImportNotAFile,
                    Label.Core_RollupBuilder_ImportNewer
                },
                messages
            );
        }
    }

    @IsTest
    static void nothingToExportAndStaffAreRefusedInPlainWords() {
        // Made by the running administrator: Maria, on a Standard User profile, cannot create users.
        User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
        System.runAs(maria()) {
            List<String> messages = new List<String>();
            try {
                RollupDefinitionTransfer.exportDefinitions(new List<Id>());
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            System.runAs(david) {
                try {
                    RollupDefinitionTransfer.importDefinitions(fileWith(new List<Object>()), true);
                } catch (AuraHandledException refused) {
                    messages.add(refused.getMessage());
                }
            }
            System.Assert.areEqual(
                new List<String>{
                    Label.Core_RollupBuilder_ExportNothing,
                    Label.Core_Rollups_ErrorNoPermission
                },
                messages
            );
        }
    }
}
