/**
 * The Field Access Manager (C-65, canonical model R-FA1 to R-FA7): preview, apply, record and
 * undo of Read and Edit on permission sets the organization made. Tests run as the admin test
 * user (the running user's profile, which holds Manage Profiles and Permission Sets, plus
 * BarnCRM Admin) and make their own permission sets. Setup rows and the data job cannot share a
 * transaction, so each is written in a `System.runAs` block of its own.
 */
@IsTest(
    testFor='ApexClass:FieldAccessService, ApexClass:FieldAccessController, ApexClass:FieldAccessRecordJob'
)
private class FieldAccessServiceTest {
    private static final String RELATIONSHIP = Relationship__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getName();
    private static final String DESCRIPTION = Relationship__c.Description__c.getDescribe()
        .getName();
    private static final String START_DATE = Relationship__c.Start_Date__c.getDescribe().getName();

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static PermissionSet newSet(String name) {
        PermissionSet created = new PermissionSet(Name = name, Label = name.replace('_', ' '));
        insert as system created;
        return created;
    }

    private static void grantRelationship(Id setId, Boolean descriptionEdit) {
        insert as system new ObjectPermissions(
            ParentId = setId,
            SobjectType = RELATIONSHIP,
            PermissionsRead = true,
            PermissionsEdit = true
        );
        insert as system new FieldPermissions(
            ParentId = setId,
            SobjectType = RELATIONSHIP,
            Field = RELATIONSHIP + '.' + DESCRIPTION,
            PermissionsRead = true,
            PermissionsEdit = descriptionEdit
        );
    }

    private static String change(List<Id> setIds, List<Map<String, Object>> items) {
        return JSON.serialize(
            new Map<String, Object>{ 'version' => 1, 'setIds' => setIds, 'items' => items }
        );
    }

    private static Map<String, Object> item(String objectName, String field, String access) {
        return new Map<String, Object>{
            'object' => objectName,
            'field' => field,
            'access' => access
        };
    }

