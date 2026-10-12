/**
 * The What's new card (C-27): which notes a person sees, how versions compare, and Dismiss
 * (canonical model R-WN1 to R-WN4).
 *
 * Each test that reads or writes a person's seen record runs as a fresh Read Only user, which
 * also proves the least privileged BarnCRM role can use the card, and keeps the per-user record
 * apart from other test classes running as the running user.
 */
@IsTest
private class WhatsNewControllerTest {
    private static User readOnlyUser() {
        return TestDataFactory.createUser('Reader', new List<String>{ 'BarnCRM_Read_Only' });
    }

    private static Release_Note__mdt note(String name, String version, Integer sortOrder) {
        return new Release_Note__mdt(
            DeveloperName = name,
            Version__c = version,
            Headline__c = 'Headline ' + name,
            Details__c = 'First point\n\n  Second point  \r\nThird point',
            Sort_Order__c = sortOrder,
            Module__c = 'Core'
        );
    }

    private static void ship(List<Release_Note__mdt> notes) {
        WhatsNewController.stubbedNotes = notes;
    }

    private static void markSeenAs(User person, String version) {
        insert new Whats_New_Seen__c(SetupOwnerId = person.Id, Last_Seen_Version__c = version);
    }

    private static List<WhatsNewController.VersionView> readAs(User person) {
        List<WhatsNewController.VersionView> shown;
        System.runAs(person) {
            shown = WhatsNewController.getWhatsNew();
        }
        return shown;
    }

    @IsTest
    static void withNoNotesShippedTheCardIsEmptyAndDismissStoresNothing() {
        User person = readOnlyUser();
        ship(new List<Release_Note__mdt>());

        Test.startTest();
        List<WhatsNewController.VersionView> shown = readAs(person);
        System.runAs(person) {
            WhatsNewController.dismiss();
        }
        Test.stopTest();

        Assert.areEqual(0, shown.size(), 'Nothing shipped, nothing shown.');
        Assert.areEqual(0, [SELECT COUNT() FROM Whats_New_Seen__c], 'Dismiss stored nothing.');
    }

    @IsTest
    static void aFirstViewShowsOnlyTheCurrentRelease() {
        User person = readOnlyUser();
        ship(
            new List<Release_Note__mdt>{
                note('Old', '0.5', 1),
                note('CurrentB', '0.6', 2),
                note('CurrentA', '0.6', 1)
            }
        );

        Test.startTest();
        List<WhatsNewController.VersionView> shown = readAs(person);
        Test.stopTest();

        Assert.areEqual(1, shown.size(), 'Only the current release, not the history.');
        Assert.areEqual('0.6', shown[0].version);
        Assert.areEqual(2, shown[0].notes.size());
        Assert.areEqual('CurrentA', shown[0].notes[0].key, 'Lowest sort order first.');
        Assert.areEqual('Headline CurrentA', shown[0].notes[0].headline);
        Assert.areEqual('Core', shown[0].notes[0].module);
        Assert.areEqual(
            new List<String>{ 'First point', 'Second point', 'Third point' },
            shown[0].notes[0].details,
            'One detail per line, blank lines dropped, trimmed.'
        );
    }

    @IsTest
    static void afterAnUpgradeEveryNewerReleaseIsShownNewestFirst() {
        User person = readOnlyUser();
        markSeenAs(person, '0.6');
        ship(
            new List<Release_Note__mdt>{
                note('Seen', '0.6', 1),
                note('Seven', '0.7', 1),
                note('Twelve', '0.12', 1),
                note('Nine', '0.9', 1),
                note('Unordered', '0.9', null),
                note('Ordered', '0.9', 5)
            }
        );

        Test.startTest();
        List<WhatsNewController.VersionView> shown = readAs(person);
        Test.stopTest();

        Assert.areEqual(3, shown.size(), 'Releases after 0.6 only.');
        Assert.areEqual('0.12', shown[0].version, '0.12 is newer than 0.9.');
        Assert.areEqual('0.9', shown[1].version);
        Assert.areEqual('0.7', shown[2].version);
        Assert.areEqual('Nine', shown[1].notes[0].key);
        Assert.areEqual('Ordered', shown[1].notes[1].key);
        Assert.areEqual('Unordered', shown[1].notes[2].key, 'A note without an order comes last.');
    }

    @IsTest
    static void nothingIsShownWhenThePersonHasSeenTheCurrentRelease() {
        User person = readOnlyUser();
        markSeenAs(person, '0.12');
        ship(new List<Release_Note__mdt>{ note('Nine', '0.9', 1), note('Twelve', '0.12', 1) });

        Test.startTest();
        List<WhatsNewController.VersionView> shown = readAs(person);
        Test.stopTest();

        Assert.areEqual(0, shown.size(), 'Nothing newer than what was dismissed.');
    }

