/**
 * Records what `JobNotifier.starter()` answers inside a scheduled run, as an account name, for
 * JobNotifierTest. A class of its own because the platform does not run a schedulable that is
 * an inner class of a test class when the test stops.
 */
@IsTest
public class JobNotifierProbe implements Schedulable {
    public void execute(SchedulableContext context) {
        Id starter = JobNotifier.starter();
        insert new Account(Name = starter == null ? 'Starter: none' : 'Starter: ' + starter);
    }
}
