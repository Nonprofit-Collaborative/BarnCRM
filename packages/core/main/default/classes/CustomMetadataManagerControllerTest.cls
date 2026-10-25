/**
 * The custom metadata manager's Apex surface: a holder of Manage BarnCRM Metadata reads, saves
 * and waits on the outcome; anyone else is refused before anything is read.
 *
 * Maria holds BarnCRM Admin and BarnCRM Metadata Admin and the tests run as her: a permission
 * set given to the running user during the test run is not seen by FeatureManagement until a
 * new user context starts, and reads and saves are in her own mode from API version 67.0.
 */
@IsTest(testFor='ApexClass:CustomMetadataManagerController')
private class CustomMetadataManagerControllerTest {
    private static final String TYPE_NAME = 'Relationship_Type__mdt';
    private static final Id JOB = FakeIds.ofPrefix('0Af', 3);

    private class StubDeployer implements CustomMetadataManagerService.Deployer {
        public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            return JOB;
        }
    }

    private static User maria() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Metadata_Admin' }
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
        User maria = maria();
        noRows();
        List<CustomMetadataManagerService.TypeView> types;
        String jobId;
        CustomMetadataManagerController.Outcome pending;
        CustomMetadataManagerController.Outcome done;

        Test.startTest();
        System.runAs(maria) {
            types = CustomMetadataManagerController.getTypes();
            jobId = CustomMetadataManagerController.saveRow(TYPE_NAME, closeFriend());
            pending = CustomMetadataManagerController.getOutcome(jobId);
            // What the deploy callback writes when the deployment succeeds, in system mode as
            // the callback writes it: the audit row is the package's bookkeeping.
            insert as system new Setting_Change__c(
                Setting_Name__c = 'Relationship_Type.Org_Close_friend',
                Changed_By__c = UserInfo.getUserId(),
                Changed_At__c = System.now(),
                Deployment_Id__c = jobId
            );
            done = CustomMetadataManagerController.getOutcome(jobId);
        }
        Test.stopTest();

        Assert.areEqual(2, types.size(), 'Relationship types and match sources');
        Assert.areEqual(String.valueOf(JOB), jobId, 'The deployment Id comes back');
        Assert.areEqual(CustomMetadataManagerController.PENDING, pending.status, 'Still running');
        Assert.areEqual(CustomMetadataManagerController.SUCCEEDED, done.status, 'Finished');
    }

    @IsTest
    static void aFailedDeploymentComesBackWithItsMessage() {
        User maria = maria();
        noRows();
        CustomMetadataManagerController.Outcome failed;

        System.runAs(maria) {
            Test.startTest();
            ErrorLogger.logMessage(
                'The change to Close friend was not saved: no.',
                'Custom metadata',
                ErrorLogger.SEVERITY_ERROR,
                JOB
            );
            Test.stopTest();

            failed = CustomMetadataManagerController.getOutcome(String.valueOf(JOB));
        }
        Assert.areEqual(CustomMetadataManagerController.FAILED, failed.status, 'Failed');
        Assert.areEqual('The change to Close friend was not saved: no.', failed.message, 'Why');
    }

    @IsTest
    static void aRefusalIsShownAsItIsAndArchiveUsesTheSamePath() {
        User maria = maria();
        noRows();
        String saveMessage;
        String archiveMessage;
        String outcomeMessage;
        CustomMetadataManagerService.RowInput unnamed = closeFriend();
        unnamed.label = '';

        Test.startTest();
        System.runAs(maria) {
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
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_CmdtManager_NameRequired, saveMessage, 'Validation message');
        Assert.areEqual(Label.Core_CmdtManager_RecordNotFound, archiveMessage, 'Unknown row');
        Assert.areEqual(Label.Core_CmdtManager_LoadError, outcomeMessage, 'Bad Id');
    }

    @IsTest
    static void someoneWithoutThePermissionIsRefused() {
        System.runAs(TestUsers.admin()) {
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
}
