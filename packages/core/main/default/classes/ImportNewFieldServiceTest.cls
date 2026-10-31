@IsTest(testFor='ApexClass:ImportNewFieldService, ApexClass:ImportNewFieldController')
private class ImportNewFieldServiceTest {
    private static final List<String> FIELD_ADMIN = new List<String>{
        'BarnCRM_Admin',
        'BarnCRM_Metadata_Admin'
    };
    private static final String SUCCESS = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body><createMetadataResponse><result><fullName>Account.Shirt_Size__c</fullName><success>true</success></result></createMetadataResponse></soapenv:Body></soapenv:Envelope>';
    private static final String REFUSED = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body><createMetadataResponse><result><errors><message>Too many custom fields</message><statusCode>LIMIT_EXCEEDED</statusCode></errors><fullName>Account.Shirt_Size__c</fullName><success>false</success></result></createMetadataResponse></soapenv:Body></soapenv:Envelope>';
    private static final String FAULT = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body><soapenv:Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>INVALID_SESSION_ID: Invalid Session ID</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>';

    private static String lastBody;

    private class MetadataMock implements HttpCalloutMock {
        private final String body;

        MetadataMock(String body) {
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            lastBody = request.getBody();
            HttpResponse response = new HttpResponse();
            response.setStatusCode(body == FAULT ? 500 : 200);
            response.setBody(body);
            return response;
        }
    }

    @TestSetup
    static void createUsers() {
        TestUsers.withPermissionSets(FIELD_ADMIN);
        TestUsers.admin();
    }

    private static ImportNewFieldService.FieldRequest picklist(String apiName) {
        ImportNewFieldService.FieldRequest request = new ImportNewFieldService.FieldRequest();
        request.objectApiName = 'Account';
        request.label = 'Shirt Size';
        request.apiName = apiName;
        request.type = 'Picklist';
        request.values = new List<String>{ 'S', 'M & L' };
        return request;
    }

    private static void connectedAdmin() {
        ImportNewFieldService.systemPermissionOverride = true;
        ImportNewFieldService.connectedOverride = true;
    }

    private static String alternateEmail() {
        return NamespaceUtil.qualify('Alternate_Email');
    }

    @IsTest
    static void createsTheFieldAndMapsItOnceDescribed() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            connectedAdmin();
            Test.setMock(HttpCalloutMock.class, new MetadataMock(SUCCESS));
            Test.startTest();
            Id jobId = ImportNewFieldController.createField(JSON.serialize(picklist('Shirt_Size')));
            Test.stopTest();
            Test.getEventBus().deliver();

