/**
 * Eligibility rules (P-14, R-EN8): the checks on a rule set, and what each operator decides. The
 * same cases are in `eligibilityEngine.test.js`; the Apex and the preview must agree.
 */
@IsTest(testFor='ApexClass:EligibilityRules')
private class EligibilityRulesTest {
    // runs-as: deploying user (pure logic: parses and evaluates a JSON rule set, no DML or SOQL)
    private static final Set<String> FIELDS = new Set<String>{
        'referral_source__c',
        'intake_date__c',
        'household_size__c'
    };

    private static String rules(String conditions, String result) {
        return '{"version":1,"rules":[{"id":"r1","all":[' +
            conditions +
            '],"result":"' +
            result +
            '","reason":"Because","basis":"Income"}]}';
    }

    private static EligibilityRules.Result decide(String conditions, Map<String, Object> values) {
        return EligibilityRules.evaluate(rules(conditions, 'Eligible'), values);
    }

    @IsTest
    static void blankRulesAreSoundAndDecideNothing() {
        Assert.isTrue(EligibilityRules.validate(null, FIELDS).isEmpty(), 'Nothing to check.');
        Assert.isTrue(EligibilityRules.validate('  ', FIELDS).isEmpty(), 'Nothing to check.');
        Assert.isNull(EligibilityRules.evaluate(null, new Map<String, Object>()), 'No rules.');
        Assert.isNull(
            EligibilityRules.evaluate('{"version":1,"rules":[]}', new Map<String, Object>()),
            'An empty list decides nothing.'
        );
    }

    @IsTest
    static void soundRulesPass() {
        String json = rules(
            '{"field":"Referral_Source__c","operator":"in","value":["Self","School"]},' +
                '{"field":"Household_Size__c","operator":"greaterThan","value":3},' +
                '{"field":"Intake_Date__c","operator":"isNotBlank"}',
            'Eligible'
        );
        Assert.areEqual(0, EligibilityRules.validate(json, FIELDS).size(), 'Sound.');
    }

