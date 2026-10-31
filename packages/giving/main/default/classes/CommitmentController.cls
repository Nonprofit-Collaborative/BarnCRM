/**
 * The LWC-facing surface of commitments: the schedule a commitment already has, the
 * schedule a set of entries would produce before anything is saved, generating the
 * schedule on demand, and the four status changes.
 *
 * Every method validates its input and returns a typed result or an error the component
 * can render (plan Section 7.2).
 */
public with sharing class CommitmentController {
    /** One row of a schedule, saved or previewed. */
    public class InstallmentRow {
        @AuraEnabled
        public Id recordId { get; set; }
        @AuraEnabled
        public Integer sequence { get; set; }
        @AuraEnabled
        public Date dueDate { get; set; }
        @AuraEnabled
        public Decimal expectedAmount { get; set; }
        @AuraEnabled
        public Decimal paidAmount { get; set; }
        @AuraEnabled
        public String status { get; set; }
    }

    /** A whole schedule, with the totals the component shows under it. */
    public class SchedulePreview {
        @AuraEnabled
        public List<InstallmentRow> installments { get; set; }
        @AuraEnabled
        public Integer count { get; set; }
        @AuraEnabled
        public Decimal expectedTotal { get; set; }
        @AuraEnabled
        public Boolean saved { get; set; }
        /** The commitment's status, so the component offers only the changes it allows. */
        @AuraEnabled
        public String commitmentStatus { get; set; }
        /**
         * Whether the person may pause, resume, complete or cancel this commitment, so a reader
         * is not offered buttons that can only fail.
         */
        @AuraEnabled
        public Boolean canChange { get; set; }
        /** Whether the person may generate a missing schedule. */
        @AuraEnabled
        public Boolean canGenerate { get; set; }

        public SchedulePreview(List<InstallmentRow> rows, Boolean saved) {
            this.installments = rows;
            this.count = rows.size();
            this.saved = saved;
            Decimal total = 0;
            for (InstallmentRow row : rows) {
                total += row.expectedAmount == null ? 0 : row.expectedAmount;
            }
            this.expectedTotal = total;
        }
    }

    /** What the component sends when it asks what a schedule would look like. */
    public class ScheduleInput {
        @AuraEnabled
        public String commitmentType { get; set; }
        @AuraEnabled
        public Decimal amount { get; set; }
        @AuraEnabled
        public String frequency { get; set; }
        @AuraEnabled
        public Decimal dayOfMonth { get; set; }
        @AuraEnabled
        public Date startDate { get; set; }
        @AuraEnabled
        public Date endDate { get; set; }
        @AuraEnabled
        public Decimal expectedTotal { get; set; }
        @AuraEnabled
        public Decimal installmentsPlanned { get; set; }
    }

    /**
     * The installments a commitment already has, in schedule order.
     */
    @AuraEnabled(cacheable=true)
    public static SchedulePreview getSchedule(Id commitmentId) {
        if (commitmentId == null) {
            throw UserErrors.message(System.Label.Giving_Commitment_NotFound);
        }
        try {
            List<InstallmentRow> rows = new List<InstallmentRow>();
            for (
                Installment__c installment : new InstallmentSelector()
                    .selectByCommitmentIds(new Set<Id>{ commitmentId })
            ) {
                rows.add(toRow(installment));
            }
            SchedulePreview schedule = new SchedulePreview(rows, true);
            List<Commitment__c> commitments = new CommitmentSelector()
                .selectByIds(new Set<Id>{ commitmentId });
            if (commitments.isEmpty()) {
                throw UserErrors.message(System.Label.Giving_Commitment_NotFound);
            }
            schedule.commitmentStatus = commitments[0].Status__c;
            schedule.canChange = canChange(commitmentId);
            schedule.canGenerate =
                schedule.canChange && Schema.SObjectType.Installment__c.isCreateable();
            return schedule;
        } catch (AuraHandledException alreadyHandled) {
            throw alreadyHandled;
        } catch (Exception readFailure) {
            ErrorLogger.log(readFailure, 'CommitmentController.getSchedule');
            throw UserErrors.message(System.Label.Giving_SchedulePreview_LoadError);
        }
    }

    /**
     * The schedule a set of entries would produce, worked out without saving anything, so
     * David can see the twelve payments before he commits to them.
     */
    @AuraEnabled(cacheable=true)
    public static SchedulePreview getSchedulePreview(ScheduleInput input) {
        if (
            input == null ||
            input.amount == null ||
            input.startDate == null ||
            String.isBlank(input.frequency)
        ) {
            throw UserErrors.message(System.Label.Giving_Commitment_InvalidSchedule);
        }
        try {
            Commitment__c draft = new Commitment__c(
                Type__c = String.isBlank(input.commitmentType) ? 'Pledge' : input.commitmentType,
                Amount__c = input.amount,
                Frequency__c = input.frequency,
                Day_of_Month__c = input.dayOfMonth,
                Start_Date__c = input.startDate,
                End_Date__c = input.endDate,
                Expected_Total__c = input.expectedTotal,
                Installments_Planned__c = input.installmentsPlanned
            );
            // The preview shows the schedule the save will make, total filled in the same way.
            CommitmentService.fillExpectedTotals(new List<Commitment__c>{ draft });
            List<InstallmentRow> rows = new List<InstallmentRow>();
            for (Installment__c installment : CommitmentService.buildSchedule(draft)) {
                rows.add(toRow(installment));
            }
            return new SchedulePreview(rows, false);
        } catch (Exception previewFailure) {
            ErrorLogger.log(previewFailure, 'CommitmentController.getSchedulePreview');
            throw UserErrors.message(System.Label.Giving_SchedulePreview_LoadError);
        }
    }

    /**
     * Generates the installments a commitment is missing and returns the schedule that
     * results, for the "Generate now" action on a commitment that has none.
     */
    @AuraEnabled
    public static SchedulePreview generateNow(Id commitmentId) {
        if (commitmentId == null) {
            throw UserErrors.message(System.Label.Giving_Commitment_NotFound);
        }
        if (!canChange(commitmentId) || !Schema.SObjectType.Installment__c.isCreateable()) {
            throw UserErrors.message(System.Label.Giving_Commitment_NoPermission);
        }
        try {
            CommitmentService.generateInstallments(new Set<Id>{ commitmentId });
        } catch (Exception generateFailure) {
            ErrorLogger.log(generateFailure, 'CommitmentController.generateNow');
            throw UserErrors.message(System.Label.Giving_SchedulePreview_GenerateError);
        }
        return getSchedule(commitmentId);
    }

    /**
     * Pauses, resumes, cancels, or completes a commitment.
     */
    @AuraEnabled
    public static SchedulePreview changeStatus(Id commitmentId, String action) {
        if (commitmentId == null) {
            throw UserErrors.message(System.Label.Giving_Commitment_NotFound);
        }
        // Checked first: a refused save would otherwise read as a status the change cannot
        // be made from, which sends a reader looking for the wrong cause.
        if (!canChange(commitmentId)) {
            throw UserErrors.message(System.Label.Giving_Commitment_NoPermission);
        }
        Set<Id> commitmentIds = new Set<Id>{ commitmentId };
        try {
            String wanted = String.isBlank(action) ? '' : action.toLowerCase();
            if ('pause'.equals(wanted)) {
                CommitmentService.pause(commitmentIds);
            } else if ('resume'.equals(wanted)) {
                CommitmentService.resume(commitmentIds);
            } else if ('cancel'.equals(wanted)) {
                CommitmentService.cancel(commitmentIds);
            } else if ('complete'.equals(wanted)) {
                CommitmentService.complete(commitmentIds);
            } else {
                throw UserErrors.message(System.Label.Giving_Commitment_TransitionNotAllowed);
            }
        } catch (CommitmentService.CommitmentException notAllowed) {
            throw UserErrors.message(notAllowed.getMessage());
        } catch (AuraHandledException alreadyHandled) {
            throw alreadyHandled;
        } catch (Exception changeFailure) {
            ErrorLogger.log(changeFailure, 'CommitmentController.changeStatus');
            throw UserErrors.message(System.Label.Giving_Commitment_TransitionNotAllowed);
        }
        return getSchedule(commitmentId);
    }

    /** The person may edit the commitment's status, and this commitment in particular. */
    private static Boolean canChange(Id commitmentId) {
        if (
            !Schema.SObjectType.Commitment__c.isUpdateable() ||
            !Schema.SObjectType.Commitment__c.fields.Status__c.isUpdateable()
        ) {
            return false;
        }
        Id userId = UserInfo.getUserId();
        return ![
                SELECT RecordId
                FROM UserRecordAccess
                WHERE UserId = :userId AND RecordId = :commitmentId AND HasEditAccess = TRUE
                WITH USER_MODE
            ]
            .isEmpty();
    }

    private static InstallmentRow toRow(Installment__c installment) {
        InstallmentRow row = new InstallmentRow();
        row.recordId = installment.Id;
        row.sequence = installment.Sequence__c == null ? null : installment.Sequence__c.intValue();
        row.dueDate = installment.Due_Date__c;
        row.expectedAmount = installment.Expected_Amount__c;
        row.paidAmount = installment.Paid_Amount__c;
        row.status = installment.Status__c;
        return row;
    }
}
