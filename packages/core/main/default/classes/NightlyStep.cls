/**
 * One step of BarnCRM's nightly run (ADR-0166 nightly-job-dispatcher, canonical model R-NJ2):
 * a key, a label, a time of day and the schedulable that does the work, run with no context.
 * Core builds its own steps in `NightlyJobs`; a module builds its own in its
 * `NightlyStepProvider`. Steps are built fresh each time they are asked for, so `active` reads
 * the settings as they are now.
 *
 * The key is the row its switch and last result are kept on.
 */
@NamespaceAccessible
public with sharing class NightlyStep {
	/** The step's key: the name its own scheduled job carried before the nightly run. */
	@NamespaceAccessible
	public final String key;

	/** The step's name as an administrator reads it, from a custom label. */
	@NamespaceAccessible
	public final String label;

	/** Minutes after midnight: the step's place in the run and the earliest it starts. */
	@NamespaceAccessible
	public final Integer minute;

	/**
	 * Null for a step with no switch of its own (its settings decide what it does); otherwise
	 * the switch's shipped value, used while no switch has been saved (R-NJ4).
	 */
	@NamespaceAccessible
	public Boolean switchDefault;

	/** False when a setting the step reads has it off tonight (Seasonal Addresses off, say). */
	@NamespaceAccessible
	public Boolean active = true;

	private final Schedulable work;

	/**
	 * @param key the name the step's job was scheduled under
	 * @param label the step's name, from a custom label
	 * @param hour the hour of its usual time, 0 to 23
	 * @param minute the minute of its usual time
	 * @param work the schedulable whose `execute(null)` starts the step's work
	 */
	@NamespaceAccessible
	public NightlyStep(String key, String label, Integer hour, Integer minute, Schedulable work) {
		this.key = key;
		this.label = label;
		this.minute = hour * 60 + minute;
		this.work = work;
	}

	/** Gives the step an on/off switch of its own, shipped on or off. */
	@NamespaceAccessible
	public NightlyStep withSwitch(Boolean shippedOn) {
		this.switchDefault = shippedOn == true;
		return this;
	}

	/** Has the step run tonight only while `isActive` is true. */
	@NamespaceAccessible
	public NightlyStep activeWhen(Boolean isActive) {
		this.active = isActive == true;
		return this;
	}

	/** True when the step has an on/off switch of its own. */
	@NamespaceAccessible
	public Boolean hasSwitch() {
		return switchDefault != null;
	}

	/**
	 * Starts the step's work. The work may start batch or queueable jobs; the run waits for
	 * them (R-NJ3).
	 */
	@NamespaceAccessible
	public void run() {
		work.execute(null);
	}
}
