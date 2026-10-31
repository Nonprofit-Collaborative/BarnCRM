/**
 * The transform engine (R-IT15): every operation does what the admin guide says, a broken
 * step is refused on save and skipped on read, nothing is read as a pattern, and a large
 * file's worth of values changes inside one transaction.
 */
@IsTest(testFor='ApexClass:DataTransform')
private class DataTransformTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static DataTransform.Step step(String op) {
        return new DataTransform.Step(op);
    }

    private static DataTransform.Step replaceStep(
        String text,
        String replaceWith,
        Boolean matchCase,
        Boolean wholeValue
    ) {
        DataTransform.Step result = step(DataTransform.OP_REPLACE);
        result.text = text;
        result.replaceWith = replaceWith;
        result.matchCase = matchCase;
        result.wholeValue = wholeValue;
        return result;
    }

    private static DataTransform.Step dateStep(String dateOrder) {
        DataTransform.Step result = step(DataTransform.OP_DATE);
        result.dateOrder = dateOrder;
        return result;
    }

    private static String one(DataTransform.Step only, String value) {
        return DataTransform.apply(new List<DataTransform.Step>{ only }, value, null);
    }

    @IsTest
    static void trimsAndCollapsesSpaces() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('Ana Ramirez', one(step('trim'), '  Ana \t  Ramirez '));
            Assert.isNull(one(step('trim'), null), 'Nothing stays nothing.');
        }
    }

    @IsTest
    static void changesCapitals() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('CA', one(step('upper'), 'ca'));
            Assert.areEqual('ana@example.org', one(step('lower'), 'ANA@Example.ORG'));
            Assert.areEqual('Ramirez-Lopez', one(step('proper'), 'RAMIREZ-LOPEZ'));
            Assert.areEqual('Mary Ann 2nd', one(step('proper'), 'mary ANN 2nd'));
            Assert.areEqual(
                'O\'neil',
                one(step('proper'), 'o\'NEIL'),
                'An apostrophe is in the word.'
            );
            Assert.areEqual(
                'Élodie',
                one(step('proper'), 'éLODIE'),
                'Letters beyond A to Z count.'
            );
        }
    }

    /**
     * Capitalize each word over long texts of 32,000 characters: the words are found by the
     * pattern engine, not character by character. Twenty texts here, a tenth of a chunk: under
     * 4 seconds for them is under 40 of a chunk's 60 asynchronous seconds. The message records
     * the time, for the org run.
     */
    @IsTest
    static void capitalizesLongTextsWithinAChunksTime() {
        System.runAs(TestUsers.admin()) {
            String longText = 'the QUICK brown fox. '.repeat(1524).left(32000);
            Integer cpuBefore = Limits.getCpuTime();
            String last;
            for (Integer index = 0; index < 20; index++) {
                last = one(step('proper'), longText);
            }
            Integer used = Limits.getCpuTime() - cpuBefore;
            Assert.isTrue(last.startsWith('The Quick Brown Fox. The Quick'), last.left(40));
            Assert.areEqual(32000, last.length(), 'Nothing lost or added.');
            Assert.isTrue(used < 4000, 'CPU ms for 20 long texts: ' + used);
        }
    }

    @IsTest
    static void findsAndReplacesLiteralText() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                '12 Main Street',
                one(replaceStep('St.', 'Street', false, false), '12 Main st.')
            );
            Assert.areEqual(
                '12 Main st.',
                one(replaceStep('St.', 'Street', true, false), '12 Main st.'),
                'Match capitals tells st. from St.'
            );
            Assert.areEqual(
                'aXc abc',
                one(replaceStep('a.c', 'aXc', false, false), 'a.c abc'),
                'A dot is a dot, not any character.'
            );
            Assert.areEqual(
                'cost $1',
                one(replaceStep('price', '$1', false, false), 'cost price'),
                'A replacement is literal too.'
            );
            Assert.areEqual('Main ', one(replaceStep('Street', null, false, false), 'Main Street'));
        }
    }

    @IsTest
    static void replacesOnlyAWholeValueWhenAsked() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step whole = replaceStep('CA', 'California', false, true);
            Assert.areEqual('California', one(whole, 'ca'));
            Assert.areEqual(
                'CAL',
                one(whole, 'CAL'),
                'A value that only contains the text is kept.'
            );
            Assert.areEqual('ca', one(replaceStep('CA', 'California', true, true), 'ca'));
        }
    }

    @IsTest
    static void fillsABlank() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step fill = step('ifBlank');
            fill.value = 'Unknown';
            Assert.areEqual('Unknown', one(fill, '  '));
            Assert.areEqual('Unknown', one(fill, null));
            Assert.areEqual('Known', one(fill, 'Known'));
        }
    }

    @IsTest
    static void appendsOtherColumnsLeavingBlanksOut() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step add = step('append');
            add.columns = new List<String>{ 'Middle', ' LAST ' };
            Map<String, String> row = new Map<String, String>{
                'middle' => 'M',
                'last' => 'Ramirez'
            };
            Assert.areEqual(
                'Ana M Ramirez',
                DataTransform.apply(new List<DataTransform.Step>{ add }, 'Ana', row)
            );
            row.put('middle', '');
            Assert.areEqual(
                'Ana Ramirez',
                DataTransform.apply(new List<DataTransform.Step>{ add }, 'Ana', row)
            );
            add.separator = ', ';
            Assert.areEqual(
                'Ramirez',
                DataTransform.apply(new List<DataTransform.Step>{ add }, null, row)
            );
            Assert.isNull(
                DataTransform.apply(
                    new List<DataTransform.Step>{ add },
                    null,
                    new Map<String, String>()
                ),
                'Nothing to add leaves the value as it was.'
            );
        }
    }

    @IsTest
    static void readsDatesInTheChosenOrder() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('2025-12-31', one(dateStep('DMY'), '31/12/2025'));
            Assert.areEqual('2025-12-31', one(dateStep('MDY'), '12-31-2025 10:30'));
            Assert.areEqual('2025-01-05', one(dateStep('YMD'), '2025.1.5'));
            Assert.areEqual('2024-02-29', one(dateStep('MDY'), '2/29/24'), 'A leap day is a day.');
            Assert.areEqual(
                '1987-03-04',
                one(dateStep('MDY'), '3/4/87'),
                'A year of 50 or more is 19xx.'
            );
        }
    }

    @IsTest
    static void leavesAnUnreadableDateAsItWas() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('2/29/2025', one(dateStep('MDY'), '2/29/2025'), 'Not a leap year.');
            Assert.areEqual('31/12/2025', one(dateStep('MDY'), '31/12/2025'), 'No 31st month.');
            Assert.areEqual(
                'Dec 31 2025',
                one(dateStep('MDY'), 'Dec 31 2025'),
                'Only two numbers.'
            );
            Assert.areEqual('1/2/123', one(dateStep('MDY'), '1/2/123'), 'A three-digit year.');
            Assert.areEqual('', one(dateStep('MDY'), ''));
        }
    }

    @IsTest
    static void runsStepsInOrder() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step fill = step('ifBlank');
            fill.value = 'none given';
            List<DataTransform.Step> steps = new List<DataTransform.Step>{
                step('trim'),
                fill,
                step('proper')
            };
            Assert.areEqual('None Given', DataTransform.apply(steps, '   ', null));
            Assert.areEqual('Ana Ramirez', DataTransform.apply(steps, ' ANA   RAMIREZ', null));
        }
    }

    @IsTest
    static void namesWhatIsWrongWithASave() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step noText = replaceStep('', 'x', false, false);
            DataTransform.Step noValue = step('ifBlank');
            DataTransform.Step noColumns = step('append');
            DataTransform.Step badOrder = dateStep('MYD');
            DataTransform.Step tooLong = replaceStep('a'.repeat(256), 'b', false, false);
            DataTransform.Step longSeparator = step('append');
            longSeparator.columns = new List<String>{ 'Last' };
            longSeparator.separator = '-'.repeat(11);
            List<String> found = DataTransform.problems(
                new List<DataTransform.Step>{
                    step('evaluate'),
                    noText,
                    noValue,
                    noColumns,
                    badOrder,
                    tooLong,
                    longSeparator,
                    null
                }
            );
            Assert.isTrue(
                found.contains(
                    String.format(Label.Core_Transform_ErrorUnknown, new List<String>{ 'evaluate' })
                )
            );
            Assert.isTrue(found.contains(Label.Core_Transform_ErrorNeedsText));
            Assert.isTrue(found.contains(Label.Core_Transform_ErrorNeedsValue));
            Assert.isTrue(found.contains(Label.Core_Transform_ErrorDateOrder));
            Assert.isTrue(found.contains(Label.Core_Transform_ErrorTooLong));
            Assert.isTrue(
                found.contains(
                    String.format(Label.Core_Transform_ErrorNeedsColumns, new List<String>{ '5' })
                )
            );
            Assert.isTrue(
                DataTransform.problems(new List<DataTransform.Step>{ step('trim') }).isEmpty()
            );
            Assert.isTrue(DataTransform.problems(null).isEmpty());
        }
    }

    @IsTest
    static void refusesMoreThanTenSteps() {
        System.runAs(TestUsers.admin()) {
            List<DataTransform.Step> steps = new List<DataTransform.Step>();
            for (Integer i = 0; i < 11; i++) {
                steps.add(step('upper'));
            }
            Assert.isTrue(
                DataTransform.problems(steps)
                    .contains(
                        String.format(Label.Core_Transform_ErrorTooMany, new List<String>{ '10' })
                    )
            );
            steps.add(step('lower'));
            Assert.areEqual(
                'ABC',
                DataTransform.apply(steps, 'abc', null),
                'Steps past the tenth are not run.'
            );
        }
    }

    @IsTest
    static void skipsABrokenStepOnRead() {
        System.runAs(TestUsers.admin()) {
            List<DataTransform.Step> steps = DataTransform.parse(
                '[{"op":"evaluate","text":"1+1"},{"op":"replace"},{"op":"upper"}]'
            );
            Assert.areEqual(3, steps.size());
            Assert.areEqual('ABC', DataTransform.apply(steps, 'abc', null));
            Assert.isTrue(
                DataTransform.parse('not json').isEmpty(),
                'Unreadable reads as no steps.'
            );
            Assert.isTrue(DataTransform.parse(null).isEmpty());
            Assert.areEqual('abc', DataTransform.apply(null, 'abc', null));
        }
    }

    @IsTest
    static void readsTheStoredDocument() {
        System.runAs(TestUsers.admin()) {
            List<DataTransform.Step> steps = DataTransform.parse(
                '[{"op":"replace","text":"St.","replaceWith":"Street","matchCase":false,"wholeValue":false},' +
                '{"op":"append","columns":["City"],"separator":", "},{"op":"date","dateOrder":"DMY"}]'
            );
            Assert.areEqual('Street', steps[0].replaceWith);
            Assert.areEqual(', ', steps[1].separator);
            Assert.areEqual('DMY', steps[2].dateOrder);
            Assert.isTrue(DataTransform.problems(steps).isEmpty());
        }
    }

    private static DataTransform.Step mapStep(String otherwise, Boolean matchCase) {
        DataTransform.Step result = step(DataTransform.OP_MAP);
        result.pairs = new List<DataTransform.Pair>{
            new DataTransform.Pair('CA', 'California'),
            new DataTransform.Pair('NY', 'New York'),
            new DataTransform.Pair('ca', 'Small ca')
        };
        result.otherwise = otherwise;
        result.matchCase = matchCase;
        return result;
    }

    private static DataTransform.Step ifThenStep(String test, String text, String value) {
        DataTransform.Step result = step(DataTransform.OP_IF_THEN);
        result.test = test;
        result.text = text;
        result.value = value;
        return result;
    }

    private static DataTransform.Step partStep(
        String separator,
        Integer position,
        Boolean fromEnd
    ) {
        DataTransform.Step result = step(DataTransform.OP_PART);
        result.separator = separator;
        result.position = position;
        result.fromEnd = fromEnd;
        return result;
    }

    private static DataTransform.Step shiftStep(Integer amount, String unit) {
        DataTransform.Step result = step(DataTransform.OP_SHIFT_DATE);
        result.amount = amount;
        result.unit = unit;
        return result;
    }

    @IsTest
    static void mapsValuesFromATable() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'California',
                one(mapStep(null, false), ' ca '),
                'Trimmed, any capitals.'
            );
            Assert.areEqual('New York', one(mapStep(null, false), 'NY'));
            Assert.areEqual('TX', one(mapStep(null, false), 'TX'), 'Not listed is kept.');
            Assert.areEqual(
                'Other',
                one(mapStep('Other', false), 'TX'),
                'Or becomes anything else.'
            );
            Assert.areEqual('', one(mapStep('Other', false), ''), 'An empty value stays empty.');
            Assert.areEqual(
                'Small ca',
                one(mapStep(null, true), 'ca'),
                'Match capitals tells ca from CA.'
            );
        }
    }

    @IsTest
    static void writesAValueWhenATestHolds() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('', one(ifThenStep('equals', 'N/A', ''), ' n/a '), 'Equals clears.');
            Assert.areEqual('Ana', one(ifThenStep('equals', 'N/A', ''), 'Ana'), 'Else kept.');
            Assert.areEqual('Test', one(ifThenStep('contains', 'test', 'Test'), 'a TEST row'));
            Assert.areEqual('Unknown', one(ifThenStep('blank', null, 'Unknown'), '  '));
            DataTransform.Step otherwise = ifThenStep('contains', '@', 'Has email');
            otherwise.otherwise = 'No email';
            Assert.areEqual('No email', one(otherwise, 'Ana'), 'Otherwise when it fails.');
            Assert.areEqual('Has email', one(otherwise, 'ana@example.org'));
        }
    }

    @IsTest
    static void keepsOnePart() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('example.org', one(partStep('@', 2, false), 'ana@example.org'));
            Assert.areEqual('Ramirez', one(partStep(' ', 1, true), 'Ana M Ramirez'));
            Assert.areEqual('John', one(partStep(',', 2, false), 'Smith, John'), 'Trimmed.');
            Assert.areEqual('', one(partStep('@', 3, false), 'ana@example.org'), 'No part 3.');
            Assert.areEqual('a.b', one(partStep('.*', 1, false), 'a.b.*c'), 'Literal separator.');
        }
    }

    @IsTest
    static void keepsFirstOrLastCharacters() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step first = step(DataTransform.OP_FIRST);
            first.count = 5;
            DataTransform.Step last = step(DataTransform.OP_LAST);
            last.count = 4;
            Assert.areEqual('97201', one(first, '97201-1234'));
            Assert.areEqual('1234', one(last, '97201-1234'));
            Assert.areEqual('972', one(first, '972'), 'A shorter value is kept whole.');
            Assert.isNull(one(first, null));
        }
    }

    @IsTest
    static void shiftsADateAndWritesToday() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('2025-02-28', one(shiftStep(1, 'months'), '2025-01-31'));
            Assert.areEqual('2025-12-01', one(shiftStep(-30, 'days'), '2025-12-31'));
            Assert.areEqual(
                '2026-01-05',
                one(shiftStep(4, 'days'), '2026-01-01 00:00:00'),
                'A stored date with a time reads.'
            );
            Assert.areEqual('soon', one(shiftStep(4, 'days'), 'soon'), 'Not a date is kept.');
            Assert.areEqual(
                '3999-12-31',
                one(shiftStep(1200, 'months'), '3999-12-31'),
                'Past 4000 is kept.'
            );
            String today = String.valueOf(Date.today()).left(10);
            DataTransform.Step always = step(DataTransform.OP_TODAY);
            Assert.areEqual(today, one(always, 'Ana'));
            DataTransform.Step whenBlank = step(DataTransform.OP_TODAY);
            whenBlank.whenBlank = true;
            Assert.areEqual('2020-01-01', one(whenBlank, '2020-01-01'), 'Only when empty.');
            Assert.areEqual(today, one(whenBlank, ''));
        }
    }

    @IsTest
    static void namesWhatIsWrongWithTheNewerSteps() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step emptyMap = step(DataTransform.OP_MAP);
            DataTransform.Step noTest = ifThenStep(null, 'x', 'y');
            DataTransform.Step noText = ifThenStep('equals', '', 'y');
            DataTransform.Step noSeparator = partStep('', 1, false);
            DataTransform.Step partZero = partStep('@', 0, false);
            DataTransform.Step noCount = step(DataTransform.OP_FIRST);
            DataTransform.Step tooFar = shiftStep(5000, 'months');
            DataTransform.Step noUnit = shiftStep(1, 'weeks');
            for (
                DataTransform.Step broken : new List<DataTransform.Step>{
                    emptyMap,
                    noTest,
                    noText,
                    noSeparator,
                    partZero,
                    noCount,
                    tooFar,
                    noUnit
                }
            ) {
                Assert.isNotNull(DataTransform.problemWith(broken), 'Refused: ' + broken.op);
                Assert.areEqual('kept', one(broken, 'kept'), 'Skipped on read: ' + broken.op);
            }
            Assert.isNull(DataTransform.problemWith(ifThenStep('blank', null, 'x')));
            Assert.isNull(DataTransform.problemWith(step(DataTransform.OP_TODAY)));
            Assert.areEqual(3, DataTransform.DOCUMENT_VERSION, 'The step document is version 3.');
        }
    }

    @IsTest
    static void readsTheNewerStepsFromTheStoredDocument() {
        System.runAs(TestUsers.admin()) {
            List<DataTransform.Step> steps = DataTransform.parse(
                '[{"op":"map","pairs":[{"text":"M","value":"Monthly"}],"otherwise":"Once"},' +
                '{"op":"shiftDate","amount":-1,"unit":"days"},{"op":"futureOp"}]'
            );
            Assert.areEqual('Monthly', steps[0].pairs[0].value);
            Assert.areEqual(-1, steps[1].amount);
            Assert.areEqual(
                'Monthly',
                DataTransform.apply(new List<DataTransform.Step>{ steps[0], steps[2] }, 'm', null),
                'An operation this version does not know is skipped.'
            );
        }
    }

    @IsTest
    static void changesTwoHundredRowsOfValues() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step add = step('append');
            add.columns = new List<String>{ 'Last' };
            DataTransform.Step fix = replaceStep('st.', 'Street', false, false);
            List<DataTransform.Step> steps = new List<DataTransform.Step>{
                step('trim'),
                step('proper'),
                fix,
                add
            };
            List<String> results = new List<String>();
            Test.startTest();
            for (Integer i = 0; i < 200; i++) {
                Map<String, String> row = new Map<String, String>{ 'last' => 'Row' + i };
                results.add(DataTransform.apply(steps, '  ANA   main st. ', row));
            }
            Test.stopTest();
            Assert.areEqual(200, results.size());
            Assert.areEqual('Ana Main Street Row0', results[0]);
            Assert.areEqual('Ana Main Street Row199', results[199]);
        }
    }
}
