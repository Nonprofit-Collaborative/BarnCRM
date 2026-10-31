/**
 * The Format digits step (C-50f2, ADR-NEXT): DataTransform.formatDigits against the shared
 * JSON fixture the browser module `transformFormat` is tested against, the step's checks, and
 * the step run through `apply` as a bulk update or an import would run it.
 */
@IsTest(testFor='ApexClass:DataTransform')
private class DataTransformDigitsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static List<Object> fixtureCases() {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'TransformFormatFixture'
            WITH USER_MODE
            LIMIT 1
        ];
        System.assertEquals(1, resources.size(), 'The shared fixture is deployed with Core.');
        Map<String, Object> fixture = (Map<String, Object>) JSON.deserializeUntyped(
            resources[0].Body.toString()
        );
        return (List<Object>) fixture.get('cases');
    }

    private static DataTransform.Step digits(String pattern, String country) {
        DataTransform.Step step = new DataTransform.Step(DataTransform.OP_DIGITS);
        step.pattern = pattern;
        step.country = country;
        return step;
    }

    @IsTest
    static void everyFixtureCaseGivesItsExpectedValue() {
        System.runAs(TestUsers.admin()) {
            List<Object> cases = fixtureCases();
            System.assert(cases.size() > 20, 'The fixture has its cases.');
            for (Object each : cases) {
                Map<String, Object> fixtureCase = (Map<String, Object>) each;
                String name = (String) fixtureCase.get('name');
                String pattern = (String) fixtureCase.get('pattern');
                String country = (String) fixtureCase.get('country');
                String input = (String) fixtureCase.get('input');
                String expected = (String) fixtureCase.get('expected');
                System.assertEquals(
                    expected,
                    DataTransform.formatDigits(input, pattern, country),
                    name
                );
                // The step run as the engine runs it gives the same value.
                System.assertEquals(
                    expected,
                    DataTransform.apply(
                        new List<DataTransform.Step>{ digits(pattern, country) },
                        input,
                        null
                    ),
                    name + ' through apply'
                );
            }
        }
    }

    @IsTest
    static void aGoodStepPassesTheCheck() {
        System.runAs(TestUsers.admin()) {
            System.assertEquals(
                null,
                DataTransform.problemWith(digits('(###) ###-####', '1')),
                'Pattern and country code.'
            );
            System.assertEquals(
                null,
                DataTransform.problemWith(digits('###-###-####', null)),
                'No country code.'
            );
        }
    }

    @IsTest
    static void aBadStepIsRefused() {
        System.runAs(TestUsers.admin()) {
            List<DataTransform.Step> bad = new List<DataTransform.Step>{
                digits(null, '1'),
                digits('   ', '1'),
                digits('no places', ''),
                digits('#'.repeat(DataTransform.MAX_SLOTS + 1), ''),
                digits('#'.repeat(5) + '-'.repeat(DataTransform.MAX_PATTERN), ''),
                digits('###', 'US'),
                digits('###', '1234')
            };
            for (DataTransform.Step step : bad) {
                System.assertEquals(
                    Label.Core_Transform_ErrorDigits,
                    DataTransform.problemWith(step),
                    JSON.serialize(step)
                );
            }
            System.assertEquals(
                1,
                DataTransform.problems(bad).size(),
                'One sentence however many steps share it.'
            );
        }
    }

    @IsTest
    static void aBadStepIsSkippedWhenApplied() {
        System.runAs(TestUsers.admin()) {
            System.assertEquals(
                '5551234567',
                DataTransform.apply(
                    new List<DataTransform.Step>{ digits('no places', '') },
                    '5551234567',
                    null
                ),
                'A step that fails the check changes nothing.'
            );
        }
    }

    @IsTest
    static void aStoredStepReadsBack() {
        System.runAs(TestUsers.admin()) {
            List<DataTransform.Step> steps = DataTransform.parse(
                '[{"op":"trim"},{"op":"digits","pattern":"(###) ###-####","country":"1"}]'
            );
            System.assertEquals(2, steps.size());
            System.assertEquals(
                '(555) 123-4567',
                DataTransform.apply(steps, ' 1-555-123-4567 ', null)
            );
            System.assertEquals(3, DataTransform.DOCUMENT_VERSION, 'Digits is a version 3 step.');
        }
    }
}
