/**
 * Tells the person who started a long job that it is over (Q-04): one custom notification, of
 * the packaged type `BarnCRM_Job_Finished`, under the bell and in the mobile app, saying what
 * finished, how it went in numbers, and opening the job's record or its settings page.
 *
 * Each job calls this once, from the end of its last pass. A job a schedule started never
 * notifies: it captures `starter()` when it is built, which is null in a scheduled run, so the
 * nightly and weekly runs stay quiet and a Run now from a page does not.
 *
 * Sending is a courtesy, never part of the job: nothing here throws. The setting
 * `Job_Notifications__c` turned off, no recipient, or the notification type missing from the
 * org sends nothing; a send the platform refuses is written to the Error Log and the job carries
 * on. The platform gives no way to see a sent notification, so every notification about to be
 * sent is also kept in `sent`, which is what the tests assert on.
 */
@NamespaceAccessible
public with sharing class JobNotifier {
    /** The packaged notification type's developer name. */
    public static final String TYPE_NAME = 'BarnCRM_Job_Finished';

    /** The Error Log context a refused send is written under. */
    public static final String LOG_CONTEXT = 'Job notification';

    /**
     * The settings console sections a notification can open, as the console names them. A
     * sub-section name opens its page scrolled to that box (P1).
     */
    public static final String SECTION_GENERAL = 'General';
    /** Where the duplicate scan's panel is: the Duplicate Matching page (ADR-0139). */
    public static final String SECTION_DUPLICATE_MATCHING = SettingSections.DUPLICATE_MATCHING;
    /** The household naming panel's box on People and Households. */
    public static final String SECTION_HOUSEHOLD_NAMES = SettingSections.HOUSEHOLD_NAMES;
    public static final String SECTION_ADDRESSES = 'Addresses';
    @NamespaceAccessible
    public static final String SECTION_ROLLUPS = 'Rollups';
    public static final String SECTION_HEALTH = 'Health';

    private static final String SETTINGS_TAB = 'BarnCRM_Settings';

    /** The platform's limits on a custom notification's title and body. */
    private static final Integer TITLE_LIMIT = 250;
    private static final Integer BODY_LIMIT = 750;

    /** The type looked up; a test names one that does not exist to see the org without it. */
    @TestVisible
    private static String typeName = TYPE_NAME;

    /** Every notification handed to the platform this transaction, in order, for the tests. */
    @TestVisible
    private static List<Notice> sent = new List<Notice>();

    /** Set by a test to have the next send refused, as the platform may refuse one. */
    @TestVisible
    private static Boolean refuseNextSend = false;

    private static Id cachedTypeId;
    private static Boolean typeLookedUp = false;

    /** One notification: who it is for, what it says, and what it opens. */
    @NamespaceAccessible
    public class Notice {
        @NamespaceAccessible
        public Id recipientId;
        @NamespaceAccessible
        public String title;
        public String body;
        /** The record it opens, or null when it opens a settings page. */
        @NamespaceAccessible
        public Id targetId;
        /** The settings console section it opens, or null when it opens a record. */
        @NamespaceAccessible
        public String section;
    }

    private class RefusedException extends Exception {
    }

    /**
     * What this transaction handed to the platform, for a module's tests: `sent` is test visible
     * only inside Core once the namespace is registered.
     */
    @NamespaceAccessible
    public static List<Notice> sentNotices() {
        return sent;
    }

    /**
     * Who to tell about a job being started now: the person running this transaction, or null
     * when a schedule started it, because nobody is waiting for a scheduled run.
     */
    @NamespaceAccessible
    public static Id starter() {
        return System.isScheduled() ? null : UserInfo.getUserId();
    }

    /**
     * Tells `recipientId` that a job is over and opens `recordId` when clicked.
     *
     * @param recipientId who started the job; null sends nothing
     * @param jobName what the job is called, from a label ("Bulk update")
     * @param stopped true when the job did not finish
     * @param body the outcome in numbers, from a label
     * @param recordId the job's own record
     */
    @NamespaceAccessible
    public static void aboutRecord(
        Id recipientId,
        String jobName,
        Boolean stopped,
        String body,
        Id recordId
    ) {
        Notice notice = notice(recipientId, jobName, stopped, body);
        notice.targetId = recordId;
        send(notice);
    }

    /**
     * Tells `recipientId` that a job is over and opens a section of the settings console.
     *
     * @param section one of the SECTION constants
     */
    @NamespaceAccessible
    public static void aboutSettings(
        Id recipientId,
        String jobName,
        Boolean stopped,
        String body,
        String section
    ) {
        Notice notice = notice(recipientId, jobName, stopped, body);
        notice.section = section;
        send(notice);
    }

    private static Notice notice(Id recipientId, String jobName, Boolean stopped, String body) {
        Notice notice = new Notice();
        notice.recipientId = recipientId;
        notice.title = String.format(
            stopped == true
                ? System.Label.Core_JobNotice_Stopped
                : System.Label.Core_JobNotice_Finished,
            new List<Object>{ jobName }
        );
        notice.body = String.isBlank(body) ? notice.title : body;
        return notice;
    }

    private static void send(Notice notice) {
        try {
            if (notice.recipientId == null || !isOn()) {
                return;
            }
            Id typeId = typeId();
            if (typeId == null) {
                return;
            }
            sent.add(notice);
            if (refuseNextSend) {
                refuseNextSend = false;
                throw new RefusedException(notice.title);
            }
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(typeId);
            notification.setTitle(notice.title.abbreviate(TITLE_LIMIT));
            notification.setBody(notice.body.abbreviate(BODY_LIMIT));
            if (notice.targetId != null) {
                notification.setTargetId(notice.targetId);
            } else {
                notification.setTargetPageRef(pageReference(notice.section));
            }
            notification.send(new Set<String>{ String.valueOf(notice.recipientId) });
        } catch (Exception refused) {
            ErrorLogger.log(refused, LOG_CONTEXT, notice.targetId);
        }
    }

    private static Boolean isOn() {
        return SettingsService.getSettings().Job_Notifications__c == true;
    }

    /**
     * The notification type's Id, looked up once a transaction; null when the org lacks it.
     * Queried by name rather than statically, so the class compiles and runs quietly in an org
     * whose edition has no custom notifications at all (ADR-0013).
     */
    private static Id typeId() {
        if (!typeLookedUp) {
            typeLookedUp = true;
            try {
                List<SObject> types = Database.queryWithBinds(
                    'SELECT Id FROM CustomNotificationType WHERE DeveloperName = :typeName LIMIT 1', // detection-only: dynamic, and an org without it is caught below
                    new Map<String, Object>{ 'typeName' => typeName },
                    AccessLevel.SYSTEM_MODE
                );
                cachedTypeId = types.isEmpty() ? null : types[0].Id;
            } catch (QueryException notInThisEdition) {
                // No custom notifications in this org: the feature is simply absent, not broken.
                cachedTypeId = null;
            }
        }
        return cachedTypeId;
    }

    /** The settings console at one section, as the page reference a notification opens. */
    @TestVisible
    private static String pageReference(String section) {
        return JSON.serialize(
            new Map<String, Object>{
                'type' => 'standard__navItemPage',
                'attributes' => new Map<String, Object>{
                    'apiName' => NamespaceUtil.qualify(SETTINGS_TAB)
                },
                'state' => new Map<String, Object>{ NamespaceUtil.stateKey('section') => section }
            }
        );
    }
}
