/**
 * Volunteer letters for a list of people, ten people per transaction (R-VL4): ten PDFs is what
 * one transaction of the PDF service is sized for (ADR-0016). Runs as the user who started it,
 * so each chunk reads hours and people in that user's access, as a single letter does.
 *
 * Started from a flow with the Generate volunteer letters action, for example from a screen
 * flow on a list view of contacts.
 */
public with sharing class VolunteerLetterBatch implements Database.Batchable<Id> {
    public static final Integer PEOPLE_PER_CHUNK = 10;
    private static final String LOG_CONTEXT = 'VolunteerLetterBatch';

    private final List<Id> personIds;
    private final Id templateId;
    private final Date fromDate;
    private final Date toDate;

    public VolunteerLetterBatch(List<Id> personIds, Id templateId, Date fromDate, Date toDate) {
        this.personIds = personIds == null ? new List<Id>() : personIds;
        this.templateId = templateId;
        this.fromDate = fromDate;
        this.toDate = toDate;
    }

    /** What a flow passes: the people, the template and the period. */
    public class Request {
        @InvocableVariable(
            label='Person Ids'
            description='Contact or person account Ids'
            required=true
        )
        public List<Id> personIds;
        @InvocableVariable(label='Letter Template Id' required=true)
        public Id templateId;
        @InvocableVariable(label='From Date' required=true)
        public Date fromDate;
        @InvocableVariable(label='To Date' required=true)
        public Date toDate;
    }

    /**
     * Starts one run per request and returns its job Id. Refused up front without Manage
     * Volunteers, so a flow fails on screen rather than in a background job.
     */
    @InvocableMethod(
        label='Generate volunteer letters'
        description='Saves a volunteer hours letter or certificate as a PDF file on each person with approved hours in the period.'
        category='BarnCRM Volunteers'
    )
    public static List<Id> generateLetters(List<Request> requests) {
        VolunteerLetterService.requireManage();
        List<Id> jobIds = new List<Id>();
        for (Request request : requests) {
            jobIds.add(
                Database.executeBatch(
                    new VolunteerLetterBatch(
                        request.personIds,
                        request.templateId,
                        request.fromDate,
                        request.toDate
                    ),
                    PEOPLE_PER_CHUNK
                )
            );
        }
        return jobIds;
    }

    public Iterable<Id> start(Database.BatchableContext context) {
        return personIds;
    }

    public void execute(Database.BatchableContext context, List<Id> scope) {
        try {
            VolunteerLetterService.generate(scope, templateId, fromDate, toDate);
        } catch (Exception failed) {
            ErrorLogger.log(failed, LOG_CONTEXT);
        }
    }

    public void finish(Database.BatchableContext context) {
        return;
    }
}
