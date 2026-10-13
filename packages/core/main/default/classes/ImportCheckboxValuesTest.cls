/**
 * How an import reads a checkbox column (canonical model R-IT11): the spellings read as ticked
 * and cleared, a blank cell that changes nothing, and a value that is neither, which is never
 * read as cleared but skipped on its row and named in the run log while the rest of the row
 * loads.
 */
@IsTest
private class ImportCheckboxValuesTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    /** The generic contact list plus the two opt-out checkboxes. */
    private static void given(List<Map<String, String>> values) {
        TestDataFactory.defaultSettings();
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(
            new ImportMapping.Column('Email Opt Out', 'Contact1.HasOptedOutOfEmail')
        );
        mapping.columns.add(new ImportMapping.Column('Do Not Call', 'Contact1.DoNotCall'));
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static Map<String, String> row(String email, String optOut, String doNotCall) {
        Map<String, String> result = ImportTestDataFactory.donorRow('Ana', 'Ramirez', email, null);
        result.put('Email Opt Out', optOut);
        result.put('Do Not Call', doNotCall);
        return result;
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    private static Contact contactBy(String email) {
        return [
            SELECT Id, HasOptedOutOfEmail, DoNotCall, MailingCity
            FROM Contact
            WHERE Email = :email
            LIMIT 1
        ];
    }

    private static Integer notesNaming(ImportRowProcessor.Outcome outcome, String value) {
        Integer count = 0;
        for (String note : outcome.notes) {
            if (note.contains('"' + value + '"')) {
                count++;
            }
        }
        return count;
    }

    @IsTest
    static void readsEveryAcceptedSpellingIgnoringCaseAndSpaces() {
        System.runAs(TestUsers.admin()) {
            List<String> ticked = new List<String>{
                'true',
                'yes',
                'y',
                '1',
                'x',
                'checked',
                'on',
                't'
            };
            List<String> cleared = new List<String>{ 'false', 'no', 'n', '0', 'off', 'f' };

            Test.startTest();
            for (String spelling : ticked) {
                Assert.areEqual(true, ImportObjectSchema.checkbox(spelling), spelling);
                Assert.areEqual(
                    true,
                    ImportObjectSchema.checkbox('  ' + spelling.toUpperCase() + ' '),
                    spelling + ' in capitals with spaces'
                );
            }
            for (String spelling : cleared) {
                Assert.areEqual(false, ImportObjectSchema.checkbox(spelling), spelling);
                Assert.areEqual(
                    false,
                    ImportObjectSchema.checkbox(' ' + spelling.toUpperCase()),
                    spelling + ' in capitals with a space'
                );
            }
            Boolean blank = ImportObjectSchema.checkbox('   ');
            Boolean missing = ImportObjectSchema.checkbox(null);
            Boolean maybe = ImportObjectSchema.checkbox('maybe');
            Boolean withFullStop = ImportObjectSchema.checkbox('Yes.');
            Test.stopTest();

            Assert.isNull(blank, 'A blank value is neither.');
            Assert.isNull(missing, 'Nor is a missing one.');
            Assert.isNull(maybe, 'An unknown word is never read as cleared.');
            Assert.isNull(withFullStop, 'Nor is a near miss.');
        }
    }

    /** Each accepted spelling saves as ticked or cleared on a new person. */
    @IsTest
    static void aNewPersonTakesEachSpelling() {
        System.runAs(TestUsers.admin()) {
            given(
                new List<Map<String, String>>{
                    row('one@example.org', 'X', 'off'),
                    row('two@example.org', 'Checked', 'F'),
                    row('three@example.org', 'on', 'N'),
                    row('four@example.org', 'T', 'no')
                }
            );

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(4, outcome.created, 'Every row loaded.');
            Assert.isTrue(outcome.notes.isEmpty(), 'Nothing to report: ' + outcome.notes);
            for (
                String email : new List<String>{
                    'one@example.org',
                    'two@example.org',
                    'three@example.org',
                    'four@example.org'
                }
            ) {
                Contact saved = contactBy(email);
                Assert.isTrue(saved.HasOptedOutOfEmail, email + ' is opted out.');
                Assert.isFalse(saved.DoNotCall, email + ' may be called.');
            }
        }
    }

    /**
     * An unknown value leaves the stored checkbox as it was, in the preview and the commit, and
     * is named with its row and column; the other columns of the row still load. A blank cell
     * changes nothing either, and is not reported.
     */
    @IsTest
    static void anUnreadableValueSkipsThatFieldAndTheRestOfTheRowLoads() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            insert new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org',
                MailingCity = 'Salem',
                HasOptedOutOfEmail = true,
                DoNotCall = true
            );
            given(new List<Map<String, String>>{ row('ana@example.org', 'maybe', '') });

            Test.startTest();
            ImportRowProcessor.Outcome preview = run(true);
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(1, preview.updated, 'The preview still updates her city.');
            Assert.areEqual(1, notesNaming(preview, 'maybe'), 'And names the value.');
            Assert.areEqual(1, outcome.updated, 'The commit updated her.');
            Assert.areEqual(0, outcome.rejected, 'The row was not rejected.');
            Contact saved = contactBy('ana@example.org');
            Assert.areEqual('Portland', saved.MailingCity, 'The rest of the row loaded.');
            Assert.isTrue(saved.HasOptedOutOfEmail, 'An unknown value never clears the box.');
            Assert.isTrue(saved.DoNotCall, 'Nor does a blank cell.');
            Assert.areEqual(1, outcome.notes.size(), 'One note: ' + outcome.notes);
            String note = new List<String>(outcome.notes)[0];
            Assert.isTrue(note.startsWith('Row 2:'), 'The note names the row: ' + note);
            Assert.isTrue(note.contains('Email Opt Out'), 'And the column: ' + note);
            Assert.isTrue(note.contains('"maybe"'), 'And the value: ' + note);
            for (Import_Journal__c entry : [SELECT Entries_JSON__c FROM Import_Journal__c]) {
                Assert.isFalse(
                    String.valueOf(entry.Entries_JSON__c).contains('HasOptedOutOfEmail'),
                    'The skipped checkbox is not journaled as a change.'
                );
            }
        }
    }

    /** Two hundred rows in one chunk: unknown values are skipped row by row, in bulk. */
    @IsTest
    static void skipsUnknownValuesAcrossAFullChunk() {
        System.runAs(TestUsers.admin()) {
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                Boolean even = Math.mod(i, 2) == 0;
                Map<String, String> person = row(
                    'person' + i + '@example.org',
                    even ? 'Y' : 'nope' + i,
                    even ? 'unsure' + i : 'yes'
                );
                person.put('Last Name', 'Surname' + i);
                values.add(person);
            }
            given(values);

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(200, outcome.created, 'Every row loaded.');
            Assert.areEqual(0, outcome.rejected, 'None was rejected for a checkbox.');
            Assert.areEqual(
                100,
                [SELECT COUNT() FROM Contact WHERE HasOptedOutOfEmail = TRUE],
                'Only the rows that said Y are opted out.'
            );
            Assert.areEqual(
                100,
                [SELECT COUNT() FROM Contact WHERE DoNotCall = TRUE],
                'Only the rows that said yes are not to be called.'
            );
            Assert.areEqual(200, outcome.notes.size(), 'One note per unknown value.');
            Assert.areEqual(1, notesNaming(outcome, 'nope1'), 'Each names its own value.');
            Assert.areEqual(1, notesNaming(outcome, 'unsure198'), 'Up to the last row.');
        }
    }
}