            Assert.isTrue(lastBody.contains('<met:createMetadata>'), lastBody);
            Assert.isTrue(lastBody.contains('<met:fullName>Account.Shirt_Size__c</met:fullName>'));
            Assert.isTrue(lastBody.contains('<met:fullName>M &amp; L</met:fullName>'), 'escaped');
            Assert.isTrue(lastBody.contains('<met:type>Picklist</met:type>'));
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Error' WITH SYSTEM_MODE],
                'nothing logged'
            );
            // The created field is read from describe; an existing field stands in for it.
            ImportNewFieldService.Outcome outcome = ImportNewFieldController.checkField(
                jobId,
                'Account',
                alternateEmail()
            );
            Assert.areEqual(ImportNewFieldService.CREATED, outcome.state);
            Assert.areEqual(alternateEmail() + '__c', outcome.fieldValue);
        }
    }

    /**
     * The failed job's one Error Log entry, delivered from ErrorLogger's event, names the reason,
     * and the poll reports it.
     */
    private static void assertReported(
        ImportNewFieldService.Outcome outcome,
        String reason,
        Id jobId
    ) {
        List<Error_Log__c> logged = [
            SELECT Message__c, Context__c
            FROM Error_Log__c
            WHERE Severity__c = 'Error'
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, logged.size(), 'One entry for job ' + jobId);
        Assert.isTrue(logged[0].Message__c.contains(reason), logged[0].Message__c);
        Assert.areEqual(logged[0].Message__c, outcome.message, logged[0].Context__c);
    }

    @IsTest
    static void aRefusedFieldIsLoggedAndReported() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            connectedAdmin();
            Test.setMock(HttpCalloutMock.class, new MetadataMock(REFUSED));
            Test.startTest();
            Id jobId = ImportNewFieldService.start(picklist('Shirt_Size'));
            Test.stopTest();
            Test.getEventBus().deliver();

            ImportNewFieldService.Outcome outcome = ImportNewFieldService.check(
                jobId,
                'Account',
                'Shirt_Size'
            );
            Assert.areEqual(ImportNewFieldService.FAILED, outcome.state);
            assertReported(outcome, 'Too many custom fields', jobId);
        }
    }

    @IsTest
    static void aConnectionFaultIsLoggedInPlainWords() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            connectedAdmin();
            Test.setMock(HttpCalloutMock.class, new MetadataMock(FAULT));
            Test.startTest();
            Id jobId = ImportNewFieldService.start(picklist('Shirt_Size'));
            Test.stopTest();
            Test.getEventBus().deliver();

            ImportNewFieldService.Outcome outcome = ImportNewFieldService.check(
                jobId,
                'Account',
                'Shirt_Size'
            );
            Assert.areEqual(ImportNewFieldService.FAILED, outcome.state);
            assertReported(outcome, 'INVALID_SESSION_ID', jobId);
        }
    }

    @IsTest
    static void refusesWithoutThePermissions() {
        System.runAs(TestUsers.admin()) {
            ImportNewFieldService.systemPermissionOverride = true;
            ImportNewFieldService.connectedOverride = true;
            Assert.isFalse(ImportNewFieldService.connection().canCreate, 'no Metadata Admin');
            try {
                ImportNewFieldService.start(picklist('Shirt_Size'));
                Assert.fail('Expected a refusal');
            } catch (ImportNewFieldService.NewFieldException e) {
                Assert.areEqual(Label.Core_ImportNewField_NoPermission, e.getMessage());
            }
        }
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            ImportNewFieldService.systemPermissionOverride = false;
            try {
                ImportNewFieldController.createField(JSON.serialize(picklist('Shirt_Size')));
                Assert.fail('Expected a refusal');
            } catch (AuraHandledException e) {
                Assert.areEqual(Label.Core_ImportNewField_NoPermission, e.getMessage());
            }
        }
    }

    @IsTest
    static void refusesWithoutAConnection() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            ImportNewFieldService.systemPermissionOverride = true;
            ImportNewFieldService.connectedOverride = false;
            Assert.isFalse(ImportNewFieldController.getConnection().connected);
            try {
                ImportNewFieldService.start(picklist('Shirt_Size'));
                Assert.fail('Expected a refusal');
            } catch (ImportNewFieldService.NewFieldException e) {
                Assert.areEqual(Label.Core_ImportNewField_NotConnected, e.getMessage());
            }
            Assert.isTrue(ImportNewFieldController.setUpConnection().canCreate);
            // Refresh Fields after creating the field in Setup.
            Assert.areEqual(
                ImportNewFieldService.CREATED,
                ImportNewFieldController.findField('Account', alternateEmail() + '__c').state
            );
            Assert.areEqual(
                ImportNewFieldService.RUNNING,
                ImportNewFieldController.findField('Account', 'Not_Created_Yet').state
            );
        }
    }

    @IsTest
    static void refusesANameAlreadyOnTheObject() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            connectedAdmin();
            try {
                ImportNewFieldService.start(picklist(alternateEmail()));
                Assert.fail('Expected a refusal');
            } catch (ImportNewFieldService.NewFieldException e) {
                Assert.areEqual(Label.Core_ImportNewField_NameTaken, e.getMessage());
            }
        }
    }

    // runs-as: deploying user (pure logic: validates a request against describe, no DML or SOQL)
    @IsTest
    static void checksNamesTypesAndValues() {
        ImportNewFieldService.FieldRequest request = picklist('Order');
        Assert.isTrue(String.join(ImportNewFieldService.problems(request), ' ').contains('Order'));
        for (String bad : new List<String>{ '1st', 'Two__Bars', 'Ends_', 'Has Space', '' }) {
            request.apiName = bad;
            Assert.areEqual(
                new List<String>{ Label.Core_ImportNewField_NameInvalid },
                ImportNewFieldService.problems(request),
                bad
            );
        }
        request.apiName = 'Shirt_Size';
        request.values = new List<String>{ 'S', 's' };
        Assert.areEqual(
            new List<String>{ Label.Core_ImportNewField_PicklistInvalid },
            ImportNewFieldService.problems(request)
        );
        request.type = 'Text';
        request.length = 300;
        Assert.areEqual(
            new List<String>{ Label.Core_ImportNewField_LengthInvalid },
            ImportNewFieldService.problems(request)
        );
        request.type = 'Currency';
        request.scale = 2;
        Assert.isTrue(ImportNewFieldService.problems(request).isEmpty());
        String xml = ImportNewFieldService.fieldXml(request);
        Assert.isTrue(xml.contains('<met:precision>18</met:precision><met:scale>2</met:scale>'));
        request.type = 'Formula';
        request.objectApiName = 'No_Such_Object__c';
        Assert.areEqual(2, ImportNewFieldService.problems(request).size());
    }

    @IsTest
    static void grantsAccessThroughTheChosenPermissionSet() {
        System.runAs(TestUsers.withPermissionSets(FIELD_ADMIN)) {
            PermissionSet chosen = new PermissionSet(Name = 'Barn_Test_Chosen', Label = 'Chosen');
            insert as system chosen;
            insert as system new ObjectPermissions(
                ParentId = chosen.Id,
                SobjectType = 'Account',
                PermissionsRead = true
            );
            String field = alternateEmail() + '__c';
            ImportNewFieldService.grantAccess('Account', field, chosen.Id, 'test');
            ImportNewFieldService.grantAccess('Account', field, chosen.Id, 'test');

            List<FieldPermissions> rows = [
                SELECT PermissionsRead, PermissionsEdit
                FROM FieldPermissions
                WHERE ParentId = :chosen.Id AND Field = :('Account.' + field)
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(1, rows.size(), 'granted once, however often it runs');
            Assert.isTrue(rows[0].PermissionsRead && rows[0].PermissionsEdit);
        }
    }
}
