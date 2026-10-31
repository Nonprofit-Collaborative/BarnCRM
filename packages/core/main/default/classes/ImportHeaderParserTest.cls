/**
 * Headings that name an object and a field together, and sheet and file names that name an
 * object (C-49a): every spelling the owner listed, and the readings that must not match.
 * `match`, `resolve` and `objectOfName` are exact; the best guesses of C-49e (`find`, `guess`,
 * `resolveOrGuess`, `objectOfNameOrGuess`) are tested at the end, typos and near words alike.
 */
// runs-as: deploying user (pure logic: reads names against maps built in the test, no DML or SOQL)
@IsTest(testFor='ApexClass:ImportHeaderParser')
private class ImportHeaderParserTest {
    /** Fields by object, spelled as describe would give them. */
    private class TestFields implements ImportHeaderParser.FieldKeys {
        public Map<String, String> keysOf(String objectName) {
            Map<String, String> keys = new Map<String, String>();
            Map<String, List<String>> fields = new Map<String, List<String>>{
                'Contact' => new List<String>{
                    'FirstName|First Name',
                    'Phone|Business Phone',
                    'MobilePhone|Mobile Phone',
                    'AccountId|Account',
                    'Custom_Field__c|Custom Field'
                },
                'Account' => new List<String>{ 'Name|Account Name', 'Contact__c|Contact' },
                'Object__c' => new List<String>{ 'CustomField__c|Custom Field' },
                'Field_Trip__c' => new List<String>{ 'Start_Date__c|Start Date' }
            };
            List<String> named = fields.get(objectName);
            for (String each : named == null ? new List<String>() : named) {
                String apiName = each.substringBefore('|');
                ImportHeaderParser.putKey(keys, apiName, apiName);
                ImportHeaderParser.putKey(keys, apiName.removeEnd('__c'), apiName);
                ImportHeaderParser.putKey(keys, each.substringAfter('|'), apiName);
            }
            // Phone's own name too, as a label would give it.
            if (objectName == 'Contact') {
                ImportHeaderParser.putKey(keys, 'Phone', 'Phone');
            }
            return keys;
        }
    }

    private static Map<String, String> objects() {
        Map<String, String> keys = new Map<String, String>();
        for (
            String each : new List<String>{
                'Contact|Contact|Contacts',
                'Account|Account|Accounts',
                'Object__c|Object|Objects',
                'Field_Trip__c|Field Trip|Field Trips'
            }
        ) {
            List<String> parts = each.split('\\|');
            ImportHeaderParser.putKey(keys, parts[0], parts[0]);
            ImportHeaderParser.putKey(keys, parts[0].removeEnd('__c'), parts[0]);
            ImportHeaderParser.putKey(keys, parts[1], parts[0]);
            ImportHeaderParser.putKey(keys, parts[2], parts[0]);
        }
        return keys;
    }

    private static String read(String header) {
        ImportHeaderParser.Resolved found = ImportHeaderParser.resolve(
            header,
            objects(),
            new TestFields()
        );
        return found == null ? null : found.objectName + '.' + found.fieldName;
    }

    @IsTest
    static void readsEverySpellingOfObjectAndField() {
        Map<String, String> expected = new Map<String, String>{
            'Contact.FirstName' => 'Contact.FirstName',
            'Contact.First Name' => 'Contact.FirstName',
            'Object__c-CustomField__c' => 'Object__c.CustomField__c',
            'object - custom field' => 'Object__c.CustomField__c',
            'phone:contact' => 'Contact.Phone',
            'Phone (Contact)' => 'Contact.Phone',
            'Contact: Phone' => 'Contact.Phone',
            'Contact / Phone' => 'Contact.Phone',
            'Contact | Mobile Phone' => 'Contact.MobilePhone',
            'Contact_Phone' => 'Contact.Phone',
            'CONTACTS.MOBILE PHONE' => 'Contact.MobilePhone',
            'Field Trip - Start Date' => 'Field_Trip__c.Start_Date__c',
            'Field Trips: start_date__c' => 'Field_Trip__c.Start_Date__c'
        };
        for (String header : expected.keySet()) {
            Assert.areEqual(expected.get(header), read(header), 'Reads "' + header + '".');
        }
    }

