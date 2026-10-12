/**
 * What the What's new card on the BarnCRM home page shows, and its Dismiss (C-27).
 *
 * The notes are the shipped `Release_Note__mdt` records of every installed package, read as
 * shipped: they hold no organization data. What a person has already seen is their own
 * user-level `Whats_New_Seen__c` record (canonical model Section 12A, rules R-WN1 to R-WN4,
 * ADR-NEXT `NEXT-whats-new-from-packaged-release-notes.md`).
 */
public with sharing class WhatsNewController {
    // At most four parts of at most four digits: 19 characters, within Last_Seen_Version__c.
    private static final Pattern VERSION_SHAPE = Pattern.compile('^\\d{1,4}(\\.\\d{1,4}){0,3}$');

    /**
     * Notes used instead of the shipped ones. Custom metadata records cannot be created in a
     * test, so tests set this to in-memory records.
     */
    @TestVisible
    private static List<Release_Note__mdt> stubbedNotes;

    /** One note as the card shows it. */
    public class NoteView {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String headline { get; set; }
        @AuraEnabled
        public List<String> details { get; set; }
        @AuraEnabled
        public String module { get; set; }
    }

    /** One release and its notes, in the order the card shows them. */
    public class VersionView {
        @AuraEnabled
        public String version { get; set; }
        @AuraEnabled
        public List<NoteView> notes { get; set; }
    }

    /** The releases this person has not dismissed yet, newest first; empty when nothing is new. */
    @AuraEnabled
    public static List<VersionView> getWhatsNew() {
        try {
            Whats_New_Seen__c row = Whats_New_Seen__c.getValues(UserInfo.getUserId());
            return unseen(shippedNotes(), row == null ? null : row.Last_Seen_Version__c);
        } catch (Exception caught) {
            throw asUserError(caught, 'What\'s new');
        }
    }

    /** Hides the card for this person until a newer release ships notes. */
    @AuraEnabled
    public static void dismiss() {
        try {
            List<Entry> entries = wellFormed(shippedNotes());
            if (!entries.isEmpty()) {
                WhatsNewSeenWriter.markSeen(entries[0].note.Version__c.trim());
            }
        } catch (Exception caught) {
            throw asUserError(caught, 'Dismiss What\'s new');
        }
    }

    /** R-WN2: newer than the last seen version, or only the current one when none is stored. */
    @TestVisible
    private static List<VersionView> unseen(List<Release_Note__mdt> notes, String lastSeen) {
        List<VersionView> result = new List<VersionView>();
        List<Entry> entries = wellFormed(notes);
        if (entries.isEmpty()) {
            return result;
        }
        List<Integer> threshold = parse(lastSeen);
        List<Integer> current = entries[0].parts;
        VersionView open;
        for (Entry entry : entries) {
            Boolean wanted = threshold == null
                ? compare(entry.parts, current) == 0
                : compare(entry.parts, threshold) > 0;
            if (!wanted) {
                continue;
            }
            if (open == null || compare(parse(open.version), entry.parts) != 0) {
                open = new VersionView();
                open.version = entry.note.Version__c.trim();
                open.notes = new List<NoteView>();
                result.add(open);
            }
            open.notes.add(asView(entry.note));
        }
        return result;
    }

    /** The notes whose version is well formed, newest version first, then in sort order. */
    private static List<Entry> wellFormed(List<Release_Note__mdt> notes) {
        List<Entry> entries = new List<Entry>();
        for (Release_Note__mdt note : notes) {
            List<Integer> parts = parse(note.Version__c);
            if (parts != null) {
                entries.add(new Entry(note, parts));
            }
        }
        entries.sort();
        return entries;
    }

    /** The version as whole-number parts, or null when it is not dot separated whole numbers. */
    @TestVisible
    private static List<Integer> parse(String version) {
        if (version == null || !VERSION_SHAPE.matcher(version.trim()).matches()) {
            return null;
        }
        List<Integer> parts = new List<Integer>();
        for (String part : version.trim().split('\\.')) {
            parts.add(Integer.valueOf(part));
        }
        return parts;
    }

    /** Negative, zero or positive as a is older, the same or newer; a missing part is zero. */
    @TestVisible
    private static Integer compare(List<Integer> a, List<Integer> b) {
        Integer length = Math.max(a.size(), b.size());
        for (Integer i = 0; i < length; i++) {
            Integer left = i < a.size() ? a[i] : 0;
            Integer right = i < b.size() ? b[i] : 0;
            if (left != right) {
                return left - right;
            }
        }
        return 0;
    }

    /** A note with its parsed version, ordered for the card. */
    private class Entry implements Comparable {
        Release_Note__mdt note;
        List<Integer> parts;

        Entry(Release_Note__mdt note, List<Integer> parts) {
            this.note = note;
            this.parts = parts;
        }

        public Integer compareTo(Object other) {
            Entry that = (Entry) other;
            Integer byVersion = compare(that.parts, parts);
            if (byVersion != 0) {
                return byVersion;
            }
            Decimal mine = note.Sort_Order__c;
            Decimal theirs = that.note.Sort_Order__c;
            if (mine != theirs) {
                if (mine == null || theirs == null) {
                    return mine == null ? 1 : -1;
                }
                return mine < theirs ? -1 : 1;
            }
            String myName = note.DeveloperName == null ? '' : note.DeveloperName;
            return myName.compareTo(that.note.DeveloperName == null ? '' : that.note.DeveloperName);
        }
    }

    private static NoteView asView(Release_Note__mdt note) {
        NoteView view = new NoteView();
        view.key = note.DeveloperName;
        view.headline = note.Headline__c;
        view.module = note.Module__c;
        view.details = new List<String>();
        if (String.isNotBlank(note.Details__c)) {
            for (String line : note.Details__c.split('\\r?\\n')) {
                if (String.isNotBlank(line)) {
                    view.details.add(line.trim());
                }
            }
        }
        return view;
    }

    private static List<Release_Note__mdt> shippedNotes() {
        if (stubbedNotes != null) {
            return stubbedNotes;
        }
        return [
            SELECT DeveloperName, Version__c, Headline__c, Details__c, Sort_Order__c, Module__c
            FROM Release_Note__mdt
            WITH SYSTEM_MODE
            LIMIT 2000
        ];
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        ErrorLogger.log(caught, context);
        AuraHandledException reported = new AuraHandledException(Label.Core_WhatsNew_Failed);
        reported.setMessage(Label.Core_WhatsNew_Failed);
        return reported;
    }
}