    @IsTest
    static void dismissStoresTheCurrentReleaseAndHidesTheCard() {
        User person = readOnlyUser();
        ship(new List<Release_Note__mdt>{ note('Nine', '0.9', 1), note('Twelve', '0.12', 1) });

        Test.startTest();
        System.runAs(person) {
            WhatsNewController.dismiss();
        }
        List<WhatsNewController.VersionView> shown = readAs(person);
        Test.stopTest();

        Assert.areEqual(0, shown.size(), 'The card is hidden after Dismiss.');
        List<Whats_New_Seen__c> rows = [
            SELECT SetupOwnerId, Last_Seen_Version__c
            FROM Whats_New_Seen__c
        ];
        Assert.areEqual(1, rows.size(), 'No organization-wide or other record is written (R-WN1).');
        Assert.areEqual(person.Id, rows[0].SetupOwnerId);
        Assert.areEqual('0.12', rows[0].Last_Seen_Version__c);
    }

    @IsTest
    static void dismissingAgainAfterAnUpgradeUpdatesTheSameRecord() {
        User person = readOnlyUser();
        markSeenAs(person, '0.6');
        ship(new List<Release_Note__mdt>{ note('Seven', '0.7', 1) });

        Test.startTest();
        System.runAs(person) {
            WhatsNewController.dismiss();
        }
        Test.stopTest();

        List<Whats_New_Seen__c> rows = [
            SELECT Last_Seen_Version__c
            FROM Whats_New_Seen__c
            WHERE SetupOwnerId = :person.Id
        ];
        Assert.areEqual(1, rows.size(), 'One record per person.');
        Assert.areEqual('0.7', rows[0].Last_Seen_Version__c);
    }

    @IsTest
    static void versionsCompareAsNumbersPartByPart() {
        Assert.isTrue(compare('0.12', '0.9') > 0, '0.12 is newer than 0.9.');
        Assert.isTrue(compare('0.9', '0.12') < 0);
        Assert.isTrue(compare('1.0', '0.99') > 0);
        Assert.areEqual(0, compare('0.12', '0.12.0'), 'A missing part counts as zero.');
        Assert.isTrue(compare('0.12.1', '0.12') > 0);
        Assert.areEqual(0, compare(' 0.6 ', '0.6'), 'Surrounding spaces are ignored.');
    }

    @IsTest
    static void malformedVersionsAreIgnored() {
        List<String> malformed = new List<String>{ null, '', 'v0.6', '0..6', '0.6.', 'beta' };
        malformed.addAll(new List<String>{ '1.-2', '1.2.3.4.5', '12345.1' });
        for (String bad : malformed) {
            Assert.isNull(WhatsNewController.parse(bad), 'Not a version: ' + bad);
        }

        List<WhatsNewController.VersionView> shown = WhatsNewController.unseen(
            new List<Release_Note__mdt>{ note('Good', '0.6', 1), note('Bad', 'next', 1) },
            null
        );
        Assert.areEqual(1, shown.size(), 'A malformed note is never shown nor made current.');
        Assert.areEqual('Good', shown[0].notes[0].key);

        shown = WhatsNewController.unseen(
            new List<Release_Note__mdt>{ note('Five', '0.5', 1), note('Six', '0.6', 1) },
            'garbage'
        );
        Assert.areEqual(1, shown.size(), 'A malformed stored version reads as never dismissed.');
        Assert.areEqual('0.6', shown[0].version);
    }

    @IsTest
    static void equalReleasesWrittenDifferentlyShareOneHeading() {
        List<WhatsNewController.VersionView> shown = WhatsNewController.unseen(
            new List<Release_Note__mdt>{ note('A', '0.12', 1), note('B', '0.12.0', 2) },
            null
        );

        Assert.areEqual(1, shown.size(), '0.12 and 0.12.0 are one release.');
        Assert.areEqual(2, shown[0].notes.size());
    }

    @IsTest
    static void twoHundredNotesAcrossManyReleasesAreShownInOrder() {
        // The 200 record rule: no records are written here beyond one seen row per person, so the
        // bulk case is the read, two hundred notes across forty releases.
        List<Release_Note__mdt> notes = new List<Release_Note__mdt>();
        for (Integer i = 0; i < 200; i++) {
            notes.add(note('N' + i, '1.' + Math.mod(i, 40), Math.mod(i, 7)));
        }

        Test.startTest();
        List<WhatsNewController.VersionView> shown = WhatsNewController.unseen(notes, '1.0');
        Test.stopTest();

        Assert.areEqual(39, shown.size(), 'Releases 1.1 to 1.39.');
        Assert.areEqual('1.39', shown[0].version);
        Assert.areEqual('1.1', shown[38].version);
        Integer total = 0;
        for (WhatsNewController.VersionView release : shown) {
            total += release.notes.size();
        }
        Assert.areEqual(195, total, 'Every note after 1.0, none twice.');
    }

    private static Integer compare(String a, String b) {
        return WhatsNewController.compare(WhatsNewController.parse(a), WhatsNewController.parse(b));
    }
}
