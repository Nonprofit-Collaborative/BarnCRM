/**
 * The custom metadata manager's Apex surface: a holder of Manage BarnCRM Metadata reads, saves
 * and waits on the outcome; anyone else is refused before anything is read.
 */
@IsTest
private class CustomMetadataManagerControllerTest {
    private static final String TYPE_NAME = 'Relationship_Type__mdt';
    private static final Id JOB = Id.valueOf('0Af000000000003');

    private class StubDeployer implements CustomMetadataManagerService.Deployer {
        public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            return JOB;
        }
    }

    @TestSetup
    static void grantPermission() {
        PermissionSet holder = new PermissionSet(
            Name = 'Cmdt_Manager_Controller_Test',
            Label = 'Cmdt Manager Controller Test'
        );
        insert holder;
        List<CustomPermission> permissions = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = 'Manage_BarnCRM_Metadata'
            LIMIT 1
        ];
        Assert.isFalse(permissions.isEmpty(), 'The package ships Manage BarnCRM Metadata');
        insert new SetupEntityAccess(ParentId = holder.Id, SetupEntityId = permissions[0].Id);
        insert new PermissionSetAssignment(
            AssigneeId = UserInfo.getUserId(),
            PermissionSetId = holder.Id
        );
    }

    private static CustomMetadataManagerService.RowInput closeFriend() {
        CustomMetadataManagerService.RowInput input = new CustomMetadataManagerService.RowInput();
        input.label = 'Close friend';
        input.values = new Map<String, String>{
            'Type__c' => 'Friend',
            'Reciprocal_Type__c' => 'Friend'
        };
        return input;
    }

    private static void noRows() {
        CustomMetadataManagerSelector.rowsOverride = new Map<String, List<CustomMetadataManagerSelector.StoredRow>>{
            Relationship_Type__mdt.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getName() => new List<CustomMetadataManagerSelector.StoredRow>()
        };
        CustomMetadataManagerService.deployer = new StubDeployer();
    }

    @IsTest
    static void mariaSavesAndWaitsForTheOutcome() {
        noRows();

        Test.startTest();
        List<CustomMetadataManagerService.TypeView> types = CustomMetadataManagerController.getTypes();
        String jobId = CustomMetadataManagerController.saveRow(TYPE_NAME, closeFriend());
        CustomMetadataManagerController.Outcome pending = CustomMetadataManagerController.getOutcome(
            jobId
        );
        insert new Setting_Change__c(
            Setting_Name__c = 'Relationship_Type.Org_Close_friend',
            Changed_By__c = UserInfo.getUserId(),
            Changed_At__c = System.now(),
            Deployment_Id__c = jobId
        );
        CustomMetadataManagerController.Outcome done = CustomMetadataManagerController.getOutcome(
            jobId
        );
        Test.stopTest();

        Assert.areEqual(1, types.size(), 'One editable list');
        Assert.areEqual(String.valueOf(JOB), jobId, 'The deployment Id comes back');
        Assert.areEqual(CustomMetadataManagerController.PENDING, pending.status, 'Still running');
        Assert.areEqual(CustomMetadataManagerController.SUCCEEDED, done.status, 'Finished');
    }

    @IsTest
    static void aFailedDeploymentComesBackWithItsMessage() {
        noRows();

        Test.startTest();
        ErrorLogger.logMessage(
            'The change to Close friend was not saved: no.',
            'Custom metadata',
            ErrorLogger.SEVERITY_ERROR,
            JOB
        );
        Test.stopTest();

        CustomMetadataManagerController.Outcome failed = CustomMetadataManagerController.getOutcome(
            String.valueOf(JOB)
        );
        Assert.areEqual(CustomMetadataManagerController.FAILED, failed.status, 'Failed');
        Assert.areEqual('The change to Close friend was not saved: no.', failed.message, 'Why');
    }

    @IsTest
    static void aRefusalIsShownAsItIsAndArchiveUsesTheSamePath() {
        noRows();
        String saveMessage;
        String archiveMessage;
        String outcomeMessage;
        CustomMetadataManagerService.RowInput unnamed = closeFriend();
        unnamed.label = '';

        Test.startTest();
        try {
            CustomMetadataManagerController.saveRow(TYPE_NAME, unnamed);
        } catch (AuraHandledException e) {
            saveMessage = e.getMessage();
        }
        try {
            CustomMetadataManagerController.setArchived(TYPE_NAME, 'Org_Missing', true);
        } catch (AuraHandledException e) {
            archiveMessage = e.getMessage();
        }
        try {
            CustomMetadataManagerController.getOutcome('not an id');
        } catch (AuraHandledException e) {
            outcomeMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_CmdtManager_NameRequired, saveMessage, 'Validation message');
        Assert.areEqual(Label.Core_CmdtManager_RecordNotFound, archiveMessage, 'Unknown row');
        Assert.areEqual(Label.Core_CmdtManager_LoadError, outcomeMessage, 'Bad Id');
    }

    @IsTest
    static void someoneWithoutThePermissionIsRefused() {
        User david = SettingsTestPermissions.buildStandardUser('David', 'Okafor', 'cmdtdav');
        insert david;
        String message;

        Test.startTest();
        System.runAs(david) {
            try {
                CustomMetadataManagerController.getTypes();
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_CmdtManager_PermissionRequired, message, 'Refused first');
    }
}
