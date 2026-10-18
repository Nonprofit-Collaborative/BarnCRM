/**
 * A shift names itself from its job and start, and a typed name is kept (R-VS2).
 */
@IsTest(
    testFor='ApexClass:VolunteerShiftTriggerHandler, ApexClass:VolunteerJobSelector, ApexTrigger:VolunteerShiftTrigger'
)
private class VolunteerShiftTriggerHandlerTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.job('Food pantry sort');
        }
    }

    @IsTest
    static void anUnnamedShiftIsNamedAndATypedNameIsKept() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Id jobId = [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
            List<Volunteer_Shift__c> shifts = new List<Volunteer_Shift__c>();
            for (Integer i = 0; i < 251; i++) {
                Volunteer_Shift__c shift = VolunteersTestData.newShift(
                    jobId,
                    VolunteersTestData.SHIFT_START.addDays(i),
                    3
                );
                shift.Name = null;
                shifts.add(shift);
            }
            Volunteer_Shift__c typed = VolunteersTestData.newShift(
                jobId,
                VolunteersTestData.SHIFT_START,
                2
            );
            typed.Name = 'Spring clean';
            shifts.add(typed);

            Test.startTest();
            insert shifts;
            Test.stopTest();

            Map<Id, Volunteer_Shift__c> saved = new Map<Id, Volunteer_Shift__c>(
                [SELECT Id, Name FROM Volunteer_Shift__c]
            );
            Assert.areEqual(
                'Food pantry sort: ' + VolunteersTestData.SHIFT_START.format('d MMM yyyy, h:mm a'),
                saved.get(shifts[0].Id).Name,
                'A shift saved without a name is named from its job and start.'
            );
            Assert.areEqual(
                'Food pantry sort: ' +
                VolunteersTestData.SHIFT_START.addDays(250).format('d MMM yyyy, h:mm a'),
                saved.get(shifts[250].Id).Name,
                'Every one of them.'
            );
            Assert.areEqual('Spring clean', saved.get(typed.Id).Name, 'A typed name is kept.');
        }
    }
}