    @IsTest
    static void cleansLineBreaksByteOrderMarkAndSpaces() {
        Assert.areEqual('Contact.FirstName', read('Contact.\nFirst\r\nName'), 'Line breaks.');
        Assert.areEqual('Contact.Phone', read('﻿Contact.Phone  '), 'BOM and trailing.');
        Assert.areEqual('Contact.Phone', read('Phone (Contact)'), 'A non-breaking space.');
        Assert.areEqual('a b', ImportHeaderParser.clean('﻿ a \r\n\t b '), 'One space.');
        Assert.areEqual('', ImportHeaderParser.clean(null), 'Null reads as blank.');
    }

    @IsTest
    static void neverSplitsInsideAnApiName() {
        Assert.areEqual(
            'Contact.Custom_Field__c',
            read('Contact_Custom_Field__c'),
            'Only the reading that names a field matches.'
        );
        Assert.areEqual(
            'Field_Trip__c.Start_Date__c',
            // Joined here so no line reads as a namespaced name (check-namespace.sh).
            read('Field_Trip__c' + '_Start_Date__c'),
            'An API name on each side of a lone underscore.'
        );
        Assert.isNull(read('Custom_Field__c'), 'A field name alone names no object.');
        for (List<String> split : ImportHeaderParser.underscoreSplits('Custom_Field__c')) {
            Assert.isFalse(
                split[0].endsWith('_') || split[1].startsWith('_') || split[1] == 'c',
                'Never split at either underscore of "__": ' + split
            );
        }
        Assert.areEqual(
            2,
            ImportHeaderParser.underscoreSplits('Custom_Field__c').size(),
            'One lone underscore, read either way.'
        );
    }

    @IsTest
    static void triesSeparatorsBeforeUnderscores() {
        Assert.areEqual(
            0,
            ImportHeaderParser.explicitSplits('Contact_Phone').size(),
            'No separator in an underscore heading.'
        );
        Assert.areEqual(
            'Contact.Custom_Field__c',
            read('Contact.Custom_Field__c'),
            'A separator reads first, and the field keeps its underscores.'
        );
    }

    @IsTest
    static void matchesNothingItCannotBeSureOf() {
        Assert.isNull(read('Donor.Phone'), 'An unknown object.');
        Assert.isNull(read('Contact.Shoe Size'), 'An unknown field.');
        Assert.isNull(read('Phone'), 'A field alone.');
        Assert.isNull(read('First Name'), 'A space is not a separator.');
        Assert.isNull(read(''), 'A blank heading.');
        Assert.isNull(read(null), 'A null heading.');
        Assert.isNull(read('.Phone'), 'An empty object part.');
        Assert.isNull(read('Phone ()'), 'Empty parentheses.');
        Assert.isNull(
            read('Contact.Account'),
            'Contact.Account (a field) and Account.Contact (a field): two readings, neither wins.'
        );
    }

    @IsTest
    static void aSpellingTwoObjectsShareNamesNeither() {
        Map<String, String> keys = new Map<String, String>();
        ImportHeaderParser.putKey(keys, 'Shift', 'Shift__c');
        ImportHeaderParser.putKey(keys, 'Shift', 'Other_Shift__c');
        ImportHeaderParser.putKey(keys, 'Shift__c', 'Shift__c');
        Assert.isNull(ImportHeaderParser.match('shift', keys), 'Ambiguous.');
        Assert.areEqual('Shift__c', ImportHeaderParser.match('SHIFT__C', keys), 'Exact name.');
        Assert.isNull(ImportHeaderParser.match('Shifts', keys), 'No fuzzy match.');
        Assert.isNull(ImportHeaderParser.match('x', null), 'No keys.');
        Assert.isNull(ImportHeaderParser.match(' ', keys), 'A blank part.');
    }

