/**
 * SPIKE (rollup slice S15). Offline checks of the generator and the SOAP plumbing. The real proof
 * is the org run in the S15 findings (scratchpad rollup-s15-spike.md).
 */
@IsTest
private class S15SpikeSelfDeployTest {
    private class MetadataMock implements HttpCalloutMock {
        public HttpRequest lastRequest;
        public HttpResponse respond(HttpRequest request) {
            lastRequest = request;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body>' +
                    '<deployResponse xmlns="http://soap.sforce.com/2006/04/metadata"><result>' +
                    '<done>false</done><id>0Af000000000001AAA</id><state>Queued</state>' +
                    '</result></deployResponse></soapenv:Body></soapenv:Envelope>'
            );
            return response;
        }
    }

    @IsTest
    static void namesAreDeterministicAndFitTheLimit() {
        String longName = 'A_Very_Long_Custom_Object_Name_For_Testing__c';
        Assert.areEqual(
            S15SpikeSelfDeploy.baseName(longName),
            S15SpikeSelfDeploy.baseName(longName)
        );
        Assert.isTrue(
            (S15SpikeSelfDeploy.baseName(longName) + '_Test').length() <= 40,
            'Test class name too long'
        );
        Assert.areEqual('S15_Pet', S15SpikeSelfDeploy.baseName('Pet__c'));
    }

    @IsTest
    static void generatedCodeIsOneSignalLine() {
        String body = S15SpikeSelfDeploy.triggerBody('Pet__c');
        Assert.isTrue(body.contains('trigger S15_Pet on Pet__c (before insert,'), body);
        Assert.isTrue(body.contains('S15SpikeSignal.handle();'), body);
        Assert.isTrue(
            S15SpikeSelfDeploy.testBody('Pet__c').contains('new Pet__c()'),
            'Test inserts a dummy record'
        );
    }

    @IsTest
    static void zipHasFiveEntries() {
        Compression.ZipReader reader = new Compression.ZipReader(
            S15SpikeSelfDeploy.buildZip('Pet__c')
        );
        Assert.areEqual(5, reader.getEntries().size());
        Assert.isNotNull(reader.getEntry('triggers/S15_Pet.trigger'));
        Assert.isNotNull(reader.getEntry('classes/S15_Pet_Test.cls'));
    }

    @IsTest
    static void deployRunsOnlyTheGeneratedTest() {
        String envelope = S15SpikeSelfDeploy.deployEnvelope(
            'SESSION',
            Blob.valueOf('zip'),
            'S15_Pet_Test',
            true
        );
        Assert.isTrue(
            envelope.contains('<met:testLevel>RunSpecifiedTests</met:testLevel>'),
            envelope
        );
        Assert.isTrue(envelope.contains('<met:runTests>S15_Pet_Test</met:runTests>'), envelope);
        Assert.isTrue(
            envelope.indexOf('checkOnly') < envelope.indexOf('rollbackOnError'),
            'WSDL order'
        );
        Assert.isTrue(
            envelope.indexOf('runTests') < envelope.indexOf('singlePackage'),
            'WSDL order'
        );
    }

    @IsTest
    static void outcomeReadsDoneStatusAndProblems() {
        Dom.Document pending = new Dom.Document();
        pending.load('<r><result><done>false</done></result></r>');
        Assert.isNull(S15SpikeSelfDeploy.outcome(pending));

        Dom.Document failed = new Dom.Document();
        failed.load(
            '<r><result><done>true</done><status>Failed</status><details>' +
                '<runTestResult><codeCoverageWarnings><message>Test coverage of selected Apex Trigger is 0%</message>' +
                '</codeCoverageWarnings></runTestResult></details></result></r>'
        );
        String result = S15SpikeSelfDeploy.outcome(failed);
        Assert.isTrue(result.startsWith('Failed'), result);
        Assert.isTrue(result.contains('coverage'), result);
    }

    @IsTest
    static void rejectsStandardAndUnknownObjects() {
        for (String name : new List<String>{ 'Contact', 'Nope__c', '' }) {
            try {
                S15SpikeSelfDeploy.describeTarget(name);
                Assert.fail('Expected a refusal for ' + name);
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    @IsTest
    static void deployJobCallsTheSelfNamedCredential() {
        MetadataMock mock = new MetadataMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new S15SpikeSelfDeploy.DeployJob('Pet__c', true).execute(null);
        Test.stopTest();
        Assert.areEqual('callout:S15_Self/services/Soap/m/67.0', mock.lastRequest.getEndpoint());
        Assert.isTrue(mock.lastRequest.getBody().contains('<met:deploy>'), 'Deploy call');
    }

    @IsTest
    static void signalTestHandlerSwallowsRejectionsAfterTheTriggerRan() {
        S15SpikeSignal.invoked = true;
        // An Account with no Name fails the insert; the handler swallows it because the signal ran.
        S15SpikeSignal.testHandler(new Account());
        S15SpikeSignal.invoked = false;
        try {
            S15SpikeSignal.testHandler(new Account());
            Assert.fail('Expected the insert error to surface when the trigger never ran');
        } catch (DmlException e) {
            Assert.isNotNull(e.getMessage());
        }
    }
}