    private static FieldPermissions fieldRow(Id setId, String field) {
        List<FieldPermissions> rows = [
            SELECT Id, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE ParentId = :setId AND Field = :(RELATIONSHIP + '.' + field)
            WITH SYSTEM_MODE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static ObjectPermissions objectRow(Id setId) {
        List<ObjectPermissions> rows = [
            SELECT Id, PermissionsRead, PermissionsEdit, PermissionsDelete
            FROM ObjectPermissions
            WHERE ParentId = :setId AND SobjectType = :RELATIONSHIP
            WITH SYSTEM_MODE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Import_Batch__c accessJob() {
        return [
            SELECT
                Id,
                Status__c,
                Rows_Updated__c,
                Rows_Rejected__c,
                Undo_Deadline__c,
                Operation_JSON__c
            FROM Import_Batch__c
            WHERE Operation__c = :FieldAccessService.OPERATION_ACCESS
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    @IsTest
    static void refusedWithoutManageProfilesAndPermissionSets() {
        System.runAs(TestUsers.admin()) {
            FieldAccessService.manageProfilesOverride = false;
            FieldAccessController.Status status = FieldAccessController.getStatus();
            Assert.isFalse(status.canChange, 'Without the system permission nothing may change.');
            Assert.areEqual(
                BarnHelp.text('Core', 'Core_FieldAccess_NeedsManageProfiles'),
                status.reason
            );
            try {
                FieldAccessController.searchSets('Test');
                Assert.fail('A search without the permission must be refused.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    BarnHelp.text('Core', 'Core_FieldAccess_NeedsManageProfiles'),
                    expected.getMessage()
                );
            }
        }
    }

    @IsTest
    static void searchOffersOnlySetsTheOrganizationMade() {
        System.runAs(TestUsers.admin()) {
            Assert.isTrue(
                FieldAccessController.getStatus().canChange,
                'The admin may change access.'
            );
            PermissionSet own = newSet('FAM_Search_Own');
            List<FieldAccessController.SetChoice> found = FieldAccessController.searchSets(
                'FAM Search'
            );
            Assert.areEqual(1, found.size(), 'The set the test made is offered.');
            Assert.areEqual(String.valueOf(own.Id), found[0].id);
            Assert.areEqual(
                0,
                FieldAccessController.searchSets('F').size(),
                'One letter searches nothing.'
            );
            PermissionSet profileSet = [
                SELECT Id
                FROM PermissionSet
                WHERE IsOwnedByProfile = TRUE
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            try {
                FieldAccessService.requireSets(new List<Object>{ profileSet.Id });
                Assert.fail('A profile must never be changed.');
            } catch (FieldAccessService.FieldAccessException expected) {
                Assert.areEqual(
                    BarnHelp.text('Core', 'Core_FieldAccess_SetNotAllowed'),
                    expected.getMessage()
                );
            }
        }
    }

    @IsTest
    static void neverOffersAPermissionSetBarnCrmShips() {
        Assert.isTrue(
            BarnCRMShippedPermissionSets.NAMES.contains(HealthCheckService.PERMISSION_SET_ADMIN),
            'The generated list holds the sets Core ships.'
        );
        System.runAs(TestUsers.admin()) {
            // BarnCRM_Admin is installed with Core, unpackaged or not.
            PermissionSet shipped = [
                SELECT Id, Label
                FROM PermissionSet
                WHERE Name = :HealthCheckService.PERMISSION_SET_ADMIN
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            for (
                FieldAccessController.SetChoice choice : FieldAccessController.searchSets(
                    shipped.Label
                )
            ) {
                Assert.areNotEqual(
                    String.valueOf(shipped.Id),
                    choice.id,
                    'A set BarnCRM ships is never offered.'
                );
            }
            try {
                FieldAccessService.requireSets(new List<Object>{ shipped.Id });
                Assert.fail('A set BarnCRM ships must never be changed.');
            } catch (FieldAccessService.FieldAccessException expected) {
                Assert.areEqual(
                    BarnHelp.text('Core', 'Core_FieldAccess_SetNotAllowed'),
                    expected.getMessage()
                );
            }
        }
    }

    @IsTest
    static void fieldsListChangeableFieldsWithTodaysAccess() {
        System.runAs(TestUsers.admin()) {
            PermissionSet given = newSet('FAM_Fields_Given');
            PermissionSet empty = newSet('FAM_Fields_Empty');
            grantRelationship(given.Id, false);
            FieldAccessController.FieldList listed = FieldAccessController.getFields(
                RELATIONSHIP,
                new List<String>{ given.Id, empty.Id }
            );
            Assert.areEqual(2, listed.setCount);
            Assert.areEqual(2, listed.objectAccess.size());
            FieldAccessController.FieldOption offered;
            for (FieldAccessController.FieldOption option : listed.fields) {
                Assert.areNotEqual(
                    'Name',
                    option.name,
                    'Name cannot be restricted, so it is not offered.'
                );
                if (option.name == DESCRIPTION) {
                    offered = option;
                }
            }
            Assert.isNotNull(offered, 'Description is offered.');
            Assert.areEqual(1, offered.readCount, 'One of the two sets reads it.');
            Assert.areEqual(0, offered.editCount, 'Neither edits it.');
        }
    }

    @IsTest
    static void previewAddsObjectReadNeededForFieldAccess() {
        System.runAs(TestUsers.admin()) {
            PermissionSet empty = newSet('FAM_Preview_Empty');
            FieldAccessController.Preview preview = FieldAccessController.preview(
                change(
                    new List<Id>{ empty.Id },
                    new List<Map<String, Object>>{
                        item(RELATIONSHIP, DESCRIPTION, FieldAccessService.EDIT)
                    }
                )
            );
            Assert.areEqual(2, preview.changed, 'The field and the object Read it needs.');
            Assert.areEqual(0, preview.unchanged);
            Assert.isNull(preview.rows[0].fieldName, 'The kind of record comes first.');
            Assert.areEqual(FieldAccessService.WHY_NEEDED, preview.rows[0].reason);
            Assert.isTrue(preview.rows[0].afterRead);
            Assert.isFalse(preview.rows[0].afterEdit, 'Field access needs only object Read.');
            Assert.areEqual(DESCRIPTION, preview.rows[1].fieldName);
            Assert.isTrue(
                preview.rows[1].afterRead && preview.rows[1].afterEdit,
                'Edit gives Read.'
            );
            Assert.areEqual(FieldAccessService.WHY_ASKED, preview.rows[1].reason);
            Assert.isNull(objectRow(empty.Id), 'A preview writes nothing.');
        }
    }

    @IsTest
    static void applyWritesRecordsAndUndoPutsBack() {
        PermissionSet empty;
        String document;
        System.runAs(TestUsers.admin()) {
            empty = newSet('FAM_Apply_Empty');
            document = change(
                new List<Id>{ empty.Id },
                new List<Map<String, Object>>{
                    item(RELATIONSHIP, RELATIONSHIP + '.' + DESCRIPTION, FieldAccessService.EDIT),
                    item(RELATIONSHIP, START_DATE, FieldAccessService.READ)
                }
            );
            Test.startTest();
            FieldAccessController.Outcome done = FieldAccessController.apply(document, 3);
            Test.stopTest();
            Assert.areEqual(3, done.changed);
            Assert.areEqual(0, done.refused);
        }
        Import_Batch__c job = accessJob();
        Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'The record job ran.');
        Assert.areEqual(3, job.Rows_Updated__c.intValue());
        Assert.isTrue(job.Undo_Deadline__c > Datetime.now());
        Assert.isTrue(job.Operation_JSON__c.contains('"confirmedCount":3'));
        Assert.areEqual(
            3,
            ImportJournalService.entryCount(job.Id, ImportJournalService.PHASE_COMMIT),
            'Every row written is journaled.'
        );
        Assert.isTrue(fieldRow(empty.Id, DESCRIPTION).PermissionsEdit);
        Assert.isTrue(objectRow(empty.Id).PermissionsRead);
        System.runAs(TestUsers.admin()) {
            List<FieldAccessController.ChangeJob> listed = FieldAccessController.listChanges();
            Assert.areEqual(String.valueOf(job.Id), listed[0].id);
            Assert.isTrue(listed[0].canUndo, 'A complete change inside its window can be undone.');
            Assert.areEqual(
                BarnHelp.text('Core', 'Core_Import_UndoErrorAccessChange'),
                ImportUndoService.preview(job.Id).reason,
                'The import undo refuses an access change.'
            );
            FieldAccessController.Outcome undone = FieldAccessController.undo(job.Id);
            Assert.areEqual(3, undone.changed, 'Every row is put back.');
            Assert.areEqual(0, undone.kept);
        }
        Assert.isNull(fieldRow(empty.Id, DESCRIPTION), 'A row the change created is deleted.');
        Assert.isNull(fieldRow(empty.Id, START_DATE));
        Assert.isNull(objectRow(empty.Id));
    }

    @IsTest
    static void applyRefusesWhenTheCountChanged() {
        System.runAs(TestUsers.admin()) {
            PermissionSet empty = newSet('FAM_Count_Empty');
            String document = change(
                new List<Id>{ empty.Id },
                new List<Map<String, Object>>{ item(RELATIONSHIP, null, FieldAccessService.READ) }
            );
            try {
                FieldAccessController.apply(document, 5);
                Assert.fail('A count other than the preview must be refused.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    String.format(
                        BarnHelp.text('Core', 'Core_FieldAccess_CountChanged'),
                        new List<Object>{ 1, 5 }
                    ),
                    expected.getMessage()
                );
            }
            Assert.isNull(objectRow(empty.Id), 'Nothing is written.');
        }
    }

    @IsTest
    static void removingObjectReadRemovesItsFieldsAndUndoRecreatesThem() {
        PermissionSet given;
        System.runAs(TestUsers.admin()) {
            given = newSet('FAM_Remove_Given');
            grantRelationship(given.Id, true);
        }
        System.runAs(TestUsers.admin()) {
            String document = change(
                new List<Id>{ given.Id },
                new List<Map<String, Object>>{ item(RELATIONSHIP, null, FieldAccessService.NONE) }
            );
            FieldAccessService.Plan plan = FieldAccessService.plan(document);
            Assert.areEqual(2, plan.changes.size(), 'The object and its one field row.');
            Assert.areEqual(FieldAccessService.WHY_REMOVED_WITH_OBJECT, plan.changes[1].reason);
            FieldAccessService.Result done = FieldAccessService.apply(document, 2);
            Assert.areEqual(2, done.changed);
            Assert.areEqual(ImportJournalService.ACTION_DELETED, done.entries[0].get('action'));
            Assert.isNull(fieldRow(given.Id, DESCRIPTION));
            Assert.isNull(objectRow(given.Id));
            // Undo through the journal the record job writes.
            FieldAccessService.Result undone = undoFromEntries(done);
            Assert.areEqual(2, undone.changed);
        }
        ObjectPermissions back = objectRow(given.Id);
        Assert.isTrue(
            back.PermissionsRead && back.PermissionsEdit,
            'Object access is recreated as it was.'
        );
        Assert.isTrue(
            fieldRow(given.Id, DESCRIPTION).PermissionsEdit,
            'Field access is recreated.'
        );
    }

    /** Writes the job and journal the record job would, then undoes it in a new context. */
    private static FieldAccessService.Result undoFromEntries(FieldAccessService.Result done) {
        Import_Batch__c job = new Import_Batch__c(
            Operation__c = FieldAccessService.OPERATION_ACCESS,
            Status__c = ImportBatchService.STATUS_COMPLETE,
            Undo_Deadline__c = Datetime.now().addDays(1),
            Committed_By__c = UserInfo.getUserId()
        );
        FieldAccessService.Result undone;
        System.runAs(TestUsers.admin()) {
            insert as system job;
            ImportJournalService.write(job.Id, ImportJournalService.PHASE_COMMIT, done.entries);
        }
        System.runAs(TestUsers.admin()) {
            undone = FieldAccessService.undo(job.Id);
        }
        return undone;
    }

    @IsTest
    static void undoKeepsARowChangedSince() {
        PermissionSet given;
        FieldAccessService.Result done;
        System.runAs(TestUsers.admin()) {
            given = newSet('FAM_Kept_Given');
            grantRelationship(given.Id, false);
        }
        System.runAs(TestUsers.admin()) {
            done = FieldAccessService.apply(
                change(
                    new List<Id>{ given.Id },
                    new List<Map<String, Object>>{
                        item(RELATIONSHIP, DESCRIPTION, FieldAccessService.NONE)
                    }
                ),
                1
            );
            insert as system new FieldPermissions(
                ParentId = given.Id,
                SobjectType = RELATIONSHIP,
                Field = RELATIONSHIP + '.' + DESCRIPTION,
                PermissionsRead = true,
                PermissionsEdit = true
            );
        }
        FieldAccessService.Result undone = undoFromEntries(done);
        Assert.areEqual(1, undone.kept, 'A row changed since is kept.');
        Assert.areEqual(0, undone.changed);
        Assert.areEqual(ImportJournalService.ACTION_NOT_RESTORED, undone.entries[0].get('action'));
        Assert.isTrue(fieldRow(given.Id, DESCRIPTION).PermissionsEdit, 'Kept as it is now.');
    }

    @IsTest
    static void recordJobMarksAnUndoneChange() {
        Import_Batch__c job = new Import_Batch__c(
            Operation__c = FieldAccessService.OPERATION_ACCESS,
            Status__c = ImportBatchService.STATUS_COMPLETE,
            Undo_Deadline__c = Datetime.now().addDays(1),
            Committed_By__c = UserInfo.getUserId(),
            Run_Log__c = 'Applied.'
        );
        System.runAs(TestUsers.admin()) {
            insert as system job;
            FieldAccessService.Result result = new FieldAccessService.Result();
            result.changed = 2;
            result.failures.add('A refusal.');
            Test.startTest();
            FieldAccessRecordJob.recordUndo(job.Id, result);
            Test.stopTest();
        }
        Import_Batch__c after = [
            SELECT Status__c, Run_Log__c
            FROM Import_Batch__c
            WHERE Id = :job.Id
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(ImportBatchService.STATUS_UNDONE, after.Status__c);
        Assert.isTrue(after.Run_Log__c.startsWith('Applied.\n'), 'The undo line is added.');
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                BarnHelp.text('Core', 'Core_FieldAccess_UndoNotAllowed'),
                FieldAccessService.undoRefusal(
                    new Import_Batch__c(
                        Operation__c = FieldAccessService.OPERATION_ACCESS,
                        Status__c = after.Status__c,
                        Undo_Deadline__c = Datetime.now().addDays(1)
                    )
                ),
                'A change is undone once.'
            );
        }
    }

    @IsTest
    static void refusesWhatSalesforceWouldRefuse() {
        System.runAs(TestUsers.admin()) {
            PermissionSet empty = newSet('FAM_Refuse_Empty');
            List<Id> setIds = new List<Id>{ empty.Id };
            String formula = Account.Is_Organization__c.getDescribe().getName();
            assertRefused(
                change(
                    setIds,
                    new List<Map<String, Object>>{
                        item('Account', formula, FieldAccessService.EDIT)
                    }
                ),
                String.format(
                    BarnHelp.text('Core', 'Core_FieldAccess_ReadOnlyField'),
                    new List<Object>{ Account.Is_Organization__c.getDescribe().getLabel() }
                )
            );
            assertRefused(
                change(
                    setIds,
                    new List<Map<String, Object>>{
                        item(RELATIONSHIP, null, FieldAccessService.NONE),
                        item(RELATIONSHIP, DESCRIPTION, FieldAccessService.READ)
                    }
                ),
                String.format(
                    BarnHelp.text('Core', 'Core_FieldAccess_Conflict'),
                    new List<Object>{
                        Relationship__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                            .getLabel()
                    }
                )
            );
            assertRefused(
                change(
                    setIds,
                    new List<Map<String, Object>>{
                        item(RELATIONSHIP, 'Name', FieldAccessService.READ)
                    }
                ),
                String.format(
                    BarnHelp.text('Core', 'Core_FieldAccess_FieldNotAllowed'),
                    new List<Object>{ 'Name' }
                )
            );
            assertRefused(
                change(setIds, new List<Map<String, Object>>()),
                BarnHelp.text('Core', 'Core_FieldAccess_NoItems')
            );
            assertRefused('{"version":2}', BarnHelp.text('Core', 'Core_FieldAccess_BadDocument'));
            assertRefused(
                change(
                    new List<Id>(),
                    new List<Map<String, Object>>{ item(RELATIONSHIP, null, 'read') }
                ),
                BarnHelp.text('Core', 'Core_FieldAccess_NoSets')
            );
        }
    }

    private static void assertRefused(String document, String message) {
        try {
            FieldAccessController.preview(document);
            Assert.fail('Expected a refusal: ' + message);
        } catch (AuraHandledException expected) {
            Assert.areEqual(message, expected.getMessage());
        }
    }
}