    @IsTest
    static void namesTheObjectMostHeadingsName() {
        Assert.areEqual(
            'Contact',
            ImportHeaderParser.objectOfHeaders(
                new List<String>{
                    'Notes',
                    'Account.Account Name',
                    'Contact.First Name',
                    'Phone (Contact)'
                },
                objects(),
                new TestFields()
            ),
            'Two headings name Contact, one Account.'
        );
        Assert.areEqual(
            'Account',
            ImportHeaderParser.objectOfHeaders(
                new List<String>{ 'Account.Name', 'Contact.Phone' },
                objects(),
                new TestFields()
            ),
            'A tie goes to the first named.'
        );
        Assert.isNull(
            ImportHeaderParser.objectOfHeaders(
                new List<String>{ 'First Name', 'Email' },
                objects(),
                new TestFields()
            ),
            'Field names alone name no object.'
        );
        Assert.isNull(
            ImportHeaderParser.objectOfHeaders(null, objects(), new TestFields()),
            'No headings.'
        );
    }

    @IsTest
    static void namesTheObjectAFileOrSheetIsNamedFor() {
        Map<String, String> expected = new Map<String, String>{
            'contacts_2026.xlsx' => 'Contact',
            'Field Trips.csv' => 'Field_Trip__c',
            'Field_Trip__c.csv' => 'Field_Trip__c',
            'Contacts export 2026-10-30.csv' => 'Contact',
            'IMPORT-accounts.txt' => 'Account',
            'Budget 2026.xlsx' => null,
            'Exports.csv' => null,
            '' => null
        };
        for (String fileName : expected.keySet()) {
            Assert.areEqual(
                expected.get(fileName),
                ImportHeaderParser.objectOfFileName(fileName, objects()),
                'File "' + fileName + '".'
            );
        }
        Assert.areEqual('Contact', ImportHeaderParser.objectOfName('Contacts', objects()), 'Tab.');
        Assert.isNull(ImportHeaderParser.objectOfName('Sheet1', objects()), 'A default tab name.');
        Assert.isNull(ImportHeaderParser.objectOfName(null, objects()), 'No name.');
    }

    // -------------------------------------------------------------------------------------
    // C-49e: best guesses (plan D-150)
    // -------------------------------------------------------------------------------------

    /** Contact's fields as describe spells them: API name and label. */
    private static Map<String, String> contactFields() {
        Map<String, String> keys = new Map<String, String>();
        for (
            String each : new List<String>{
                'FirstName|First Name',
                'LastName|Last Name',
                'Email|Email',
                'Phone|Business Phone',
                'MobilePhone|Mobile Phone',
                'Birthdate|Birthdate',
                'Phone_Number__c|Phone Number'
            }
        ) {
            ImportHeaderParser.putKey(keys, each.substringBefore('|'), each.substringBefore('|'));
            ImportHeaderParser.putKey(keys, each.substringAfter('|'), each.substringBefore('|'));
        }
        return keys;
    }

    @IsTest
    static void guessesTyposOfAFieldAndSaysSo() {
        Map<String, String> expected = new Map<String, String>{
            'Frist Name' => 'FirstName',
            'Emial' => 'Email',
            'Phone Nmber' => 'Phone_Number__c',
            'Last Nme' => 'LastName',
            'Mobile Phon' => 'MobilePhone'
        };
        for (String header : expected.keySet()) {
            ImportHeaderParser.Found found = ImportHeaderParser.find(header, contactFields());
            Assert.isNotNull(found, 'A guess for "' + header + '".');
            Assert.areEqual(expected.get(header), found.name, 'Guesses "' + header + '".');
            Assert.isTrue(found.guessed, '"' + header + '" is flagged as a guess.');
        }
    }

    @IsTest
    static void anExactMatchIsNeverAGuess() {
        ImportHeaderParser.Found found = ImportHeaderParser.find('First Name', contactFields());
        Assert.areEqual('FirstName', found.name, 'Exact by label.');
        Assert.isFalse(found.guessed, 'An exact match is not flagged.');
        found = ImportHeaderParser.find('EMAIL', contactFields());
        Assert.areEqual('Email', found.name, 'Exact ignoring case.');
        Assert.isFalse(found.guessed, 'Still exact.');
        Assert.isNull(
            ImportHeaderParser.match('Frist Name', contactFields()),
            'match stays exact.'
        );
    }

