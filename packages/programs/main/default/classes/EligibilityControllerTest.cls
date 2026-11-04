/**
 * The Eligibility Rules panel's server side (P-14, R-EN8): the state it shows, saving rules after
 * checking them, and screening open enrollments (the status, basis, reason and date it sets).
 */
@IsTest(testFor='ApexClass:EligibilityController')
private class EligibilityControllerTest {
    private static final String ADMIN = 'Programs_Admin';

    private static final String RULES =
        '{"version":1,"defaultResult":"Review","defaultReason":"Needs a look",' +
        '"rules":[' +
        '{"id":"r1","all":[{"field":"Referral_Source__c","operator":"equals","value":"Self"}],"result":"Not Eligible","reason":"Self referral is not accepted","basis":"Referral"},' +
        '{"id":"r2","all":[{"field":"Referral_Source__c","operator":"in","value":["School","Another Agency"]}],"result":"Eligible","reason":"Referred by a partner","basis":"Referral"}]}';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        );
    }

    /** A program with these rules and three open enrollments with these referral sources. */
    private static Program__c programWith(String rules, List<String> sources) {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
        Program__c program = new Program__c(Name = 'Pantry', Eligibility_Rules__c = rules);
        insert program;
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < sources.size(); i++) {
            people.add(HouseholdTestDataFactory.newContact('Person' + i, 'Screen'));
        }
        insert people;
        List<Enrollment__c> enrollments = new List<Enrollment__c>();
        for (Integer i = 0; i < sources.size(); i++) {
            enrollments.add(
                new Enrollment__c(
                    Program__c = program.Id,
                    Contact__c = people[i].Id,
                    Referral_Source__c = sources[i]
                )
            );
        }
        insert enrollments;
        return program;
    }

    private static Map<String, Enrollment__c> bySource(Id programId) {
        Map<String, Enrollment__c> result = new Map<String, Enrollment__c>();
        for (Enrollment__c each : [
            SELECT
                Referral_Source__c,
                Eligibility_Status__c,
                Eligibility_Basis__c,
                Eligibility_Reason__c,
                Eligibility_Date__c
            FROM Enrollment__c
            WHERE Program__c = :programId
        ]) {
            result.put(each.Referral_Source__c, each);
        }
        return result;
    }

    @IsTest
    static void theStateListsTheOrgsIntakeFieldsAndOpenEnrollments() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c program = programWith(RULES, new List<String>{ 'Self', 'School' });

            EligibilityController.State state = EligibilityController.getState(program.Id);

            Assert.areEqual(RULES, state.rules, 'The saved rules.');
            Assert.isTrue(state.canEdit, 'Admin edits the rules.');
            Assert.isTrue(state.canScreen, 'Admin screens.');
            Set<String> names = new Set<String>();
            for (EligibilityController.Field field : state.fields) {
                names.add(field.apiName);
            }
            Assert.isTrue(names.contains('Referral_Source__c'), 'An intake picklist is offered.');
            Assert.isTrue(names.contains('Intake_Date__c'), 'An intake date is offered.');
            Assert.isFalse(names.contains('Eligibility_Status__c'), 'The result fields are not.');
            Assert.isFalse(names.contains('Contact__c'), 'A lookup is not.');
            Assert.isTrue(state.bases.contains('Income'), 'The basis choices.');
            Assert.areEqual(2, state.people.size(), 'Both open enrollments.');
            Assert.isNotNull(state.people[0].name, 'Each with a name.');
            Assert.isTrue(state.people[0].values.containsKey('Referral_Source__c'), 'And values.');
        }
    }

    @IsTest
    static void aReaderSeesRulesButCannotChangeOrScreen() {
        Id programId;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            programId = programWith(RULES, new List<String>{ 'Self' }).Id;
        }
        System.runAs(TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        )) {
            EligibilityController.State state = EligibilityController.getState(programId);
            Assert.isFalse(state.canEdit, 'A reader cannot edit.');
            Assert.isFalse(state.canScreen, 'A reader cannot screen.');
        }
    }

    @IsTest
    static void savingChecksTheRulesThenStoresThem() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c program = programWith(null, new List<String>());

            List<String> problems = EligibilityController.saveRules(
                program.Id,
                '{"rules":[{"id":"r1","all":[{"field":"Contact__c","operator":"isBlank"}],"result":"Review","reason":"x"}]}'
            );
            Assert.areEqual(1, problems.size(), 'A field that is not offered is refused.');
            Assert.isNull(
                [SELECT Eligibility_Rules__c FROM Program__c WHERE Id = :program.Id]
                .Eligibility_Rules__c,
                'Nothing was stored.'
            );

            Assert.isTrue(EligibilityController.saveRules(program.Id, RULES).isEmpty(), 'Sound.');
            Assert.areEqual(
                RULES,
                [SELECT Eligibility_Rules__c FROM Program__c WHERE Id = :program.Id]
                .Eligibility_Rules__c,
                'Stored.'
            );

            Assert.isTrue(EligibilityController.saveRules(program.Id, '  ').isEmpty(), 'Cleared.');
            Assert.isNull(
                [SELECT Eligibility_Rules__c FROM Program__c WHERE Id = :program.Id]
                .Eligibility_Rules__c,
                'Blank clears the rules.'
            );
        }
    }

    @IsTest
    static void screeningSetsStatusBasisReasonAndDate() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c program = programWith(RULES, new List<String>{ 'Self', 'School', 'Other' });

            EligibilityController.Summary summary = EligibilityController.screen(
                program.Id,
                null,
                false
            );

            Assert.areEqual(1, summary.eligible, 'School.');
            Assert.areEqual(1, summary.notEligible, 'Self.');
            Assert.areEqual(1, summary.review, 'Other falls to the default.');
            Map<String, Enrollment__c> result = bySource(program.Id);
            Enrollment__c notEligible = result.get('Self');
            Assert.areEqual('Not Eligible', notEligible.Eligibility_Status__c, 'Status.');
            Assert.areEqual('Referral', notEligible.Eligibility_Basis__c, 'Basis from the rule.');
            Assert.areEqual(
                'Self referral is not accepted',
                notEligible.Eligibility_Reason__c,
                'Reason from the rule.'
            );
            Assert.areEqual(Date.today(), notEligible.Eligibility_Date__c, 'Decided today.');
            Enrollment__c review = result.get('Other');
            Assert.areEqual('Review', review.Eligibility_Status__c, 'Review.');
            Assert.areEqual('Needs a look', review.Eligibility_Reason__c, 'Default reason.');
            Assert.isNull(review.Eligibility_Date__c, 'Review is not a decision.');
        }
    }

    @IsTest
    static void aBulkRunLeavesDecidedEnrollmentsAloneUnlessAsked() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c program = programWith(RULES, new List<String>{ 'Self', 'School' });
            Enrollment__c decided = bySource(program.Id).get('Self');
            decided.Eligibility_Status__c = 'Eligible';
            decided.Eligibility_Reason__c = 'Decided by hand';
            update decided;

            EligibilityController.Summary plain = EligibilityController.screen(
                program.Id,
                null,
                false
            );
            Assert.areEqual(1, plain.skipped, 'The hand decision is left alone.');
            Assert.areEqual(
                'Decided by hand',
                bySource(program.Id).get('Self').Eligibility_Reason__c,
                'Unchanged.'
            );

            EligibilityController.Summary single = EligibilityController.screen(
                program.Id,
                decided.Id,
                false
            );
            Assert.areEqual(1, single.notEligible, 'One enrollment asked for is always screened.');
            Assert.areEqual(
                'Not Eligible',
                bySource(program.Id).get('Self').Eligibility_Status__c,
                'Changed.'
            );

            decided.Eligibility_Status__c = 'Eligible';
            update decided;
            EligibilityController.Summary all = EligibilityController.screen(
                program.Id,
                null,
                true
            );
            Assert.areEqual(0, all.skipped, 'Include decided screens everyone.');
            Assert.areEqual(
                'Not Eligible',
                bySource(program.Id).get('Self').Eligibility_Status__c,
                'Changed back by the rules.'
            );
        }
    }

    @IsTest
    static void aProgramWithoutRulesScreensNothing() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c program = programWith(null, new List<String>{ 'Self' });

            EligibilityController.Summary summary = EligibilityController.screen(
                program.Id,
                null,
                false
            );

            Assert.isTrue(summary.noRules, 'Nothing to apply.');
            Assert.areEqual(
                'Not Screened',
                bySource(program.Id).get('Self').Eligibility_Status__c,
                'Untouched.'
            );
        }
    }

    @IsTest
    static void aMissingProgramIsRefusedInPlainWords() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c program = programWith(RULES, new List<String>());
            Id gone = program.Id;
            delete program;
            try {
                EligibilityController.getState(gone);
                Assert.fail('A missing program must be refused.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    BarnHelp.text('Programs', 'Programs_Fail_Elig'),
                    refused.getMessage(),
                    'Said in the label.'
                );
            }
        }
    }
}
