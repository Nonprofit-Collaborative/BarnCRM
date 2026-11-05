/**
 * The rules of a grant (canonical model 29ZH, ADR-0161 `0161-funders-module.md`): which stages
 * are open (R-GN1), the stage dates (R-GN3) and the program named by record identifier (R-GN4).
 *
 * The program is the Programs module's `Program__c`, found by describe only, so Funders installs
 * without Programs (decision 6). Every read of it runs in user mode.
 */
public with sharing class GrantService {
	public static final String STAGE_PROSPECT = 'Prospect';
	public static final String STAGE_INQUIRY = 'Letter of Inquiry';
	public static final String STAGE_INVITED = 'Invited to Apply';
	public static final String STAGE_APPLIED = 'Applied';
	public static final String STAGE_AWARDED = 'Awarded';
	public static final String STAGE_DECLINED = 'Declined';
	public static final String STAGE_WITHDRAWN = 'Withdrawn';

	/** Every stage, in order: the open ones first (R-GN1). */
	public static final List<String> STAGES = new List<String>{
		STAGE_PROSPECT,
		STAGE_INQUIRY,
		STAGE_INVITED,
		STAGE_APPLIED,
		STAGE_AWARDED,
		STAGE_DECLINED,
		STAGE_WITHDRAWN
	};

	/** The open stages, in board order (R-GN1). */
	public static final List<String> OPEN_STAGES = new List<String>{
		STAGE_PROSPECT,
		STAGE_INQUIRY,
		STAGE_INVITED,
		STAGE_APPLIED
	};

	/** The open stages before anything is submitted: an application deadline still matters (R-GN7). */
	public static final List<String> BEFORE_SUBMITTING = new List<String>{
		STAGE_PROSPECT,
		STAGE_INQUIRY,
		STAGE_INVITED
	};

	private static final Set<String> DECIDED = new Set<String>{
		STAGE_AWARDED,
		STAGE_DECLINED,
		STAGE_WITHDRAWN
	};

	private static final String PROGRAM_OBJECT = 'Program__c';
	private static final Integer PROGRAM_LIMIT = 500;

	/** Thrown with a message a person can act on. */
	public class GrantException extends Exception {
	}

	public static Boolean isOpen(String stage) {
		return OPEN_STAGES.contains(stage);
	}

	/**
	 * R-GN3: an empty Submitted Date becomes today when a grant reaches Applied, and an empty
	 * Decision Date when it reaches Awarded, Declined or Withdrawn. A date already there is kept.
	 *
	 * @param grants the grants being saved
	 * @param oldById their saved versions, null on insert
	 */
	public static void fillStageDates(List<Grant__c> grants, Map<Id, Grant__c> oldById) {
		Date today = Date.today();
		for (Grant__c grant : grants) {
			Grant__c old = oldById == null ? null : oldById.get(grant.Id);
			if (old != null && old.Stage__c == grant.Stage__c) {
				continue;
			}
			if (grant.Stage__c == STAGE_APPLIED && grant.Submitted_Date__c == null) {
				grant.Submitted_Date__c = today;
			}
			if (DECIDED.contains(grant.Stage__c) && grant.Decision_Date__c == null) {
				grant.Decision_Date__c = today;
			}
		}
	}

	/**
	 * R-GN4: stores each grant's program in its 18-character form and refuses text that is not a
	 * record identifier, or, where Programs is installed, an identifier of another object.
	 *
	 * @param grants the grants being saved
	 */
	public static void checkPrograms(List<Grant__c> grants) {
		Schema.SObjectType programType = null;
		Boolean looked = false;
		for (Grant__c grant : grants) {
			if (String.isBlank(grant.Program_Id__c)) {
				grant.Program_Id__c = null;
				continue;
			}
			Id programId = asId(grant.Program_Id__c);
			if (programId != null && !looked) {
				programType = NamespaceUtil.packagedObjectType(PROGRAM_OBJECT);
				looked = true;
			}
			if (
				programId == null ||
				(programType != null &&
				programId.getSObjectType() != programType)
			) {
				grant.Program_Id__c.addError(Label.Funders_Grant_BadProgram);
				continue;
			}
			grant.Program_Id__c = String.valueOf(programId);
		}
	}

	/** The text as a record identifier, or null when it is not one (also used for the fund). */
	public static Id asId(String text) {
		try {
			return Id.valueOf(text.trim());
		} catch (StringException notAnId) {
			return null;
		}
	}

	// ------------------------------------------------------------------------------ programs

	/**
	 * The Programs module's Program object, or null where Programs is not installed or the user
	 * cannot read programs.
	 */
	@TestVisible
	private static Schema.SObjectType programType() {
		Schema.SObjectType type = NamespaceUtil.packagedObjectType(PROGRAM_OBJECT);
		if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
			return null;
		}
		return type;
	}

	/** Whether programs can be chosen here: Programs is installed and the user can read it. */
	public static Boolean programsAvailable() {
		return programType() != null;
	}

	/**
	 * The programs a grant can pay for, by name, as value and label pairs. Empty without Programs.
	 *
	 * @return up to 500 programs the user can see
	 */
	public static List<Map<String, String>> programs() {
		List<Map<String, String>> options = new List<Map<String, String>>();
		Schema.SObjectType type = programType();
		if (type == null) {
			return options;
		}
		// The object name comes from describe, never from the user.
		String soql =
			'SELECT Id, Name FROM ' +
			type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
			' ORDER BY Name LIMIT :maxRows';
		for (
			SObject program : Database.queryWithBinds(
				soql,
				new Map<String, Object>{ 'maxRows' => PROGRAM_LIMIT },
				AccessLevel.USER_MODE
			)
		) {
			options.add(
				new Map<String, String>{
					'value' => (String) program.Id,
					'label' => (String) program.get('Name')
				}
			);
		}
		return options;
	}

	/** The program's name, or null when Programs is absent or the program cannot be found. */
	public static String programName(String programId) {
		Schema.SObjectType type = programType();
		if (type == null || String.isBlank(programId)) {
			return null;
		}
		String soql =
			'SELECT Name FROM ' +
			type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
			' WHERE Id = :programId LIMIT 1';
		List<SObject> rows = Database.queryWithBinds(
			soql,
			new Map<String, Object>{ 'programId' => programId },
			AccessLevel.USER_MODE
		);
		return rows.isEmpty() ? null : (String) rows[0].get('Name');
	}

	/**
	 * Names the program a grant pays for, or clears it. Saved in user mode, so the rules of
	 * R-GN4 and the user's own access apply.
	 *
	 * @param grantId the grant
	 * @param programId a program's record identifier, or blank for none
	 */
	public static void setProgram(Id grantId, String programId) {
		String value = null;
		if (String.isNotBlank(programId)) {
			Schema.SObjectType type = programType();
			Id parsed = asId(programId);
			if (type == null || parsed == null || parsed.getSObjectType() != type) {
				throw new GrantException(Label.Funders_Grant_BadProgram);
			}
			value = String.valueOf(parsed);
		}
		update as user new Grant__c(Id = grantId, Program_Id__c = value);
	}
}
