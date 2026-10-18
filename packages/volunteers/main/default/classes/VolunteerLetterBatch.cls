/**
 * Volunteer letters for a list of people, ten people per transaction (R-VL4): ten PDFs is what
 * one transaction of the PDF service is sized for (ADR-0016). Runs as the user who started it,
 * so each chunk reads hours and people in that user's access, as a single letter does.
 *
 * Started from a flow with the Generate volunteer letters action, for example from a screen
 * flow on a list view of contacts or a record-triggered flow. The action takes a letter Type,
 * checks everything before any job starts (R-VL6), runs every request of one transaction as
 * one job, and the job tells the person who started it how it went (R-VL7).
 */
public with sharing class VolunteerLetterBatch implements Database.Batchable<VolunteerLetterBatch.Work>, Database.Stateful {
    public static final Integer PEOPLE_PER_CHUNK = 10;
    private static final String LOG_CONTEXT = 'VolunteerLetterBatch';
    /** The settings console sections the notification opens, as the console names them. */
    private static final String ERROR_LOG_SECTION = 'Error Log';
    private static final String GENERAL_SECTION = 'General';

    private final List<Work> work;
    private final Id notifyUserId;

    private Integer made = 0;
    private Integer failed = 0;
    private Map<String, Integer> skippedByReason = new Map<String, Integer>();

    /** Up to ten people with the template and period their letters share. */
    public class Work {
        public List<Id> personIds = new List<Id>();
        public Id templateId;
        public Date fromDate;
        public Date toDate;
    }

    public VolunteerLetterBatch(List<Work> work, Id notifyUserId) {
        this.work = work == null ? new List<Work>() : work;
        this.notifyUserId = notifyUserId;
    }

    /**
     * The work for people grouped by the template and period their letters share (so 200
     * one-person requests for one period become 20 chunks, not 200), ten people at a time.
     * A person asked for twice in one group is made one letter.
     */
    private static List<Work> chunks(Map<String, Work> shapes, Map<String, List<Id>> people) {
        List<Work> chunks = new List<Work>();
        for (String key : shapes.keySet()) {
            Work shape = shapes.get(key);
            Work current;
            for (Id personId : people.get(key)) {
                if (current == null || current.personIds.size() >= PEOPLE_PER_CHUNK) {
                    current = new Work();
                    current.templateId = shape.templateId;
                    current.fromDate = shape.fromDate;
                    current.toDate = shape.toDate;
                    chunks.add(current);
                }
                current.personIds.add(personId);
            }
        }
        return chunks;
    }

    /** What a flow passes: the people, the letter type and the period. */
    public class Request {
        @InvocableVariable(
            label='Person Ids'
            description='Contact or person account Ids'
            required=true
        )
        public List<Id> personIds;
        @InvocableVariable(
            label='Letter Type'
            description='Hours letter or Certificate: the type of the template to use. The one active template of that type is used.'
            required=true
        )
        public String letterType;
        @InvocableVariable(label='From Date' required=true)
        public Date fromDate;
        @InvocableVariable(label='To Date' required=true)
        public Date toDate;
    }

    /**
     * Checks every request, then starts one job for all of them and returns its Id once per
     * request (null for a call with nobody to make letters for). Refused up front, with a
     * message the flow's fault path carries, when the person lacks Manage Volunteers, a type has
     * no active template, or a period is missing or reversed.
     */
    @InvocableMethod(
        label='Generate volunteer letters'
        description='Saves a volunteer hours letter or certificate as a PDF file on each person with approved hours in the period, using the active template of the letter type.'
        category='BarnCRM Volunteers'
    )
    public static List<Id> generateLetters(List<Request> requests) {
        VolunteerLetterService.requireManage();
        Map<String, Id> templateByType = new Map<String, Id>();
        Set<String> validated = new Set<String>();
        Map<String, Work> shapes = new Map<String, Work>();
        Map<String, List<Id>> people = new Map<String, List<Id>>();
        Map<String, Set<Id>> seen = new Map<String, Set<Id>>();
        for (Request request : requests) {
            String typeKey = request.letterType == null ? '' : request.letterType.trim();
            if (!templateByType.containsKey(typeKey)) {
                templateByType.put(
                    typeKey,
                    VolunteerLetterService.activeTemplateIdForType(typeKey)
                );
            }
            Id templateId = templateByType.get(typeKey);
            String checkKey = templateId + '|' + request.fromDate + '|' + request.toDate;
            if (validated.add(checkKey)) {
                VolunteerLetterService.validate(templateId, request.fromDate, request.toDate);
                Work shape = new Work();
                shape.templateId = templateId;
                shape.fromDate = request.fromDate;
                shape.toDate = request.toDate;
                shapes.put(checkKey, shape);
                people.put(checkKey, new List<Id>());
                seen.put(checkKey, new Set<Id>());
            }
            for (Id personId : request.personIds == null ? new List<Id>() : request.personIds) {
                if (personId != null && seen.get(checkKey).add(personId)) {
                    people.get(checkKey).add(personId);
                }
            }
        }
        List<Work> allWork = chunks(shapes, people);
        Id jobId = allWork.isEmpty()
            ? null
            : Database.executeBatch(new VolunteerLetterBatch(allWork, JobNotifier.starter()), 1);
        List<Id> jobIds = new List<Id>();
        for (Integer i = 0; i < requests.size(); i++) {
            jobIds.add(jobId);
        }
        return jobIds;
    }

    public Iterable<Work> start(Database.BatchableContext context) {
        return work;
    }

    public void execute(Database.BatchableContext context, List<Work> scope) {
        for (Work chunk : scope) {
            try {
                VolunteerLetterService.Outcome outcome = VolunteerLetterService.generate(
                    chunk.personIds,
                    chunk.templateId,
                    chunk.fromDate,
                    chunk.toDate
                );
                made += outcome.versionIds.size();
                for (String reason : outcome.skipped.values()) {
                    skippedByReason.put(
                        reason,
                        (skippedByReason.containsKey(reason) ? skippedByReason.get(reason) : 0) + 1
                    );
                }
            } catch (Exception problem) {
                failed += chunk.personIds.size();
                ErrorLogger.log(problem, LOG_CONTEXT);
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        JobNotifier.aboutSettings(
            notifyUserId,
            Label.Volunteers_JobNotice_Letters,
            failed > 0 && made == 0,
            summary(made, skippedByReason, failed),
            failed > 0 ? ERROR_LOG_SECTION : GENERAL_SECTION
        );
    }

    /** The notification's body: the three counts, each skip reason, and where failures are. */
    @TestVisible
    private static String summary(
        Integer made,
        Map<String, Integer> skippedByReason,
        Integer failed
    ) {
        Integer skipped = 0;
        for (Integer count : skippedByReason.values()) {
            skipped += count;
        }
        List<String> lines = new List<String>{
            String.format(
                Label.Volunteers_JobNotice_LettersBody,
                new List<Object>{ made.format(), skipped.format(), failed.format() }
            )
        };
        List<String> reasons = new List<String>(skippedByReason.keySet());
        reasons.sort();
        for (String reason : reasons) {
            lines.add(
                String.format(
                    Label.Volunteers_JobNotice_LettersSkipped,
                    new List<Object>{ skippedByReason.get(reason).format(), reason }
                )
            );
        }
        if (failed > 0) {
            lines.add(Label.Volunteers_JobNotice_LettersFailed);
        }
        return String.join(lines, ' ');
    }

    /** Counts so far, for a test or caller that wants them. */
    public Integer lettersMade() {
        return made;
    }

    public Integer peopleFailed() {
        return failed;
    }

    public Map<String, Integer> peopleSkippedByReason() {
        return skippedByReason;
    }
}
