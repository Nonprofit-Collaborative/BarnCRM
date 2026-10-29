/**
 * The Inbound Gift API permission set is all the integration user needs (X-03, ADR-0051): every
 * test here runs as a user holding that set and nothing else, on the Standard User profile, and
 * records gifts through both entry points.
 *
 * The donors are owned by the integration user, because on an org with private contacts and
 * accounts it finds only donors it can see; the admin guide tells Maria to share them with it.
 */
@IsTest(testFor='ApexClass:InboundGift, ApexClass:InboundGiftResource, ApexClass:InboundGiftAction')
private class InboundGiftAccessTest {
    private static final String EMAIL = 'luis.garcia.access@example.org';
    private static final String BUILDING_CODE = '4100';

    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User integration = TestDataFactory.createUser(
                'InboundOnly',
                new List<String>{ 'Inbound_Gift_API' }
            );
            TestDataFactory.pausedSettings(1);
            insert new List<Fund__c>{
                new Fund__c(Name = 'General Fund', Active__c = true, Is_Default__c = true),
                new Fund__c(
                    Name = 'Building Fund',
                    Active__c = true,
                    Accounting_Code__c = BUILDING_CODE
                )
            };
            insert new Appeal__c(Name = 'Spring Appeal');
            Account household = new Account(
                Name = 'The Garcia Household',
                RecordTypeId = HouseholdService.householdRecordTypeId(),
                OwnerId = integration.Id
            );
            Account riverside = new Account(
                Name = 'Riverside Foundation',
                OwnerId = integration.Id
            );
            Database.insert(new List<Account>{ household, riverside }, AccessLevel.SYSTEM_MODE);
            // Two people in one household, so a gift from Luis earns Maria an automatic household
            // soft credit (R-SC3, on by default), which the integration user's save creates.
            insert new List<Contact>{
                new Contact(
                    FirstName = 'Luis',
                    LastName = 'Garcia',
                    Email = EMAIL,
                    AccountId = household.Id,
                    OwnerId = integration.Id
                ),
                new Contact(
                    FirstName = 'Maria',
                    LastName = 'Garcia',
                    AccountId = household.Id,
                    OwnerId = integration.Id
                )
            };
            BarnCRM_Settings__c running = TestDataFactory.defaultSettings();
            running.Automation_Paused_Until__c = null;
            TestDataFactory.saveSettings(running);
        }
    }

    private static User integrationUser() {
        return [SELECT Id FROM User WHERE LastName = 'InboundOnly' LIMIT 1];
    }

    private static Map<String, Object> post(String body) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/v1/gifts';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        RestContext.request = request;
        RestContext.response = new RestResponse();
        InboundGiftResource.create();
        Map<String, Object> answer = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        answer.put('status', RestContext.response.statusCode);
        return answer;
    }

    @IsTest
    static void theRestEndpointRecordsADesignatedGiftAndAnswersAResend() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String body =
                '{"externalId":"stripe:ch_access","amount":50,"paymentMethod":"Card",' +
                '"donorEmail":"' +
                EMAIL +
                '","fundCode":"' +
                BUILDING_CODE +
                '","appealId":"' +
                [SELECT Id FROM Appeal__c]
                .Id +
                '","paymentReference":"ch_access"}';
            Map<String, Object> first;
            Map<String, Object> again;
            System.runAs(integrationUser()) {
                Test.startTest();
                first = post(body);
                again = post(body);
                Test.stopTest();
            }

            Assert.areEqual(201, first.get('status'), String.valueOf(first));
            Assert.areEqual(200, again.get('status'), String.valueOf(again));
            Assert.areEqual(first.get('giftId'), again.get('giftId'));
            Gift__c recorded = [
                SELECT
                    Donor_Contact__c,
                    Appeal__c,
                    Amount__c,
                    (SELECT Fund__r.Accounting_Code__c, Amount__c FROM Gift_Allocations__r)
                FROM Gift__c
            ];
            Assert.areEqual(
                [SELECT Id FROM Contact WHERE Email = :EMAIL].Id,
                recorded.Donor_Contact__c
            );
            Assert.areEqual(1, recorded.Gift_Allocations__r.size());
            Assert.areEqual(
                BUILDING_CODE,
                recorded.Gift_Allocations__r[0].Fund__r.Accounting_Code__c
            );
            Assert.areEqual(50, recorded.Gift_Allocations__r[0].Amount__c);
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Soft_Credit__c WHERE Contact__r.FirstName = 'Maria'],
                'The household soft credit Giving adds was saved by the integration user.'
            );
        }
    }

    @IsTest
    static void aGiftIsRecordedWhileAcknowledgmentRulesAreOn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            settings.Acknowledgments_Enabled__c = true;
            upsert settings;
            insert new Acknowledgment_Rule__c(
                Name = 'First gifts by letter',
                Order__c = 1,
                Channel__c = 'Letter',
                Active__c = true,
                First_Gift_Only__c = true
            );
            InboundGift request = new InboundGift();
            request.externalId = 'ack:access';
            request.amount = 30;
            request.paymentMethod = 'Check';
            request.donorEmail = EMAIL;
            List<InboundGiftResult> results;
            System.runAs(integrationUser()) {
                Test.startTest();
                results = InboundGiftAction.record(new List<InboundGift>{ request });
                Test.stopTest();
            }

            Assert.areEqual(
                InboundGiftResult.OUTCOME_CREATED,
                results[0].outcome,
                results[0].message
            );
        }
    }

    @IsTest
    static void theFlowActionRecordsAnOrganizationsGiftToTheDefaultFund() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            InboundGift grant = new InboundGift();
            grant.externalId = 'daf:access';
            grant.amount = 2500;
            grant.paymentMethod = 'Grant';
            grant.donorId = [SELECT Id FROM Account WHERE Name = 'Riverside Foundation'].Id;
            grant.fundId = [SELECT Id FROM Fund__c WHERE Name = 'General Fund'].Id;
            InboundGift byEmail = new InboundGift();
            byEmail.externalId = 'flow:access';
            byEmail.amount = 15;
            byEmail.paymentMethod = 'Cash';
            byEmail.donorEmail = EMAIL;
            List<InboundGiftResult> results;
            System.runAs(integrationUser()) {
                Test.startTest();
                results = InboundGiftAction.record(new List<InboundGift>{ grant, byEmail });
                Test.stopTest();
            }

            for (InboundGiftResult result : results) {
                Assert.areEqual(InboundGiftResult.OUTCOME_CREATED, result.outcome, result.message);
            }
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Gift_Allocation__c WHERE Fund__r.Name = 'General Fund']
            );
        }
    }

    @IsTest
    static void theActionSetOpensOnlyTheFlowAction() {
        System.runAs(TestUsers.admin()) {
            List<SetupEntityAccess> grants = [
                SELECT SetupEntityId
                FROM SetupEntityAccess
                WHERE Parent.Name = 'Record_Inbound_Gift_Action' AND SetupEntityType = 'ApexClass'
                WITH SYSTEM_MODE
            ];
            List<ApexClass> action = [
                SELECT Id
                FROM ApexClass
                WHERE Name = 'InboundGiftAction'
                WITH SYSTEM_MODE
            ];

            Assert.areEqual(1, action.size(), 'The action class is in the org');
            Assert.areEqual(1, grants.size(), 'The set opens one class and nothing else');
            Assert.areEqual(action[0].Id, grants[0].SetupEntityId, 'That class is the action');
        }
    }
}