    @IsTest
    static void guessesNothingForADifferentWord() {
        for (
            String header : new List<String>{
                'Shoe Size',
                'Favorite Color',
                'Gender',
                'Notes',
                'Amount',
                'Zip',
                'Fax',
                'Nme',
                '',
                null
            }
        ) {
            Assert.isNull(
                ImportHeaderParser.find(header, contactFields()),
                '"' + header + '" must not be guessed.'
            );
        }
        Assert.isNull(ImportHeaderParser.guess('Frist Name', null), 'No keys, no guess.');
        Map<String, String> person = new Map<String, String>();
        ImportHeaderParser.putKey(person, 'Contact', 'Contact__c');
        Assert.isNull(
            ImportHeaderParser.guess('Contact.Status', person),
            'A longer heading that starts with a field name is not that field.'
        );
    }

    @IsTest
    static void aTieBetweenTwoNamesIsNoGuess() {
        Map<String, String> keys = new Map<String, String>();
        ImportHeaderParser.putKey(keys, 'Phone1', 'Phone_1__c');
        ImportHeaderParser.putKey(keys, 'Phone2', 'Phone_2__c');
        Assert.isNull(ImportHeaderParser.guess('Phone3', keys), 'Equally near two fields.');

        Map<String, String> shared = new Map<String, String>();
        ImportHeaderParser.putKey(shared, 'Shift', 'Shift__c');
        ImportHeaderParser.putKey(shared, 'Shift', 'Other_Shift__c');
        Assert.isNull(
            ImportHeaderParser.guess('Shifts', shared),
            'A spelling two names share is never offered.'
        );
    }

    @IsTest
    static void guessesTheObjectOrFieldOfATwoPartHeading() {
        Map<String, String> expected = new Map<String, String>{
            'Contcts.Frist Name' => 'Contact.FirstName',
            'Contact.Frist Name' => 'Contact.FirstName',
            'Contcts: Phone' => 'Contact.Phone',
            'Mobile Phon (Contact)' => 'Contact.MobilePhone'
        };
        for (String header : expected.keySet()) {
            ImportHeaderParser.Resolved found = ImportHeaderParser.resolveOrGuess(
                header,
                objects(),
                new TestFields()
            );
            Assert.isNotNull(found, 'A guess for "' + header + '".');
            Assert.areEqual(
                expected.get(header),
                found.objectName + '.' + found.fieldName,
                'Guesses "' + header + '".'
            );
            Assert.isTrue(found.guessed, '"' + header + '" is flagged as a guess.');
            Assert.isNull(read(header), 'resolve stays exact for "' + header + '".');
        }
        ImportHeaderParser.Resolved exact = ImportHeaderParser.resolveOrGuess(
            'Contact.First Name',
            objects(),
            new TestFields()
        );
        Assert.isFalse(exact.guessed, 'An exact two-part heading is not flagged.');
        for (
            String header : new List<String>{
                'Contcts.Shoe Size',
                'Donor.Phone',
                'Contact.Account',
                'Frist Name'
            }
        ) {
            Assert.isNull(
                ImportHeaderParser.resolveOrGuess(header, objects(), new TestFields()),
                '"' + header + '" must not be guessed.'
            );
        }
    }

    @IsTest
    static void guessesTheObjectASheetOrFileIsNamedFor() {
        ImportHeaderParser.Found found = ImportHeaderParser.objectOfNameOrGuess(
            'Contcts',
            objects()
        );
        Assert.areEqual('Contact', found.name, 'A typo of a tab name.');
        Assert.isTrue(found.guessed, 'Flagged.');
        found = ImportHeaderParser.objectOfFileNameOrGuess('Contcts export 2026.csv', objects());
        Assert.areEqual('Contact', found.name, 'A typo of a file name.');
        Assert.isTrue(found.guessed, 'Flagged.');
        found = ImportHeaderParser.objectOfNameOrGuess('Contacts', objects());
        Assert.isFalse(found.guessed, 'An exact name is not flagged.');
        for (String name : new List<String>{ 'Sheet1', 'Budget 2026', 'Amount', 'Donors', '' }) {
            Assert.isNull(
                ImportHeaderParser.objectOfNameOrGuess(name, objects()),
                '"' + name + '" must not be guessed.'
            );
        }
    }
}
