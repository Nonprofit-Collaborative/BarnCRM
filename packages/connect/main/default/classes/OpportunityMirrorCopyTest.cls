/**
 * The Opportunity mirror's copy made when a gift is saved (X-01, canonical model Section 29C), for
 * the donors, links, stages, access and volumes `OpportunityMirrorServiceTest` does not cover:
 * organizations and people held as accounts, in-kind gifts, Campaigns, typed links, a retried
 * partial save, and what one save of two hundred gifts costs.
 *
 * Opportunity is read only through dynamic queries, so this class compiles where Opportunity does
 * not exist; there each test stops once it has checked that the mirror did nothing (R-OM1).
 */
@IsTest
private class OpportunityMirrorCopyTest {
    private static final String LOG_CONTEXT = 'Opportunity mirror';
    // detection-only: read by name so this class compiles where Opportunity does not exist
    private static final String ROLE_OBJECT = 'OpportunityContactRole';

    @TestSetup
    static void setup() {
        GivingTestDataFactory.ensureDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
    }

    private static void choose(String direction) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
    }

    private static User maria() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Giving_Admin', 'Opportunity_Mirror' }
        );
    }

    private static Contact luis() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Garcia' LIMIT 1];
    }

    private static Gift__c gift(Decimal amount) {
        Gift__c gift = GivingTestDataFactory.buildGift(luis().Id, amount);
        gift.Gift_Date__c = Date.newInstance(2026, 9, 20);
        return gift;
    }

    private static Gift__c reread(Id giftId) {
        return (Gift__c) Database.queryWithBinds(
            'SELECT ' + OpportunityMirrorSelector.GIFT_FIELDS + ' FROM Gift__c WHERE Id = :giftId',
            new Map<String, Object>{ 'giftId' => giftId },
            AccessLevel.SYSTEM_MODE
        )[0];
    }

    private static String opportunityObject() {
        return OpportunityMirrorService.opportunityType().getDescribe().getName();
    }

    private static SObject opportunity(String opportunityId) {
        List<String> fields = new List<String>{ 'Id', 'Amount', 'IsWon', 'IsClosed', 'AccountId' };
        if (CampaignSyncService.isAvailable()) {
            fields.add(OpportunityMirrorService.CAMPAIGN_FIELD);
        }
        return Database.queryWithBinds(
            'SELECT ' +
                String.join(fields, ', ') +
                ' FROM ' +
                opportunityObject() +
                ' WHERE Id = :opportunityId',
            new Map<String, Object>{ 'opportunityId' => opportunityId },
            AccessLevel.SYSTEM_MODE
        )[0];
    }

    private static SObject openOpportunity(Id accountId) {
        SObject open = OpportunityMirrorService.opportunityType().newSObject();
        open.put('Name', 'Garcia pledge');
        open.put('StageName', 'Prospecting');
        open.put('CloseDate', Date.newInstance(2026, 12, 31));
        open.put('AccountId', accountId);
        return open;
    }

    private static List<SObject> primaryRoles(String opportunityId) {
        return Database.queryWithBinds(
            'SELECT ContactId FROM ' +
                ROLE_OBJECT +
                ' WHERE OpportunityId = :opportunityId AND IsPrimary = TRUE',
            new Map<String, Object>{ 'opportunityId' => opportunityId },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Integer countOpportunities() {
        return Database.countQuery(
            'SELECT COUNT() FROM ' + opportunityObject(),
            AccessLevel.SYSTEM_MODE
        );
    }

    private static List<Error_Log__c> warnings() {
        return [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Context__c = :LOG_CONTEXT AND Severity__c = 'Warning'
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void anOrganizationGivesItsOwnAccountAndNoContactRole() {
        Account acme = GivingTestDataFactory.insertOrganization('Acme Foundation');
        Gift__c grant = GivingTestDataFactory.buildAccountGift(acme.Id, 5000);
        Test.startTest();
        System.runAs(maria()) {
            insert grant;
        }
        Test.stopTest();
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        String linked = reread(grant.Id).Opportunity_Id__c;
        Assert.areEqual(acme.Id, opportunity(linked).get('AccountId'), 'The organization.');
        Assert.areEqual(0, primaryRoles(linked).size(), 'No person, so no contact role.');
    }

    @IsTest
    static void aPersonHeldAsAnAccountIsThePrimaryContact() {
        Set<Id> personTypes = OrgShapeSelector.personTypeRecordTypeIds();
        if (personTypes.isEmpty() || !OpportunityMirrorService.isAvailable()) {
            return; // An org without person accounts has no such path to prove.
        }
        SObject person = new Account(RecordTypeId = new List<Id>(personTypes)[0]);
        person.put('LastName', 'Okafor');
        insert person;
        Id personContactId = (Id) Database.query(
                'SELECT PersonContactId FROM Account WHERE Id = \'' + person.Id + '\''
            )[0]
            .get('PersonContactId');
        Gift__c given = GivingTestDataFactory.buildAccountGift(person.Id, 40);
        Test.startTest();
        System.runAs(maria()) {
            insert given;
        }
        Test.stopTest();
        List<SObject> roles = primaryRoles(reread(given.Id).Opportunity_Id__c);
        Assert.areEqual(1, roles.size(), 'One primary contact role.');
        Assert.areEqual(personContactId, roles[0].get('ContactId'), 'The person behind it.');
    }

    @IsTest
    static void anInKindGiftIsAWonOpportunityOfZero() {
        Gift__c goods = gift(0);
        goods.Type__c = 'In-kind';
        goods.In_Kind_Description__c = 'Twenty winter coats';
        Test.startTest();
        System.runAs(maria()) {
            insert goods;
        }
        Test.stopTest();
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        SObject copy = opportunity(reread(goods.Id).Opportunity_Id__c);
        Assert.areEqual(0, (Decimal) copy.get('Amount'), 'Goods are not money (ADR-0030).');
        Assert.areEqual(true, copy.get('IsWon'), 'It is in the totals, so won.');
    }

    @IsTest
    static void theAppealsCampaignIsTheOpportunitysCampaign() {
        // Maria here also links appeals to Campaigns, which the Campaign Sync set grants.
        User admin = TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Giving_Admin', 'Opportunity_Mirror', 'Campaign_Sync' }
        );
        if (!OpportunityMirrorService.isAvailable() || !CampaignSyncService.isAvailable()) {
            return;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = admin.Id, UserPermissionsMarketingUser = true);
        }
        SObject spring = CampaignSyncService.campaignType().newSObject();
        spring.put('Name', 'Spring mailing');
        System.runAs(admin) {
            insert spring;
        }
        Appeal__c appeal = GivingTestDataFactory.buildAppeal('Spring appeal');
        appeal.Campaign_Id__c = spring.Id;
        System.runAs(admin) {
            insert appeal;
        }
        Gift__c given = gift(60);
        given.Appeal__c = appeal.Id;
        Test.startTest();
        System.runAs(admin) {
            insert given;
        }
        Test.stopTest();
        Assert.areEqual(
            spring.Id,
            opportunity(reread(given.Id).Opportunity_Id__c)
                .get(OpportunityMirrorService.CAMPAIGN_FIELD),
            'The appeal\'s Campaign (R-OM3).'
        );
    }

    @IsTest
    static void typingAnExistingOpportunityLinksAndUpdatesIt() {
        User admin = maria();
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        SObject open = openOpportunity(luis().AccountId);
        System.runAs(admin) {
            insert open;
        }
        Gift__c given = gift(250);
        given.Opportunity_Id__c = String.valueOf(open.Id).left(15);
        Test.startTest();
        System.runAs(admin) {
            insert given;
        }
        Test.stopTest();
        Gift__c saved = reread(given.Id);
        Assert.areEqual(String.valueOf(open.Id), saved.Opportunity_Id__c, 'Kept in 18 characters.');
        SObject copy = opportunity(open.Id);
        Assert.areEqual(250, (Decimal) copy.get('Amount'), 'The gift is copied onto it.');
        Assert.areEqual(true, copy.get('IsWon'), 'A Received gift closes it as won.');
        Assert.areEqual(1, countOpportunities(), 'No second Opportunity.');
        Assert.areEqual(luis().Id, primaryRoles(open.Id)[0].get('ContactId'), 'Donor is primary.');
    }

    @IsTest
    static void aNewDonorReplacesThePrimaryContact() {
        User admin = maria();
        Contact ana = new Contact(
            FirstName = 'Ana',
            LastName = 'Garcia',
            AccountId = luis().AccountId
        );
        insert ana;
        Gift__c given = gift(100);
        System.runAs(admin) {
            insert given;
        }
        Test.startTest();
        System.runAs(admin) {
            update new Gift__c(Id = given.Id, Donor_Contact__c = ana.Id);
        }
        Test.stopTest();
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        List<SObject> roles = primaryRoles(reread(given.Id).Opportunity_Id__c);
        Assert.areEqual(1, roles.size(), 'Still one primary contact role.');
        Assert.areEqual(ana.Id, roles[0].get('ContactId'), 'Now the new donor.');
    }

    @IsTest
    static void aPendingGiftLeavesTheStageAndACancelledOneLosesIt() {
        User admin = maria();
        Gift__c given = gift(100);
        System.runAs(admin) {
            insert given;
        }
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        String linked = reread(given.Id).Opportunity_Id__c;
        Test.startTest();
        System.runAs(admin) {
            update new Gift__c(Id = given.Id, Status__c = 'Pending', Amount__c = 90);
            SObject pending = opportunity(linked);
            Assert.areEqual(true, pending.get('IsWon'), 'Pending leaves the stage (R-OM3).');
            Assert.areEqual(90, (Decimal) pending.get('Amount'), 'The amount still follows.');
            update new Gift__c(Id = given.Id, Status__c = 'Cancelled');
        }
        Test.stopTest();
        SObject cancelled = opportunity(linked);
        Assert.areEqual(true, cancelled.get('IsClosed'), 'Cancelled closes it.');
        Assert.areEqual(false, cancelled.get('IsWon'), 'As lost.');
    }

    @IsTest
    static void refusalsForOneReasonAreOneWarning() {
        User admin = maria();
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        List<SObject> gone = new List<SObject>{
            openOpportunity(luis().AccountId),
            openOpportunity(luis().AccountId),
            openOpportunity(luis().AccountId)
        };
        insert gone;
        List<Gift__c> gifts = new List<Gift__c>();
        for (SObject each : gone) {
            Gift__c typed = gift(10);
            typed.Opportunity_Id__c = each.Id;
            gifts.add(typed);
        }
        delete gone;
        Test.startTest();
        System.runAs(admin) {
            insert gifts;
        }
        Test.stopTest();
        List<Error_Log__c> logged = warnings();
        Assert.areEqual(1, logged.size(), 'One Warning for one message (R-OM6).');
        Assert.isTrue(
            logged[0].Message__c.contains('could not copy 3 gifts'),
            logged[0].Message__c
        );
    }

    @IsTest
    static void someoneWhoCannotCreateOpportunitiesStillSavesAndIsLoggedOnce() {
        List<Profile> readOnly = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
        if (readOnly.isEmpty()) {
            return;
        }
        // The link field comes with the permission set; Opportunity create does not.
        User rosa = TestDataFactory.createUser(
            'Rosa',
            new List<String>{ 'Giving_Admin', 'Opportunity_Mirror' }
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = rosa.Id, ProfileId = readOnly[0].Id);
        }
        Account household = new Account(Name = 'The Ruiz Household', OwnerId = rosa.Id);
        insert household;
        Contact donor = new Contact(LastName = 'Ruiz', AccountId = household.Id, OwnerId = rosa.Id);
        insert donor;
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(donor.Id, 2, 10);
        Test.startTest();
        System.runAs(rosa) {
            insert new List<Gift__c>{ gifts[0] };
            insert new List<Gift__c>{ gifts[1] };
        }
        Test.stopTest();
        Assert.isNull(reread(gifts[0].Id).Opportunity_Id__c, 'The gift saves, uncopied.');
        Assert.isNull(reread(gifts[1].Id).Opportunity_Id__c, 'So does the next one.');
        Assert.areEqual(
            OpportunityMirrorService.isAvailable() ? 1 : 0,
            warnings().size(),
            'Once per transaction (R-OM5).'
        );
    }

    @IsTest
    static void aRetriedPartialSaveKeepsNoRolledBackOpportunity() {
        List<Gift__c> gifts = new List<Gift__c>{ gift(10), gift(0), gift(30) };
        List<Database.SaveResult> saved;
        Test.startTest();
        System.runAs(maria()) {
            saved = Database.insert(gifts, false);
        }
        Test.stopTest();
        Assert.isTrue(saved[0].isSuccess() && saved[2].isSuccess(), 'The good gifts save.');
        Assert.isFalse(saved[1].isSuccess(), 'A zero amount is refused by Giving.');
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        for (Integer i : new List<Integer>{ 0, 2 }) {
            String linked = reread(saved[i].getId()).Opportunity_Id__c;
            Assert.isNotNull(linked, 'Linked after the retry.');
            Assert.areEqual(
                1,
                primaryRoles(linked).size(),
                'Linked to an Opportunity that exists.'
            );
        }
        Assert.areEqual(2, countOpportunities(), 'None left over from the rolled-back attempt.');
    }

    @IsTest
    static void twoHundredGiftsCostTheMirrorAFixedNumberOfQueriesAndStatements() {
        User admin = maria();
        choose(OpportunityMirrorService.OFF);
        Integer queries = Limits.getQueries();
        Integer statements = Limits.getDmlStatements();
        System.runAs(admin) {
            insert GivingTestDataFactory.buildGifts(luis().Id, 200, 25);
        }
        Integer queriesOff = Limits.getQueries() - queries;
        Integer statementsOff = Limits.getDmlStatements() - statements;
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(luis().Id, 200, 25);
        Test.startTest();
        System.runAs(admin) {
            queries = Limits.getQueries();
            statements = Limits.getDmlStatements();
            insert gifts;
            queries = Limits.getQueries() - queries;
            statements = Limits.getDmlStatements() - statements;
        }
        Test.stopTest();
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        Assert.areEqual(200, countOpportunities(), 'Every gift copied.');
        Assert.isTrue(queries - queriesOff <= 7, 'Queries: ' + queries + ' vs ' + queriesOff);
        Assert.isTrue(
            statements - statementsOff <= 4,
            'Statements: ' + statements + ' vs ' + statementsOff
        );
    }

    @IsTest
    static void deletingALinkedGiftLeavesItsOpportunityAndSaysSo() {
        User admin = maria();
        Gift__c kept = gift(100);
        Gift__c remade = gift(50);
        System.runAs(admin) {
            insert new List<Gift__c>{ kept, remade };
        }
        Test.startTest();
        System.runAs(admin) {
            delete kept;
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
            delete remade;
        }
        Test.stopTest();
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        Assert.areEqual(2, countOpportunities(), 'Both Opportunities stay (R-OM9).');
        List<Error_Log__c> logged = warnings();
        Assert.areEqual(2, logged.size(), 'One Warning per delete.');
        String both = logged[0].Message__c + ' ' + logged[1].Message__c;
        Assert.isTrue(both.contains('left in place'), both);
        Assert.isTrue(both.contains('makes a new gift'), 'Opportunities to Gifts says so: ' + both);
    }

    @IsTest
    static void aSaverWhoCannotReadTheAppealsCampaignLeavesTheOpportunitysCampaign() {
        // Ana links appeals to Campaigns; Maria sees Campaigns but not the appeal's Campaign ID.
        User ana = TestDataFactory.createUserOnTheRunningUsersProfile(
            'Ana',
            new List<String>{ 'Giving_Admin', 'Opportunity_Mirror', 'Campaign_Sync' }
        );
        User admin = maria();
        if (!OpportunityMirrorService.isAvailable() || !CampaignSyncService.isAvailable()) {
            return;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new List<User>{
                new User(Id = ana.Id, UserPermissionsMarketingUser = true),
                new User(Id = admin.Id, UserPermissionsMarketingUser = true)
            };
        }
        SObject autumn = CampaignSyncService.campaignType().newSObject();
        autumn.put('Name', 'Autumn mailing');
        SObject spring = CampaignSyncService.campaignType().newSObject();
        spring.put('Name', 'Spring mailing');
        SObject open = openOpportunity(luis().AccountId);
        Appeal__c appeal = GivingTestDataFactory.buildAppeal('Spring appeal');
        System.runAs(ana) {
            insert new List<SObject>{ autumn, spring };
            open.put(OpportunityMirrorService.CAMPAIGN_FIELD, autumn.Id);
            insert open;
            appeal.Campaign_Id__c = spring.Id;
            insert appeal;
        }
        Gift__c given = gift(80);
        given.Appeal__c = appeal.Id;
        given.Opportunity_Id__c = open.Id;
        Test.startTest();
        System.runAs(admin) {
            Assert.isFalse(
                Appeal__c.Campaign_Id__c.getDescribe().isAccessible(),
                'Maria cannot read the appeal\'s Campaign ID.'
            );
            insert given;
        }
        Test.stopTest();
        SObject copy = opportunity(open.Id);
        Assert.areEqual(80, (Decimal) copy.get('Amount'), 'The gift is still copied.');
        Assert.areEqual(
            autumn.Id,
            copy.get(OpportunityMirrorService.CAMPAIGN_FIELD),
            'The Campaign is left as it was, never cleared (R-OM3).'
        );
    }

    @IsTest
    static void aRetriedUpdateThatClearsALinkKeepsNoRolledBackOpportunity() {
        User admin = maria();
        Gift__c cleared = gift(10);
        Gift__c refused = gift(30);
        System.runAs(admin) {
            insert new List<Gift__c>{ cleared, refused };
        }
        List<Database.SaveResult> saved;
        Test.startTest();
        System.runAs(admin) {
            saved = Database.update(
                new List<Gift__c>{
                    new Gift__c(Id = cleared.Id, Opportunity_Id__c = null),
                    new Gift__c(Id = refused.Id, Amount__c = 0)
                },
                false
            );
        }
        Test.stopTest();
        Assert.isTrue(saved[0].isSuccess(), 'The cleared gift saves.');
        Assert.isFalse(saved[1].isSuccess(), 'A zero amount is refused by Giving.');
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        String linked = reread(cleared.Id).Opportunity_Id__c;
        Assert.isNotNull(linked, 'Linked again after the retry.');
        Assert.areEqual(1, primaryRoles(linked).size(), 'To an Opportunity that exists.');
        Assert.areEqual(3, countOpportunities(), 'Both first copies and one new one, no more.');
    }
}
