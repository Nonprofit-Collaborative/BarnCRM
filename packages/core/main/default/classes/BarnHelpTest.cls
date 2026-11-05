/**
 * Tests for BarnHelp (ADR-0164 help-text-json): help text by key from the BarnHelp_* static
 * resources, with language fallback to English and empty text, never an exception, when a key,
 * resource or translation is missing.
 */
@IsTest(testFor='ApexClass:BarnHelp')
private class BarnHelpTest {
    @TestSetup
    static void createUser() {
        TestUsers.admin();
    }

    private static void useBodies(Map<String, String> bodies, String language) {
        BarnHelp.bodiesForTest = bodies;
        BarnHelp.languageForTest = language;
    }

    @IsTest
    static void readsTextByKeyAndFormatsPlaceholders() {
        useBodies(
            new Map<String, String>{
                'BarnHelp_Core' => '{"languages":["en"],"texts":{"Core_Example_Intro":"Start here.","Core_Example_Count":"{0} rows."}}'
            },
            'en_US'
        );
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'Start here.',
                BarnHelp.text('Core', 'Core_Example_Intro'),
                'The English text.'
            );
            Assert.areEqual(
                '12 rows.',
                BarnHelp.text('Core', 'Core_Example_Count', new List<Object>{ 12 }),
                'Placeholders are filled in as for a label.'
            );
            Assert.areEqual(
                '',
                BarnHelp.text('Core', 'Core_Not_There'),
                'A missing key is empty text.'
            );
            Assert.areEqual(
                '',
                BarnHelp.text('Programs', 'Programs_Anything'),
                'A missing catalog is empty.'
            );
        }
    }

    @IsTest
    static void prefersTheTranslationAndFallsBackToEnglish() {
        useBodies(
            new Map<String, String>{
                'BarnHelp_Giving' => '{"languages":["en","fr","fr_CA"],"texts":{"A":"Hello.","B":"Only English.","C":"Gift."}}',
                'BarnHelp_Giving_fr' => '{"texts":{"A":"Bonjour.","C":"Don."}}',
                'BarnHelp_Giving_fr_CA' => '{"texts":{"A":"Allo."}}'
            },
            'fr_CA'
        );
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'Allo.',
                BarnHelp.text('Giving', 'A'),
                'The regional translation wins.'
            );
            Assert.areEqual('Don.', BarnHelp.text('Giving', 'C'), 'Then the language.');
            Assert.areEqual('Only English.', BarnHelp.text('Giving', 'B'), 'Then English.');
        }
    }

    @IsTest
    static void ignoresAnUnlistedTranslationAndABrokenFile() {
        useBodies(
            new Map<String, String>{
                'BarnHelp_Core' => '{"languages":["en"],"texts":{"A":"Hello."}}',
                'BarnHelp_Core_de' => '{"texts":{"A":"Hallo."}}',
                'BarnHelp_Mirror' => 'not json'
            },
            'de'
        );
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'Hello.',
                BarnHelp.text('Core', 'A'),
                'A translation not listed is not read.'
            );
            Assert.areEqual(
                '',
                BarnHelp.text('Mirror', 'A'),
                'A file that is not JSON reads as empty.'
            );
        }
    }

    @IsTest
    static void languageCandidatesNeverIncludeEnglish() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                new List<String>(),
                BarnHelp.languageCandidates('en_US'),
                'English is the base.'
            );
            Assert.areEqual(
                new List<String>{ 'fr_CA', 'fr' },
                BarnHelp.languageCandidates('fr_CA'),
                'Regional first.'
            );
            Assert.areEqual(
                new List<String>{ 'de' },
                BarnHelp.languageCandidates('de'),
                'One language.'
            );
        }
    }

    @IsTest
    static void readsThePackagedCoreCatalog() {
        System.runAs(TestUsers.admin()) {
            // The real resource: present in every org BarnCRM Core is in, so reading it never
            // throws, and an unknown key is empty.
            Assert.areEqual(
                '',
                BarnHelp.text('Core', 'Core_No_Such_Help_Key'),
                'Unknown keys are empty.'
            );
        }
    }
}
