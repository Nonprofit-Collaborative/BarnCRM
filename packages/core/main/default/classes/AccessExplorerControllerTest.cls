/**
 * AccessExplorerController: the Access Explorer section reads who can see or change what, and
 * why (C-53, plan Section 6.1.1 item 7, D-154). Tests run as Maria, a Standard User holding only
 * BarnCRM Admin. Pat holds a test permission set that reads Relationship and its Description,
 * and the packaged Team Member role.
 */
@IsTest(testFor='ApexClass:AccessExplorerController')
private class AccessExplorerControllerTest {
    private static final String RELATIONSHIP = Relationship__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getName();
    private static final String DESCRIPTION = Relationship__c.Description__c.getDescribe()
        .getName();
    private static final String SET_LABEL = 'Access Explorer Test Set';

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** Pat, with the test set (read Relationship and its Description) and Team Member. */
    private static User pat(PermissionSet testSet) {
        User person = TestDataFactory.createUser('PatAccessExplorer', new List<String>());
        PermissionSetGroup role = TestDataFactory.prepareRoleGroup('Program_Staff');
        insert as system new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = person.Id, PermissionSetId = testSet.Id),
            new PermissionSetAssignment(AssigneeId = person.Id, PermissionSetGroupId = role.Id)
        };
        return person;
    }

    private static PermissionSet testSet() {
        PermissionSet created = new PermissionSet(
            Name = 'Access_Explorer_Test_Set',
            Label = SET_LABEL
        );
        insert as system created;
        insert as system new ObjectPermissions(
            ParentId = created.Id,
            SobjectType = RELATIONSHIP,
            PermissionsRead = true
        );
        insert as system new FieldPermissions(
            ParentId = created.Id,
            SobjectType = RELATIONSHIP,
            Field = RELATIONSHIP + '.' + DESCRIPTION,
            PermissionsRead = true,
            PermissionsEdit = false
        );
        return created;
    }

    private static AccessExplorerController.Row rowNamed(
        List<AccessExplorerController.Row> rows,
        String name
    ) {
        for (AccessExplorerController.Row row : rows) {
            if (row.name == name) {
                return row;
            }
        }
        return null;
    }

    private static AccessExplorerController.Grant grantWithId(
        List<AccessExplorerController.Grant> grants,
        Id grantId
    ) {
        for (AccessExplorerController.Grant grant : grants) {
            if (grant.id == grantId) {
                return grant;
            }
        }
        return null;
    }

    @IsTest
    static void aPersonsAccessNamesEverySourceAndWhatEachGives() {
        System.runAs(TestUsers.admin()) {
            PermissionSet created = testSet();
            User person = pat(created);
            AccessExplorerController.SubjectAccess access;
            System.runAs(maria()) {
                access = AccessExplorerController.getAccess(person.Id);
            }

            Assert.areEqual(person.Id, access.id, 'The person asked for.');
            Assert.isTrue(access.isActive, 'Pat is active.');
            Set<String> kinds = new Set<String>();
            AccessExplorerController.Grant role;
            for (AccessExplorerController.Grant source : access.sources) {
                kinds.add(source.kind);
                if (source.kind == AccessExplorerController.KIND_GROUP) {
                    role = source;
                }
            }
            Assert.isTrue(kinds.contains(AccessExplorerController.KIND_PROFILE), 'The profile.');
            Assert.isTrue(kinds.contains(AccessExplorerController.KIND_SET), 'The direct set.');
            Assert.areEqual(
                AccessExplorerController.KIND_PROFILE,
                access.sources[0].kind,
                'The profile comes first.'
            );
            Assert.isNotNull(role, 'Team Member is listed as a group.');
            Assert.areEqual('Team Member', role.label, 'A group by its label.');
            Assert.isTrue(role.through.contains('BarnCRM Staff'), 'Its sets: ' + role.through);

            AccessExplorerController.Row row = rowNamed(access.objects, RELATIONSHIP);
            Assert.isNotNull(row, 'Relationship is readable.');
            Assert.isTrue(row.read, 'Read.');
            Assert.isTrue(row.edit, 'Edit, from BarnCRM Staff.');
            Assert.isTrue(row.grantedBy.contains(SET_LABEL), row.grantedBy);
            Assert.isTrue(
                row.grantedBy.contains('Team Member (through BarnCRM Staff'),
                row.grantedBy
            );
        }
    }

    @IsTest
    static void aPermissionSetsAccessIsOnlyWhatItGives() {
        System.runAs(TestUsers.admin()) {
            PermissionSet created = testSet();
            AccessExplorerController.SubjectAccess access;
            List<AccessExplorerController.Row> fields;
            System.runAs(maria()) {
                access = AccessExplorerController.getAccess(created.Id);
                fields = AccessExplorerController.getFieldAccess(created.Id, RELATIONSHIP);
            }

            Assert.areEqual(SET_LABEL, access.label, 'Its label.');
            Assert.areEqual(AccessExplorerController.KIND_SET, access.detail, 'Its kind.');
            Assert.areEqual(1, access.objects.size(), 'One kind of record.');
            AccessExplorerController.Row only = access.objects[0];
            Assert.areEqual(RELATIONSHIP, only.name, 'Relationship by API name.');
            Assert.isTrue(only.read && !only.edit, 'Read only.');
            Assert.areEqual(SET_LABEL, only.grantedBy, 'Given by the set itself.');

            AccessExplorerController.Row description = rowNamed(fields, DESCRIPTION);
            Assert.isTrue(description.read, 'Description is readable.');
            Assert.isFalse(description.edit, 'Not editable.');
            Assert.isFalse(description.always, 'Description can be restricted.');
            AccessExplorerController.Row name = rowNamed(fields, 'Name');
            Assert.isTrue(name.always, 'Name is always visible with the record.');
        }
    }

    @IsTest
    static void aKindOfRecordListsItsGrantsAndThePeopleWhoHoldThem() {
        System.runAs(TestUsers.admin()) {
            PermissionSet created = testSet();
            User person = pat(created);
            String patName = [SELECT Name FROM User WHERE Id = :person.Id].Name;
            AccessExplorerController.ObjectAccess access;
            AccessExplorerController.ObjectAccess field;
            AccessExplorerController.ObjectAccess name;
            AccessExplorerController.PersonPage first;
            AccessExplorerController.PersonPage second;
            System.runAs(maria()) {
                access = AccessExplorerController.getObjectAccess(RELATIONSHIP, null);
                field = AccessExplorerController.getObjectAccess(RELATIONSHIP, DESCRIPTION);
                name = AccessExplorerController.getObjectAccess(RELATIONSHIP, 'Name');
                first = AccessExplorerController.getPeopleWithAccess(
                    RELATIONSHIP,
                    DESCRIPTION,
                    null,
                    null
                );
                second = AccessExplorerController.getPeopleWithAccess(
                    RELATIONSHIP,
                    DESCRIPTION,
                    patName,
                    person.Id
                );
            }

            AccessExplorerController.Grant grant = grantWithId(access.grants, created.Id);
            Assert.isNotNull(grant, 'The test set gives access.');
            Assert.areEqual(1, grant.activePeople, 'Pat holds it.');
            Assert.isTrue(grant.read && !grant.create, 'Read only.');
            Boolean everything = false;
            for (AccessExplorerController.Grant each : access.grants) {
                everything |= each.viewAllData && each.read && each.viewAll;
            }
            Assert.isTrue(everything, 'A View All Data profile reads every kind of record.');
            Assert.isFalse(access.truncated, 'Not cut.');

            AccessExplorerController.Grant fieldGrant = grantWithId(field.grants, created.Id);
            Assert.isTrue(fieldGrant.read && !fieldGrant.edit, 'Description: read only.');
            Assert.isTrue(name.always, 'Name is not restricted.');
            Assert.isTrue(name.grants.isEmpty(), 'So no grants are listed.');

            AccessExplorerController.Row listed = rowNamed(first.rows, person.Id);
            Assert.isNotNull(listed, 'Pat is on the first page.');
            Assert.isTrue(listed.grantedBy.contains(SET_LABEL), listed.grantedBy);
            Assert.isNull(rowNamed(second.rows, person.Id), 'The next page starts after Pat.');
        }
    }

    @IsTest
    static void aLongListOfGrantsIsCut() {
        System.runAs(TestUsers.admin()) {
            testSet();
            AccessExplorerController.maxGrants = 1;
            AccessExplorerController.ObjectAccess access;
            System.runAs(maria()) {
                access = AccessExplorerController.getObjectAccess(RELATIONSHIP, null);
            }
            Assert.isTrue(access.truncated, 'More than one grant.');
            Assert.areEqual(1, access.grants.size(), 'Cut to the limit.');
        }
    }

    @IsTest
    static void searchFindsPeopleAndPermissionSets() {
        System.runAs(TestUsers.admin()) {
            PermissionSet created = testSet();
            User person = pat(created);
            List<AccessExplorerController.Choice> people;
            List<AccessExplorerController.Choice> sets;
            List<AccessExplorerController.Choice> tooShort;
            System.runAs(maria()) {
                people = AccessExplorerController.searchPeople('PatAccessExplorer');
                sets = AccessExplorerController.searchPermissionSets('Access Explorer Test');
                tooShort = AccessExplorerController.searchPeople('P');
            }
            Assert.areEqual(1, people.size(), 'Pat.');
            Assert.areEqual(person.Id, people[0].id, 'By Id.');
            Assert.areEqual(1, sets.size(), 'The test set.');
            Assert.areEqual(AccessExplorerController.KIND_SET, sets[0].detail, 'Its kind.');
            Assert.isTrue(tooShort.isEmpty(), 'One character searches nothing.');
        }
    }

    @IsTest
    static void theOverviewCountsBarnCrmSetsAndReportsTheTabCheck() {
        System.runAs(TestUsers.admin()) {
            AccessExplorerController.Overview overview;
            System.runAs(maria()) {
                overview = AccessExplorerController.getOverview();
            }
            AccessExplorerController.Grant admin;
            for (AccessExplorerController.Grant row : overview.sets) {
                Assert.isTrue(
                    row.kind == AccessExplorerController.KIND_GROUP ||
                    row.name.startsWith('BarnCRM_'),
                    'Only BarnCRM sets and roles: ' + row.name
                );
                if (row.name == 'BarnCRM_Admin') {
                    admin = row;
                }
            }
            Assert.isNotNull(admin, 'BarnCRM Admin is listed.');
            Assert.isTrue(admin.activePeople >= 1, 'Maria holds it.');
            Assert.areEqual(
                AccessExplorerController.KIND_GROUP,
                overview.sets[0].kind,
                'Roles come first.'
            );
            Assert.areEqual(
                TabAccessScheduler.isScheduled(),
                overview.tabAccessCheckScheduled,
                'The Tab Access Check state.'
            );
        }
    }

    @IsTest
    static void refusalsSayWhatIsWrong() {
        System.runAs(TestUsers.admin()) {
            User staff = TestDataFactory.createUser('Sam', new List<String>{ 'BarnCRM_Staff' });
            List<String> messages = new List<String>();
            System.runAs(staff) {
                messages.add(refusal('overview', null, null));
            }
            System.runAs(maria()) {
                messages.add(refusal('object', 'No_Such_Object__c', null));
                messages.add(refusal('object', RELATIONSHIP, 'No_Such_Field__c'));
                messages.add(refusal('access', 'not an id', null));
                messages.add(refusal('access', UserInfo.getOrganizationId(), null));
            }
            Assert.areEqual(System.Label.Core_AccessExplorer_PermissionRequired, messages[0], '');
            Assert.isTrue(messages[1].contains('No_Such_Object__c'), messages[1]);
            Assert.isTrue(messages[2].contains('No_Such_Field__c'), messages[2]);
            Assert.areEqual(System.Label.Core_AccessExplorer_UnknownSubject, messages[3], '');
            Assert.areEqual(System.Label.Core_AccessExplorer_UnknownSubject, messages[4], '');
        }
    }

    private static String refusal(String call, String first, String second) {
        try {
            if (call == 'overview') {
                AccessExplorerController.getOverview();
            } else if (call == 'object') {
                AccessExplorerController.getObjectAccess(first, second);
            } else {
                AccessExplorerController.getAccess(first);
            }
        } catch (AuraHandledException caught) {
            return caught.getMessage();
        }
        return null;
    }
}
