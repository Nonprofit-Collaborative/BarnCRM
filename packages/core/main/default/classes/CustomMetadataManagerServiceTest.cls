/**
 * The custom metadata manager's rules: Maria adds and archives her own relationship types,
 * never a shipped one, and only with values the Type list already offers.
 *
 * Metadata.Operations cannot deploy in a test, so the deployer is replaced by one that keeps
 * the container it was given; the tests read what would have been deployed.
 */
@IsTest(testFor='ApexClass:CustomMetadataManagerService')
private class CustomMetadataManagerServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String TYPE_NAME = 'Relationship_Type__mdt';
    private static final Id FAKE_JOB = FakeIds.ofPrefix('0Af', 1);

    private class CapturingDeployer implements CustomMetadataManagerService.Deployer {
        public Metadata.DeployContainer container;
        public Metadata.DeployCallback callback;
        public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            this.container = container;
            this.callback = callback;
            return FAKE_JOB;
        }
    }

    private class DeployRefusedException extends Exception {
    }

    /** What an org without the Apex deploy setting does: the enqueue itself throws. */
    private class RefusingDeployer implements CustomMetadataManagerService.Deployer {
        public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            throw new DeployRefusedException('Deploy Metadata from Non-Certified Package Versions');
        }
    }

    private static CustomMetadataManagerSelector.StoredRow row(
        String developerName,
        String type,
        String reciprocal,
        Boolean active,
        Boolean shipped
    ) {
        CustomMetadataManagerSelector.StoredRow stored = new CustomMetadataManagerSelector.StoredRow();
        stored.developerName = developerName;
        stored.label = type;
        stored.values.put('Type__c', type);
        stored.values.put('Reciprocal_Type__c', reciprocal);
        stored.values.put('Description__c', null);
        stored.values.put('Active__c', active);
        stored.values.put('Is_Shipped__c', shipped);
        return stored;
    }

    private static void stubRows(List<CustomMetadataManagerSelector.StoredRow> rows) {
        CustomMetadataManagerSelector.rowsOverride = new Map<String, List<CustomMetadataManagerSelector.StoredRow>>{
            Relationship_Type__mdt.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getName() => rows
        };
    }

    private static void shippedSpouseAndOwnFriend() {
        stubRows(
            new List<CustomMetadataManagerSelector.StoredRow>{
                row('Spouse', 'Spouse', 'Spouse', true, true),
                row('Org_Old_friend', 'Friend', 'Friend', false, false)
            }
        );
    }

    private static CustomMetadataManagerService.RowInput input(
        String developerName,
        String label,
        String type,
        String reciprocal
    ) {
        CustomMetadataManagerService.RowInput given = new CustomMetadataManagerService.RowInput();
        given.developerName = developerName;
        given.label = label;
        given.values = new Map<String, String>{
            'Type__c' => type,
            'Reciprocal_Type__c' => reciprocal,
            'Description__c' => 'Met through the program.'
        };
        return given;
    }

    private static Map<String, Object> valuesOf(Metadata.CustomMetadata record) {
        Map<String, Object> values = new Map<String, Object>();
        for (Metadata.CustomMetadataValue value : record.values) {
            values.put(value.field.removeStart(NamespaceUtil.prefix()), value.value);
        }
        return values;
    }

    private static String refusal(CustomMetadataManagerService.RowInput given) {
        try {
            CustomMetadataManagerService.save(TYPE_NAME, given);
        } catch (CustomMetadataManagerService.CustomMetadataManagerException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void mariaAddsATypeAndItIsDeployedAsHerOwn() {
        System.runAs(TestUsers.admin()) {
            shippedSpouseAndOwnFriend();
            CapturingDeployer deployer = new CapturingDeployer();
            CustomMetadataManagerService.deployer = deployer;

            Test.startTest();
            Id jobId = CustomMetadataManagerService.save(
                TYPE_NAME,
                input(null, 'Close friend', 'Friend', 'Friend')
            );
            Test.stopTest();

            Assert.areEqual(FAKE_JOB, jobId, 'The page waits on the deployment Id');
            Metadata.CustomMetadata record = (Metadata.CustomMetadata) deployer.container.getMetadata()[0];
            Assert.areEqual(
                NamespaceUtil.prefix() + 'Relationship_Type.Org_Close_friend',
                record.fullName,
                'A new row is named with the Org_ prefix, so no shipped row can collide with it'
            );
            Assert.areEqual('Close friend', record.label, 'The name Maria typed');
            Assert.isFalse(record.protected_x, 'Her row is not protected');
            Map<String, Object> values = valuesOf(record);
            Assert.areEqual('Friend', values.get('Type__c'), 'Type deployed');
            Assert.areEqual('Friend', values.get('Reciprocal_Type__c'), 'Reciprocal deployed');
            Assert.areEqual(true, values.get('Active__c'), 'A new row is active');
            Assert.areEqual(
                false,
                values.get('Is_Shipped__c'),
                'A new row is never marked shipped'
            );
            Assert.isNotNull(deployer.callback, 'The outcome is recorded by the callback');
        }
    }

    @IsTest
    static void aShippedRowCannotBeChangedOrArchived() {
        System.runAs(TestUsers.admin()) {
            shippedSpouseAndOwnFriend();
            CustomMetadataManagerService.deployer = new CapturingDeployer();
            String archiveRefusal;

            Test.startTest();
            String editRefusal = refusal(input('Spouse', 'Spouse', 'Spouse', 'Partner'));
            try {
                CustomMetadataManagerService.setArchived(TYPE_NAME, 'Spouse', true);
            } catch (CustomMetadataManagerService.CustomMetadataManagerException e) {
                archiveRefusal = e.getMessage();
            }
            Test.stopTest();

            String expected = String.format(
                Label.Core_CmdtManager_ShippedReadOnly,
                new List<Object>{ 'Spouse' }
            );
            Assert.areEqual(expected, editRefusal, 'A shipped row is read only');
            Assert.areEqual(expected, archiveRefusal, 'A shipped row cannot be archived either');
        }
    }

    @IsTest
    static void aTypeMissingFromTheTypeListIsRefusedWithWhereToAddIt() {
        System.runAs(TestUsers.admin()) {
            shippedSpouseAndOwnFriend();
            CustomMetadataManagerService.deployer = new CapturingDeployer();

            Test.startTest();
            String message = refusal(input(null, 'Mentor', 'Mentor', 'Friend'));
            Test.stopTest();

            Assert.areEqual(
                String.format(
                    Label.Core_CmdtManager_NotAChoice,
                    new List<Object>{
                        'Mentor',
                        Relationship__c.Type__c.getDescribe().getLabel(),
                        Relationship__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                            .getLabel()
                    }
                ),
                message,
                'The message names the value and where to add it'
            );
        }
    }

    @IsTest
    static void aSecondActiveRowForATypeIsRefused() {
        System.runAs(TestUsers.admin()) {
            shippedSpouseAndOwnFriend();
            CustomMetadataManagerService.deployer = new CapturingDeployer();

            Test.startTest();
            String message = refusal(input(null, 'My spouse', 'Spouse', 'Spouse'));
            Test.stopTest();

            Assert.areEqual(
                String.format(
                    Label.Core_CmdtManager_DuplicateActive,
                    new List<Object>{ 'Spouse', 'Spouse' }
                ),
                message,
                'Only one active row can map a type'
            );
        }
    }

    @IsTest
    static void aNameAndBothTypesAreRequired() {
        System.runAs(TestUsers.admin()) {
            shippedSpouseAndOwnFriend();
            CustomMetadataManagerService.deployer = new CapturingDeployer();

            Test.startTest();
            String noName = refusal(input(null, '  ', 'Friend', 'Friend'));
            String longName = refusal(input(null, 'A'.repeat(41), 'Friend', 'Friend'));
            String noReciprocal = refusal(input(null, 'Close friend', 'Friend', ''));
            Test.stopTest();

            Assert.areEqual(Label.Core_CmdtManager_NameRequired, noName, 'Name required');
            Assert.areEqual(Label.Core_CmdtManager_NameTooLong, longName, 'Name limit');
            Assert.areEqual(
                String.format(
                    Label.Core_CmdtManager_FieldRequired,
                    new List<Object>{
                        Relationship_Type__mdt.Reciprocal_Type__c.getDescribe().getLabel()
                    }
                ),
                noReciprocal,
                'The reciprocal is required'
            );
        }
    }

    @IsTest
    static void herOwnRowIsArchivedAndRestoredOnlyWhenItsTypeIsFree() {
        System.runAs(TestUsers.admin()) {
            stubRows(
                new List<CustomMetadataManagerSelector.StoredRow>{
                    row('Org_Old_friend', 'Friend', 'Friend', false, false),
                    row('Org_New_friend', 'Friend', 'Friend', true, false)
                }
            );
            CapturingDeployer deployer = new CapturingDeployer();
            CustomMetadataManagerService.deployer = deployer;
            String restoreRefusal;

            Test.startTest();
            CustomMetadataManagerService.setArchived(TYPE_NAME, 'Org_New_friend', true);
            Map<String, Object> archived = valuesOf(
                (Metadata.CustomMetadata) deployer.container.getMetadata()[0]
            );
            try {
                CustomMetadataManagerService.setArchived(TYPE_NAME, 'Org_Old_friend', false);
            } catch (CustomMetadataManagerService.CustomMetadataManagerException e) {
                restoreRefusal = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(false, archived.get('Active__c'), 'Archiving clears Active');
            Assert.areEqual('Friend', archived.get('Type__c'), 'Archiving keeps the values');
            Assert.isNotNull(restoreRefusal, 'Restoring is refused while another row maps Friend');
        }
    }

    @IsTest
    static void aRefusedDeploymentIsLoggedAndExplained() {
        System.runAs(TestUsers.admin()) {
            shippedSpouseAndOwnFriend();
            CustomMetadataManagerService.deployer = new RefusingDeployer();

            Test.startTest();
            String message = refusal(input(null, 'Close friend', 'Friend', 'Friend'));
            Test.stopTest();

            Assert.areEqual(Label.Core_CmdtManager_DeployRefused, message, 'Says what to turn on');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Custom metadata'],
                'The refusal is in the Error Log'
            );
        }
    }

    @IsTest
    static void newNamesAreValidAndUniqueAcrossTwoHundredRows() {
        System.runAs(TestUsers.admin()) {
            List<CustomMetadataManagerSelector.StoredRow> rows = new List<CustomMetadataManagerSelector.StoredRow>{
                row('Org_Close_friend', 'Friend', 'Friend', false, false)
            };
            for (Integer i = 2; i <= 200; i++) {
                rows.add(row('Org_Close_friend_' + i, 'Friend', 'Friend', false, false));
            }

            Test.startTest();
            String next = CustomMetadataManagerService.newDeveloperName('Close friend', rows);
            String cleaned = CustomMetadataManagerService.newDeveloperName(
                '  Mentor / mentee!! ',
                rows
            );
            String symbols = CustomMetadataManagerService.newDeveloperName('***', rows);
            String longName = CustomMetadataManagerService.newDeveloperName('B'.repeat(40), rows);
            Test.stopTest();

            Assert.areEqual('Org_Close_friend_201', next, 'The next free number');
            Assert.areEqual('Org_Mentor_mentee', cleaned, 'Runs of other characters become one _');
            Assert.areEqual('Org_Row', symbols, 'A name with no letters still gets a valid name');
            Assert.isTrue(longName.length() <= 40, 'A DeveloperName holds at most 40 characters');
        }
    }

    @IsTest
    static void thePageSeesShippedRowsApartFromHerOwn() {
        System.runAs(TestUsers.admin()) {
            shippedSpouseAndOwnFriend();

            Test.startTest();
            List<CustomMetadataManagerService.TypeView> types = CustomMetadataManagerService.getTypes();
            Test.stopTest();

            Assert.areEqual(1, types.size(), 'Relationship types is the one editable list');
            CustomMetadataManagerService.TypeView view = types[0];
            Assert.areEqual(TYPE_NAME, view.typeName, 'Named without a namespace');
            Assert.areEqual(3, view.fields.size(), 'Type, reciprocal type and description');
            Assert.isFalse(view.fields[0].choices.isEmpty(), 'Type offers the Type list choices');
            Assert.isTrue(view.rows[0].shipped, 'Spouse is shipped');
            Assert.isFalse(view.rows[0].archived, 'Spouse is in use');
            Assert.isFalse(view.rows[1].shipped, 'Her row is her own');
            Assert.isTrue(view.rows[1].archived, 'Her row is archived');
            Assert.areEqual('Friend', view.rows[1].values.get('Type__c'), 'Values are text');
        }
    }

    @IsTest
    static void everyRowThePackageShipsIsMarkedShipped() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<CustomMetadataManagerService.TypeView> types = CustomMetadataManagerService.getTypes();
            Test.stopTest();

            Integer shipped = 0;
            for (CustomMetadataManagerService.RowView view : types[0].rows) {
                if (!view.developerName.startsWith(CustomMetadataManagerService.ORG_PREFIX)) {
                    Assert.isTrue(
                        view.shipped,
                        view.developerName + ' ships and must be read only'
                    );
                    shipped++;
                }
            }
            Assert.isTrue(shipped >= 11, 'The eleven shipped relationship types are read');
        }
    }
}
