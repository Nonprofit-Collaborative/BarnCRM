/**
 * How a custom metadata deployment's ending is recorded (canonical model R-S6): an audit row
 * on success, an Error Log entry on failure, each findable by the deployment Id.
 */
@IsTest
private class CustomMetadataDeployCallbackTest {
    private static final Id JOB = Id.valueOf('0Af000000000002');

    /** The platform's context cannot be built with a job Id, so the test supplies one. */
    private class TestContext extends Metadata.DeployCallbackContext {
        public override Id getCallbackJobId() {
            return JOB;
        }
    }

    private static CustomMetadataDeployCallback callback() {
        return new CustomMetadataDeployCallback(
            'Relationship_Type.Org_Mentor',
            'Mentor',
            null,
            '{"Type__c":"Mentor"}',
            UserInfo.getUserId()
        );
    }

    @IsTest
    static void aSuccessIsAuditedWithItsDeploymentId() {
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.Succeeded;

        Test.startTest();
        callback().handleResult(result, new TestContext());
        Test.stopTest();

        Setting_Change__c change = [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c, Changed_By__c, Deployment_Id__c
            FROM Setting_Change__c
        ];
        Assert.areEqual('Relationship_Type.Org_Mentor', change.Setting_Name__c, 'Which row');
        Assert.isNull(change.Old_Value__c, 'A new row had no old value');
        Assert.areEqual('{"Type__c":"Mentor"}', change.New_Value__c, 'The values deployed');
        Assert.areEqual(UserInfo.getUserId(), change.Changed_By__c, 'Who saved');
        Assert.areEqual(String.valueOf(JOB), change.Deployment_Id__c, 'Findable by the page');
        Assert.isTrue(CustomMetadataManagerSelector.hasSucceeded(JOB), 'The page sees success');
    }

    @IsTest
    static void aFailureIsLoggedWithSalesforcesReason() {
        Metadata.DeployMessage failure = new Metadata.DeployMessage();
        failure.problem = 'Type: bad value for restricted picklist field.';
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.Failed;
        result.details = new Metadata.DeployDetails();
        result.details.componentFailures = new List<Metadata.DeployMessage>{ failure };

        Test.startTest();
        callback().handleResult(result, new TestContext());
        Test.stopTest();

        String expected = String.format(
            Label.Core_CmdtManager_DeployFailed,
            new List<Object>{ 'Mentor', failure.problem }
        );
        Assert.areEqual(expected, CustomMetadataManagerSelector.failureMessage(JOB), 'The reason');
        Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'Nothing changed, no audit');
    }

    @IsTest
    static void aFailureWithNoReasonSaysWhatToDo() {
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.Failed;

        Test.startTest();
        String reason = CustomMetadataDeployCallback.reasonOf(result);
        String none = CustomMetadataDeployCallback.reasonOf(null);
        Test.stopTest();

        Assert.areEqual(Label.Core_CmdtManager_DeployFailedNoReason, reason, 'Fallback');
        Assert.areEqual(Label.Core_CmdtManager_DeployFailedNoReason, none, 'No result at all');
    }
}
