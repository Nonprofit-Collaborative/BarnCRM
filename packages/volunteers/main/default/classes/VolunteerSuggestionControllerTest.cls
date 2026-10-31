/**
 * Suggested Volunteers on a shift (V-11, R-VU7): which people are offered and the facts gathered
 * for each. The ranking itself is the framework-free `rankSuggestions` module, tested in Jest.
 * Run as users holding the packaged Volunteers permission sets, so the sets are what is tested.
 */
@IsTest(testFor='ApexClass:VolunteerSuggestionController, ApexClass:VolunteerSuggestionSelector')
private class VolunteerSuggestionControllerTest {
    private static final String COORDINATOR = 'SuggestCoordinator';
    private static final String READER = 'SuggestReader';
    /** A Saturday. Midday, so the org's time zone cannot move it to another day. */
    private static final Datetime SATURDAY_NOON = Datetime.newInstance(2026, 3, 14, 12, 0, 0);

    @TestSetup
    static void makeData() {
        TestUsers.standardUserWith(
            COORDINATOR,
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
        );
        TestUsers.standardUserWith(
            READER,
            new List<String>{ 'BarnCRM_Read_Only', 'Volunteers_Read_Only' }
        );
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.volunteerSettings(false, false);
            Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
            Volunteer_Shift__c shift = VolunteersTestData.newShift(job.Id, SATURDAY_NOON, 3);
            insert shift;
            Skill__c forklift = new Skill__c(Name = 'Forklift', Active__c = true);
            Skill__c spanish = new Skill__c(Name = 'Spanish', Active__c = true);
            insert new List<Skill__c>{ forklift, spanish };
            insert new Job_Skill__c(Job__c = job.Id, Skill__c = forklift.Id);
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Volunteer_Shift__c theShift() {
        return [SELECT Id, Volunteer_Job__c FROM Volunteer_Shift__c WITH SYSTEM_MODE LIMIT 1];
    }

    private static Contact volunteer(String lastName, String status, String days) {
        Contact person = VolunteersTestData.contact(lastName, null);
        person.Volunteer_Status__c = status;
        person.Availability_Days__c = days;
        update person;
        return person;
    }

    private static VolunteerSuggestionController.Candidate find(
        VolunteerSuggestionController.Suggestions result,
        Id personId
    ) {
        for (VolunteerSuggestionController.Candidate candidate : result.candidates) {
            if (candidate.personId == personId) {
                return candidate;
            }
        }
        return null;
    }

    @IsTest
    static void onlyActiveVolunteersNotYetSignedUpAreOffered() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();
            Contact fit = volunteer('Fit', 'Active', 'Saturday;Sunday');
            Contact booked = volunteer('Booked', 'Active', null);
            Contact cancelled = volunteer('Cancelled', 'Active', null);
            volunteer('Prospect', 'Prospective', null);
            volunteer('Retired', 'Inactive', null);
            insert VolunteersTestData.newSignup(shift.Id, booked.Id);
            Volunteer_Signup__c dropped = VolunteersTestData.newSignup(shift.Id, cancelled.Id);
            dropped.Status__c = 'Cancelled';
            insert dropped;

            VolunteerSuggestionController.Suggestions result = VolunteerSuggestionController.getSuggestions(
                shift.Id
            );

            Assert.isTrue(result.canBook, 'An admin can book an open shift.');
            Assert.areEqual('Saturday', result.weekday, 'The shift is on a Saturday.');
            Assert.areEqual(
                1,
                result.candidates.size(),
                'Not signed up (any status), Active only.'
            );
            Assert.areEqual(fit.Id, result.candidates[0].personId, 'The free active volunteer.');
            Assert.areEqual(
                new List<String>{ 'Saturday', 'Sunday' },
                result.candidates[0].availableDays,
                'Available days come as a list.'
            );
            Assert.isFalse(result.moreThanConsidered, 'Well under the bound.');
        }
    }

    @IsTest
    static void skillsInterestsHoursAndOnboardingAreGathered() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();
            Skill__c forklift = [SELECT Id FROM Skill__c WHERE Name = 'Forklift'];
            Skill__c spanish = [SELECT Id FROM Skill__c WHERE Name = 'Spanish'];
            Contact skilled = volunteer('Skilled', 'Active', null);
            Contact keen = volunteer('Keen', 'Active', null);
            Contact other = volunteer('Other', 'Active', null);
            insert new List<Volunteer_Skill__c>{
                new Volunteer_Skill__c(
                    Contact__c = skilled.Id,
                    Skill__c = forklift.Id,
                    Type__c = 'Skill'
                ),
                // Not a skill the job asks for: left out of the facts.
                new Volunteer_Skill__c(
                    Contact__c = skilled.Id,
                    Skill__c = spanish.Id,
                    Type__c = 'Skill'
                ),
                new Volunteer_Skill__c(
                    Contact__c = keen.Id,
                    Skill__c = forklift.Id,
                    Type__c = 'Interest'
                )
            };
            VolunteersTestData.volunteerSettings(false, false);
            Volunteer_Hours__c hours = VolunteersTestData.newHours(
                skilled.Id,
                shift.Volunteer_Job__c,
                6
            );
            insert hours;
            insert new List<Volunteer_Requirement__c>{
                new Volunteer_Requirement__c(
                    Contact__c = skilled.Id,
                    Type__c = 'Orientation',
                    Status__c = 'Completed',
                    Completed_Date__c = Date.today().addDays(-5)
                ),
                new Volunteer_Requirement__c(
                    Contact__c = keen.Id,
                    Type__c = 'Orientation',
                    Status__c = 'In progress'
                )
            };

            VolunteerSuggestionController.Suggestions result = VolunteerSuggestionController.getSuggestions(
                shift.Id
            );

            Assert.areEqual(
                new List<Id>{ forklift.Id },
                result.requiredSkillIds,
                'The job asks for the forklift only.'
            );
            VolunteerSuggestionController.Candidate a = find(result, skilled.Id);
            VolunteerSuggestionController.Candidate b = find(result, keen.Id);
            VolunteerSuggestionController.Candidate c = find(result, other.Id);
            Assert.areEqual(new List<Id>{ forklift.Id }, a.skillIds, 'Skill held.');
            Assert.areEqual(new List<Id>{ forklift.Id }, b.interestIds, 'Interest held.');
            Assert.isTrue(c.skillIds.isEmpty() && c.interestIds.isEmpty(), 'No skills for Other.');
            Assert.areEqual('cleared', a.onboarding, 'A completed step is current.');
            Assert.areEqual('open', b.onboarding, 'A step in progress is not.');
            Assert.areEqual('none', c.onboarding, 'No steps, no signal.');
            Assert.areEqual(0, c.hoursOnJob, 'No hours.');
            Assert.areEqual(
                [SELECT Hours__c FROM Volunteer_Hours__c WHERE Status__c = 'Approved' LIMIT 1]
                .Hours__c,
                a.hoursOnJob,
                'Approved hours on this job.'
            );
        }
    }

    @IsTest
    static void aShiftThatIsNotOpenOffersNothing() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Shift__c shift = theShift();
            volunteer('Fit', 'Active', null);
            update new Volunteer_Shift__c(Id = shift.Id, Status__c = 'Cancelled');

            VolunteerSuggestionController.Suggestions result = VolunteerSuggestionController.getSuggestions(
                shift.Id
            );

            Assert.isFalse(result.canBook, 'A cancelled shift is not offered volunteers.');
            Assert.isTrue(result.candidates.isEmpty(), 'And nobody is listed.');
        }
    }

    @IsTest
    static void aReadOnlyUserGetsNoSuggestions() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            volunteer('Fit', 'Active', null);
        }
        System.runAs(user(READER)) {
            VolunteerSuggestionController.Suggestions result = VolunteerSuggestionController.getSuggestions(
                theShift().Id
            );

            Assert.isFalse(result.canBook, 'Read Only cannot sign anyone up.');
            Assert.isTrue(result.candidates.isEmpty(), 'So it is shown no people.');
        }
    }

    @IsTest
    static void aCoordinatorGetsSuggestionsAndBooksThroughTheSignupsPanel() {
        System.runAs(user(COORDINATOR)) {
            // Made by the coordinator, so what private sharing lets them see is not in question.
            volunteer('Fit', 'Active', 'Saturday');
            Id shiftId = theShift().Id;
            VolunteerSuggestionController.Suggestions before = VolunteerSuggestionController.getSuggestions(
                shiftId
            );
            Assert.areEqual(1, before.candidates.size(), 'One person to suggest.');

            VolunteerShiftSignupsController.addSignup(shiftId, before.candidates[0].personId, null);

            VolunteerSuggestionController.Suggestions after = VolunteerSuggestionController.getSuggestions(
                shiftId
            );
            Assert.isTrue(after.candidates.isEmpty(), 'Booked, so no longer suggested.');
        }
    }

    @IsTest
    static void aMissingShiftOffersNothing() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.isFalse(VolunteerSuggestionController.getSuggestions(null).canBook, 'No id.');
            Assert.areEqual(
                'Monday',
                VolunteerSuggestionController.weekdayOf(Datetime.newInstance(2026, 3, 9, 12, 0, 0)),
                'A Monday reads as Monday.'
            );
        }
    }
}
