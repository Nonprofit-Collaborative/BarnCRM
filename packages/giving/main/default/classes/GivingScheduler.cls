/**
 * The Giving module's five nightly jobs as steps of Core's one nightly run (ADR-0166
 * nightly-job-dispatcher), keyed by the name each was once scheduled under. Each is switched on
 * and off on its own, and started now where that is safe, from the shared Nightly Jobs card of
 * BarnCRM Settings (ADR-0038 as amended by D-200 S6), which also shows each job's own summary
 * of its last run.
 *
 * The pledge reminders joined the other four in 1.5 (G-37). Scheduling them sends nothing on its
 * own: like the ask reminders, the step does nothing while its setting is off, and
 * `Pledge_Reminders_Enabled__c` ships off (D-162). The Pledge Reminders page keeps its own switch
 * for that one step.
 *
 * All five are safe to run twice on the same day: topping up a schedule adds only the
 * installments that are missing, marking overdue and placing donors on their giving level are
 * recalculations, and both reminder passes skip a donor or payment already reminded. Donor
 * levels offer no Run Now on the card: the Donor Levels page has its own Recalculate Now, and a
 * second button for the same work is a second thing to keep true (ADR-0038).
 */
public with sharing class GivingScheduler {
	/** The names the jobs were scheduled under, now their step keys. */
	public static final String TOP_UP_JOB_NAME = 'BarnCRM Giving Installment Top Up';
	public static final String OVERDUE_JOB_NAME = 'BarnCRM Giving Installments Overdue';
	public static final String LEVELS_JOB_NAME = 'BarnCRM Giving Donor Levels';
	public static final String ASK_JOB_NAME = 'BarnCRM Giving Ask Reminders';
	public static final String PLEDGE_JOB_NAME = PledgeReminderScheduler.JOB_NAME;

	/**
	 * The five jobs as steps of the nightly run. The times, and why they are these times: the
	 * top up runs first so the overdue pass sees every payment it created, and the donor level
	 * pass runs an hour after the rollups at 02:00, because the ladder reads a giving total the
	 * rollups maintain. The pledge reminders follow at 03:15, after the overdue pass, and the ask
	 * reminders at 03:30, on settled data (G-29). The nightly run also never starts a step before
	 * the one before it has finished.
	 */
	public static List<NightlyStep> steps() {
		Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
		return new List<NightlyStep>{
			new NightlyStep(
					TOP_UP_JOB_NAME,
					System.Label.Giving_NightlyJobs_TopUpName,
					1,
					15,
					new InstallmentTopUpSchedulable()
				)
				.withSwitch(true)
				.withSummary(settings.Installment_Top_Up_Last_Run_Summary__c)
				.runnableNow(),
			new NightlyStep(
					OVERDUE_JOB_NAME,
					System.Label.Giving_NightlyJobs_OverdueName,
					1,
					45,
					new InstallmentSchedulable()
				)
				.withSwitch(true)
				.withSummary(settings.Installment_Overdue_Last_Run_Summary__c)
				.runnableNow(),
			new NightlyStep(
					LEVELS_JOB_NAME,
					System.Label.Giving_NightlyJobs_LevelsName,
					3,
					0,
					new DonorLevelSchedulable()
				)
				.withSwitch(true),
			PledgeReminderScheduler.step()
				.withSummary(settings.Pledge_Reminders_Last_Run_Summary__c)
				.runnableNow(),
			new NightlyStep(
					ASK_JOB_NAME,
					System.Label.Giving_NightlyJobs_AskRemindersName,
					3,
					30,
					new AskReminderSchedulable()
				)
				.withSwitch(true)
				.withSummary(settings.Ask_Reminders_Last_Run_Summary__c)
				.runnableNow()
		};
	}
}
