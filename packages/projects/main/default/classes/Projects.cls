/**
 * What the Project Management classes share (ADR-NEXT `NEXT-project-management-module.md`): the
 * module key, the Manage Projects check and the refusal a person reads as written.
 */
public with sharing class Projects {
	public static final String MODULE = 'Projects';
	public static final String MANAGE = 'Projects_Manage';
	public static final String DONE = 'Done';
	public static final String CANCELLED = 'Cancelled';
	public static final String ACTIVE = 'Active';

	/** A refusal written for the person: `UserErrors` shows it as it is. */
	public class ProjectsException extends Exception {
	}

	/** Whether the running user holds Manage Projects (in Projects Admin). */
	public static Boolean canManage() {
		return FeatureManagement.checkPermission(MANAGE);
	}

	/** Refuses, in words, anyone without Manage Projects. */
	public static void requireManage() {
		if (!canManage()) {
			throw refuse(BarnHelp.text('Projects', 'Projects_Error_NoPermission'));
		}
	}

	/** A refusal written for the person, from the module's help text. */
	public static ProjectsException refuse(String message) {
		return new ProjectsException(message);
	}
}
