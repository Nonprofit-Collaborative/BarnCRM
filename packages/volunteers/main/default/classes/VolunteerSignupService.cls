/**
 * Sign-ups: one per person per shift, and attendance that writes the hours (V-02, canonical
 * model Section 29L). Each rule takes explicit lists, so `VolunteerSignupTriggerHandler` stays a
 * wrapper and the rules are tested without a trigger context.
 */
public with sharing class VolunteerSignupService {
    public static final String STATUS_ATTENDED = 'Attended';
    private static final Decimal MILLISECONDS_PER_HOUR = 3600000;

    /**
     * R-VU2: a second sign-up for the same person on the same shift is refused, naming the
     * shift: it is always a mistake and would double the filled count. Every sign-up in the org
     * counts, a cancelled one included, so the coordinator changes the one already there. Only
     * the sign-ups given are checked: new ones, and saved ones whose shift or person changed.
     */
    public static void refuseSecondSignups(List<Volunteer_Signup__c> signups) {
        Set<Id> shiftIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> checkedIds = new Set<Id>();
        for (Volunteer_Signup__c signup : signups) {
            if (signup.Volunteer_Shift__c == null || personOf(signup) == null) {
                continue;
            }
            shiftIds.add(signup.Volunteer_Shift__c);
            if (signup.Contact__c != null) {
                contactIds.add(signup.Contact__c);
            } else {
                accountIds.add(signup.Account__c);
            }
            if (signup.Id != null) {
                checkedIds.add(signup.Id);
            }
        }
        if (shiftIds.isEmpty()) {
            return;
        }

        Set<String> taken = new Set<String>();
        for (
            Volunteer_Signup__c existing : VolunteerIntegritySelector.selectSignupsFor(
                shiftIds,
                contactIds,
                accountIds
            )
        ) {
            if (!checkedIds.contains(existing.Id)) {
                taken.add(keyOf(existing));
            }
        }

        Map<Id, Volunteer_Shift__c> shifts = null;
        for (Volunteer_Signup__c signup : signups) {
            if (signup.Volunteer_Shift__c == null || personOf(signup) == null) {
                continue;
            }
            String key = keyOf(signup);
            if (taken.contains(key)) {
                if (shifts == null) {
                    shifts = VolunteerShiftSelector.selectByIds(shiftIds);
                }
                Volunteer_Shift__c shift = shifts.get(signup.Volunteer_Shift__c);
                String shiftName = shift == null
                    ? String.valueOf(signup.Volunteer_Shift__c)
                    : shift.Name;
                signup.addError(
                    String.format(
                        Label.Volunteers_Signup_AlreadySignedUp,
                        new List<String>{ shiftName }
                    )
                );
            } else {
                taken.add(key);
            }
        }
    }

    /**
     * R-VU3: when Attendance Creates Hours is on, a sign-up that becomes Attended writes one
     * hours entry for its person, dated the shift's start, for the shift's length, against the
     * shift and its job, naming the sign-up. A sign-up an entry already names gets no second
     * one, and moving a sign-up away from Attended deletes nothing.
     *
     * The entries go through `VolunteerHoursService.submit`, so they start Submitted, or
     * Approved when Hours Require Approval is off, like any other entry. A sign-up whose entry
     * cannot be saved is refused with the reason, and the others are saved.
     */
    public static void createHoursForAttendance(
        List<Volunteer_Signup__c> signups,
        Map<Id, Volunteer_Signup__c> previousById
    ) {
        List<Volunteer_Signup__c> attended = new List<Volunteer_Signup__c>();
        for (Volunteer_Signup__c signup : signups) {
            Volunteer_Signup__c previous = previousById == null
                ? null
                : previousById.get(signup.Id);
            Boolean becameAttended =
                signup.Status__c == STATUS_ATTENDED &&
                (previous == null ||
                previous.Status__c != STATUS_ATTENDED);
            if (becameAttended && personOf(signup) != null) {
                attended.add(signup);
            }
        }
        if (attended.isEmpty() || !VolunteerSettings.attendanceCreatesHours()) {
            return;
        }

        Set<Id> alreadyRecorded = VolunteerIntegritySelector.selectSignupsWithHours(
            new Map<Id, Volunteer_Signup__c>(attended).keySet()
        );
        Set<Id> shiftIds = new Set<Id>();
        for (Volunteer_Signup__c signup : attended) {
            shiftIds.add(signup.Volunteer_Shift__c);
        }
        Map<Id, Volunteer_Shift__c> shifts = VolunteerShiftSelector.selectByIds(shiftIds);

        List<Volunteer_Signup__c> sources = new List<Volunteer_Signup__c>();
        List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
        for (Volunteer_Signup__c signup : attended) {
            Volunteer_Shift__c shift = shifts.get(signup.Volunteer_Shift__c);
            if (alreadyRecorded.contains(signup.Id) || shift == null) {
                continue;
            }
            Decimal hours = lengthInHours(shift);
            if (hours == null || hours <= 0) {
                continue;
            }
            sources.add(signup);
            entries.add(
                new Volunteer_Hours__c(
                    Contact__c = signup.Contact__c,
                    Account__c = signup.Contact__c == null ? signup.Account__c : null,
                    Volunteer_Shift__c = shift.Id,
                    Volunteer_Job__c = shift.Volunteer_Job__c,
                    Volunteer_Signup__c = signup.Id,
                    Date_Worked__c = shift.Start_Time__c.date(),
                    Hours__c = hours
                )
            );
        }

        List<Database.SaveResult> results = VolunteerHoursService.submit(entries);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                sources[i].addError(results[i].getErrors()[0].getMessage());
            }
        }
    }

    /** The shift's length in hours, to two decimal places, or null when a time is missing. */
    public static Decimal lengthInHours(Volunteer_Shift__c shift) {
        if (shift.Start_Time__c == null || shift.End_Time__c == null) {
            return null;
        }
        Decimal milliseconds = shift.End_Time__c.getTime() - shift.Start_Time__c.getTime();
        return (milliseconds / MILLISECONDS_PER_HOUR).setScale(2, RoundingMode.HALF_UP);
    }

    private static Id personOf(Volunteer_Signup__c signup) {
        return signup.Contact__c != null ? signup.Contact__c : signup.Account__c;
    }

    private static String keyOf(Volunteer_Signup__c signup) {
        return String.valueOf(signup.Volunteer_Shift__c) + '|' + String.valueOf(personOf(signup));
    }
}
