/**
 * Tests the LWC-facing entry points of SampleDataController: the permitted load, remove
 * and status paths, the permission-denied path as a Standard User who does not hold the
 * Manage_BarnCRM_Settings custom permission, and the already-loaded error reaching the
 * component as an AuraHandledException carrying the label text.
 *
 * The permitted paths set the @TestVisible permissionOverride because the custom
 * permission and the permission set that grants it are owned by another feature, so the
 * running user cannot be assumed to hold it in every org shape.
 */
@IsTest(testFor='ApexClass:SampleDataController')
private class SampleDataControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWithInstalledModules();
    }

    private static String buildJson(Integer householdCount, Integer membersPerHousehold) {
        List<Object> households = new List<Object>();
        Integer memberNumber = 1;
        for (Integer h = 0; h < householdCount; h++) {
            List<Object> members = new List<Object>();
            for (Integer m = 0; m < membersPerHousehold; m++) {
                Map<String, Object> member = new Map<String, Object>();
                member.put('firstName', 'Maria' + memberNumber);
                member.put('lastName', 'Household' + h);
                member.put('salutation', 'Ms.');
                member.put('householdRole', m == 0 ? 'Head' : 'Other');
                member.put('email', 'maria' + memberNumber + '@example.org');
                member.put('birthdate', '1980-01-01');
                members.add(member);
                memberNumber++;
            }
            Map<String, Object> household = new Map<String, Object>();
            household.put('key', 'H' + h);
            household.put('customName', false);
            household.put('name', null);
            household.put('anniversary', null);
            household.put('members', members);
            households.add(household);
        }

        Map<String, Object> organization = new Map<String, Object>();
        organization.put('key', 'O1');
        organization.put('name', 'Test Foundation');

        Map<String, Object> root = new Map<String, Object>();
        root.put('households', households);
        root.put('organizations', new List<Object>{ organization });
        return JSON.serialize(root);
    }

    /** Inserts stage one and every contact chunk without relying on the stage batch. */
    private static void loadEverything(String jsonBody) {
        SampleDataSet data = SampleDataSet.parse(jsonBody);
        SampleDataLoadStages.loadHouseholdsAndOrganizations(data);
        for (Integer chunk = 0; chunk < data.chunkCount(); chunk++) {
            SampleDataLoadStages.loadContactChunk(data, chunk);
        }
    }

    /** A Standard User, used for the permission-denied path. */
    private static User buildStandardUser() {
        return TestUsers.newStandardUser('Sample');
    }

    @IsTest
    static void testLoadStartsTheChainForAPermittedUser() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataController.permissionOverride = true;
            SampleDataLoader.jsonOverride = buildJson(2, 2);

            Test.startTest();
            SampleDataController.loadSampleData();
            Test.stopTest();

            SampleDataLoader.Counts status = SampleDataController.getStatus();
            System.assertEquals(
                2,
                status.householdCount,
                'stage one should have inserted households'
            );
            System.assertEquals(
                1,
                status.organizationCount,
                'stage one should have inserted the organization'
            );
        }
    }

    @IsTest
    static void testRemoveDeletesForAPermittedUser() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataController.permissionOverride = true;
            loadEverything(buildJson(2, 2));

            Test.startTest();
            SampleDataLoader.Counts removed = SampleDataController.removeSampleData();
            Test.stopTest();
            System.assertEquals(2, removed.householdCount, 'both households should be removed');
            System.assertEquals(4, removed.contactCount, 'every sample contact should be removed');
            System.assertEquals(true, removed.removing, 'the card is told the removal started');

            // A test runs one stage of the batch; run the rest the way the batch does in an org.
            SampleDataRemoveStages stages = new SampleDataRemoveStages();
            Integer stageCount = stages.stageCount();
            for (Integer stage = 0; stage < stageCount; stage++) {
                stages.runStage(stage);
            }

            SampleDataLoader.Counts status = SampleDataController.getStatus();
            System.assertEquals(0, status.householdCount, 'nothing flagged should remain');
            System.assertEquals(false, status.loaded, 'the card should report not loaded');
        }
    }

    @IsTest
    static void testStatusReportsCountsAndLoadedState() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 3));

            SampleDataLoader.Counts status = SampleDataController.getStatus();
            System.assertEquals(1, status.householdCount);
            System.assertEquals(1, status.organizationCount);
            System.assertEquals(3, status.contactCount);
            System.assertEquals(true, status.loaded, 'loaded once records exist and no job runs');
            System.assertEquals(false, status.loading);
        }
    }

    @IsTest
    static void testCanManageIsTrueForAPermittedUser() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataController.permissionOverride = true;
            System.assertEquals(
                true,
                SampleDataController.canManageSampleData(),
                'a user with the permission can manage sample data'
            );
        }
    }

    @IsTest
    static void testStandardUserWithoutThePermissionIsRefused() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            User standardUser = buildStandardUser();
            insert standardUser;

            Boolean loadThrew = false;
            Boolean removeThrew = false;
            Boolean canManage = true;

            System.runAs(standardUser) {
                canManage = SampleDataController.canManageSampleData();
                try {
                    SampleDataController.loadSampleData();
                } catch (AuraHandledException e) {
                    loadThrew = true;
                    System.assertEquals(
                        Label.Core_SampleData_NoPermission,
                        e.getMessage(),
                        'the refusal should carry the no-permission label'
                    );
                }
                try {
                    SampleDataController.removeSampleData();
                } catch (AuraHandledException e) {
                    removeThrew = true;
                    System.assertEquals(
                        Label.Core_SampleData_NoPermission,
                        e.getMessage(),
                        'the refusal should carry the no-permission label'
                    );
                }
            }

            System.assertEquals(false, canManage, 'a Standard User cannot manage sample data');
            System.assertEquals(true, loadThrew, 'loading without the permission should throw');
            System.assertEquals(true, removeThrew, 'removing without the permission should throw');
        }
    }

    @IsTest
    static void testAlreadyLoadedSurfacesAsAnAuraHandledException() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataController.permissionOverride = true;
            loadEverything(buildJson(1, 1));
            SampleDataLoader.jsonOverride = buildJson(1, 1);

            Boolean threw = false;
            try {
                SampleDataController.loadSampleData();
            } catch (AuraHandledException e) {
                threw = true;
                System.assertEquals(
                    Label.Core_SampleData_AlreadyLoaded,
                    e.getMessage(),
                    'the component should receive the already-loaded label text'
                );
            }
            System.assertEquals(
                true,
                threw,
                'a second load should reach the component as an error'
            );
        }
    }
}