    @IsTest
    static void eachKindOfProblemIsReported() {
        Assert.areEqual(
            1,
            EligibilityRules.validate('not json', FIELDS).size(),
            'Unreadable JSON.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate('{"defaultResult":"Maybe","rules":[]}', FIELDS).size(),
            'Bad default result.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate(
                    rules('{"field":"Other__c","operator":"equals","value":"x"}', 'Eligible'),
                    FIELDS
                )
                .size(),
            'A field that is not offered.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate(
                    rules(
                        '{"field":"Referral_Source__c","operator":"like","value":"x"}',
                        'Eligible'
                    ),
                    FIELDS
                )
                .size(),
            'An operator that is not offered.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate(
                    rules('{"field":"Referral_Source__c","operator":"equals"}', 'Eligible'),
                    FIELDS
                )
                .size(),
            'A missing value.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate(
                    rules('{"field":"Referral_Source__c","operator":"in","value":[]}', 'Eligible'),
                    FIELDS
                )
                .size(),
            'An empty choice list.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate(
                    rules('{"field":"Referral_Source__c","operator":"isBlank"}', 'Perhaps'),
                    FIELDS
                )
                .size(),
            'A result that is not offered.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate(
                    '{"rules":[{"id":"r1","all":[],"result":"Eligible","reason":"x"}]}',
                    FIELDS
                )
                .size(),
            'A rule needs a condition.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate(
                    '{"rules":[{"id":"r1","all":[{"field":"Referral_Source__c","operator":"isBlank"}],"result":"Eligible"}]}',
                    FIELDS
                )
                .size(),
            'A rule needs a reason.'
        );
        Assert.areEqual(
            1,
            EligibilityRules.validate('{"rules":["x"]}', FIELDS).size(),
            'A rule that is not an object.'
        );
        List<String> many = new List<String>();
        for (Integer i = 0; i <= EligibilityRules.MAX_RULES; i++) {
            many.add(
                '{"id":"r' +
                    i +
                    '","all":[{"field":"Intake_Date__c","operator":"isBlank"}],"result":"Review","reason":"x"}'
            );
        }
        Assert.areEqual(
            1,
            EligibilityRules.validate('{"rules":[' + String.join(many, ',') + ']}', FIELDS).size(),
            'Too many rules.'
        );
        Assert.isTrue(
            EligibilityRules.validate(
                    rules('{"field":"Other__c","operator":"equals","value":"x"}', 'Eligible'),
                    null
                )
                .isEmpty(),
            'Without a field list the field is not checked.'
        );
    }

    @IsTest
    static void equalityIgnoresCaseAndComparesNumbersAsNumbers() {
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Referral_Source__c","operator":"equals","value":"self"}',
                    new Map<String, Object>{ 'referral_source__c' => ' Self ' }
                )
                .status,
            'Capitals and spaces do not matter.'
        );
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Household_Size__c","operator":"equals","value":"4"}',
                    new Map<String, Object>{ 'Household_Size__c' => 4.0 }
                )
                .status,
            'Numbers compare as numbers, and field names without regard to case.'
        );
        Assert.areEqual(
            'Review',
            decide(
                    '{"field":"Referral_Source__c","operator":"notEquals","value":"Self"}',
                    new Map<String, Object>{ 'Referral_Source__c' => 'Self' }
                )
                .status,
            'Not equal fails, so the default Review decides.'
        );
    }

    @IsTest
    static void listsOrderingAndBlanks() {
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Referral_Source__c","operator":"in","value":["Self","School"]}',
                    new Map<String, Object>{ 'Referral_Source__c' => 'School' }
                )
                .status,
            'In a list.'
        );
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Referral_Source__c","operator":"notIn","value":["Self","School"]}',
                    new Map<String, Object>{ 'Referral_Source__c' => 'Other' }
                )
                .status,
            'Not in a list.'
        );
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Household_Size__c","operator":"greaterOrEqual","value":3},{"field":"Household_Size__c","operator":"lessThan","value":10}',
                    new Map<String, Object>{ 'Household_Size__c' => 10 - 1 }
                )
                .status,
            'Both conditions hold.'
        );
        Assert.areEqual(
            'Review',
            decide(
                    '{"field":"Household_Size__c","operator":"lessOrEqual","value":3}',
                    new Map<String, Object>{ 'Household_Size__c' => 'many' }
                )
                .status,
            'Text never satisfies an order.'
        );
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Intake_Date__c","operator":"greaterThan","value":"2026-01-01"}',
                    new Map<String, Object>{ 'Intake_Date__c' => '2026-03-15' }
                )
                .status,
            'Dates order as dates.'
        );
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Intake_Date__c","operator":"isBlank"}',
                    new Map<String, Object>{ 'Intake_Date__c' => null }
                )
                .status,
            'Blank.'
        );
        Assert.areEqual(
            'Eligible',
            decide(
                    '{"field":"Intake_Date__c","operator":"isNotBlank"}',
                    new Map<String, Object>{ 'Intake_Date__c' => '2026-03-15' }
                )
                .status,
            'Not blank.'
        );
    }

    @IsTest
    static void theFirstMatchingRuleDecidesElseTheDefault() {
        String json =
            '{"version":1,"defaultResult":"Not Eligible","defaultReason":"Nothing fits",' +
            '"rules":[' +
            '{"id":"a","all":[{"field":"Referral_Source__c","operator":"equals","value":"Self"}],"result":"Review","reason":"Self referred","basis":"Referral"},' +
            '{"id":"b","all":[{"field":"Referral_Source__c","operator":"isNotBlank"}],"result":"Eligible","reason":"Referred"}]}';
        EligibilityRules.Result first = EligibilityRules.evaluate(
            json,
            new Map<String, Object>{ 'Referral_Source__c' => 'Self' }
        );
        Assert.areEqual('Review', first.status, 'The first matching rule wins.');
        Assert.areEqual('Self referred', first.reason, 'Its reason.');
        Assert.areEqual('Referral', first.basis, 'Its basis.');
        Assert.areEqual('a', first.ruleId, 'Its id.');
        Assert.areEqual(
            'Eligible',
            EligibilityRules.evaluate(
                    json,
                    new Map<String, Object>{ 'Referral_Source__c' => 'School' }
                )
                .status,
            'The second applies when the first does not.'
        );
        EligibilityRules.Result none = EligibilityRules.evaluate(
            json,
            new Map<String, Object>{ 'Referral_Source__c' => null }
        );
        Assert.areEqual('Not Eligible', none.status, 'The default result.');
        Assert.areEqual('Nothing fits', none.reason, 'The default reason.');
        Assert.isNull(none.ruleId, 'No rule decided.');
        EligibilityRules.Result plain = EligibilityRules.evaluate(
            rules('{"field":"Intake_Date__c","operator":"isNotBlank"}', 'Eligible'),
            new Map<String, Object>()
        );
        Assert.areEqual('Review', plain.status, 'Review when no default is given.');
        Assert.areEqual(Label.Programs_Elig_NoRuleMatched, plain.reason, 'The label says so.');
    }
}
