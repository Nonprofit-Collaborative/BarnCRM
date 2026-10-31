@IsTest(testFor='ApexClass:ImportNewFieldController')
private class ImportNewFieldControllerTest {
    private static final List<String> FIELD_ADMIN = new List<String>{
        'BarnCRM_Admin',
        'BarnCRM_Metadata_Admin'
    };

    @TestSetup
    static void createUsers() {
        TestUsers.withPermissionSets(FIELD_ADMIN);
        TestUsers.admin();
    }

    private static void connected(String calloutStatus) {
        ImportNewFieldService.systemPermissionOverride = true;
        ImportNewFieldService.connectedOverride = true;
        ImportNewFieldService.calloutStatusOverride = calloutStatus;
    }

    private static String request(String apiName) {
        return JSON.serialize(
            new Map<String, Object>{
                'objectApiName' => 'Account',
                'label' => 'Shirt Size',
                'apiName' => apiName,
                'type' => 'Text',
                'length' => 40
            }
        );
    }

    private static String alternateEmail() {
        return NamespaceUtil.qualify('Alternate_Email');
    }

    private static void assertRefused(String message, Exception e) {
        Assert.isInstanceOfType(e, AuraHandledException.class, e.getTypeName());
        Assert.areEqual(message, e.getMessage());
    }

    @IsTest
    static void reportsTheConnectionStatus() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            ImportNewFieldService.systemPermissionOverride = true;
            ImportNewFieldService.connectedOverride = false;
            ImportNewFieldService.Connection status = ImportNewFieldController.getConnection();
            Assert.isTrue(status.canCreate);
            Assert.isFalse(status.connected || status.calloutsOff, 'not set up');

            connected('Disabled');
            status = ImportNewFieldController.setUpConnection();
            Assert.isTrue(status.calloutsOff && !status.connected, 'set up, callouts off');

            connected('Enabled');
            status = ImportNewFieldController.getConnection();
            Assert.isTrue(status.connected && !status.calloutsOff, 'connected');
        }
    }

    @IsTest
    static void refusesEveryActionWithoutThePermissions() {
        System.runAs(TestUsers.admin()) {
            connected('Enabled');
            ImportNewFieldService.Connection status = ImportNewFieldController.getConnection();
            Assert.isFalse(status.canCreate || status.connected, 'no Metadata Admin');
            String refused = Label.Core_ImportNewField_NoPermission;
            try {
                ImportNewFieldController.setUpConnection();
                Assert.fail('setUpConnection');
            } catch (Exception e) {
                assertRefused(refused, e);
            }
            try {
                ImportNewFieldController.getPermissionSets();
                Assert.fail('getPermissionSets');
            } catch (Exception e) {
                assertRefused(refused, e);
            }
            try {
                ImportNewFieldController.createField(request('Shirt_Size'));
                Assert.fail('createField');
            } catch (Exception e) {
                assertRefused(refused, e);
            }
            try {
                ImportNewFieldController.checkField(UserInfo.getUserId(), 'Account', 'Shirt_Size');
                Assert.fail('checkField');
            } catch (Exception e) {
                assertRefused(refused, e);
            }
            try {
                ImportNewFieldController.findField('Account', 'Shirt_Size');
                Assert.fail('findField');
            } catch (Exception e) {
                assertRefused(refused, e);
            }
        }
    }

    @IsTest
    static void refusesCreatingWithoutAWorkingConnection() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            ImportNewFieldService.systemPermissionOverride = true;
            ImportNewFieldService.connectedOverride = false;
            try {
                ImportNewFieldController.createField(request('Shirt_Size'));
                Assert.fail('not set up');
            } catch (Exception e) {
                assertRefused(Label.Core_ImportNewField_NotConnected, e);
            }
            connected('Disabled');
            try {
                ImportNewFieldController.createField(request('Shirt_Size'));
                Assert.fail('callouts off');
            } catch (Exception e) {
                assertRefused(Label.Core_ImportNewField_CalloutsOff, e);
            }
        }
    }

    @IsTest
    static void refusesAnInvalidRequestInWords() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            connected('Enabled');
            try {
                ImportNewFieldController.createField(request('1st'));
                Assert.fail('invalid name');
            } catch (Exception e) {
                assertRefused(Label.Core_ImportNewField_NameInvalid, e);
            }
        }
    }

    @IsTest
    static void listsTheOrgsOwnPermissionSets() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            connected('Enabled');
            PermissionSet own = new PermissionSet(Name = 'Barn_Test_Own', Label = 'Barn Test Own');
            insert as system own;
            Boolean listed = false;
            for (
                ImportNewFieldController.Choice each : ImportNewFieldController.getPermissionSets()
            ) {
                listed = listed || (each.value == own.Id && each.label == 'Barn Test Own');
            }
            Assert.isTrue(listed, 'the org permission set is offered');
        }
    }

    @IsTest
    static void checksAJobAndFindsAField() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            connected('Enabled');
            // An Id that is no job of this user's: reported as failed, not thrown.
            ImportNewFieldService.Outcome outcome = ImportNewFieldController.checkField(
                UserInfo.getUserId(),
                'Account',
                'Shirt_Size'
            );
            Assert.areEqual(ImportNewFieldService.FAILED, outcome.state);
            Assert.areEqual(Label.Core_ImportNewField_JobFailed, outcome.message);

            outcome = ImportNewFieldController.findField('Account', alternateEmail() + '__c');
            Assert.areEqual(ImportNewFieldService.CREATED, outcome.state);
            Assert.areEqual(alternateEmail() + '__c', outcome.fieldValue);
            Assert.areEqual(
                ImportNewFieldService.RUNNING,
                ImportNewFieldController.findField('Account', 'Not_Created_Yet').state
            );
        }
    }
}
