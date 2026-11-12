/**
 * Volunteers' public pages (V-09; ADR-0198 volunteer self-service, decisions 1 to 3; canonical
 * model R-VJ3 and R-VU10). Core finds this class by name (`PublicPageExtensions`) and BarnCRM
 * Forms serves what it returns on its Site page and REST API; without Forms nothing calls it.
 *
 * - `?list=volunteers`: the Open shifts still to come of jobs with Show on Public Page and Active.
 * - `?record=<shift>`: one such shift, with places left as a count and the job's Sign-Up Form.
 * - `?record=<sign-up>.<claim>`: the person's own page, only when the host checked the signed
 *   claim (`PublicPageExtensions.isSignedRequest`): their upcoming bookings, approved hours and
 *   their value, the last ten approved entries, and the Self-Service Profile Form.
 *
 * `without sharing`, system mode reads, because a Site guest user has no object access. It never
 * shows who else is booked, the coordinator or notes. Every text is finished here, from the help
 * catalog, so a host needs no Volunteers vocabulary.
 */
@NamespaceAccessible
public without sharing class VolunteerPublicPage implements PublicPageExtension {
	public static final String KIND = 'volunteers';
	private static final Integer LIST_LIMIT = 50;
	private static final Set<String> UPCOMING = new Set<String>{
		'Signed up',
		'Confirmed',
		'Waitlisted'
	};

	@NamespaceAccessible
	public VolunteerPublicPage() {
		// Built by name from Core (PublicPageExtensions), so it needs a public constructor.
	}

	public String kind() {
		return KIND;
	}

	public Boolean handles(Schema.SObjectType recordType) {
		return recordType == Volunteer_Shift__c.SObjectType ||
			recordType == Volunteer_Signup__c.SObjectType;
	}

	public Map<String, Object> page(Id recordId) {
		if (recordId.getSObjectType() == Volunteer_Signup__c.SObjectType) {
			return PublicPageExtensions.isSignedRequest() ? personalPage(recordId) : null;
		}
		List<Volunteer_Shift__c> shifts = publicShifts(new Set<Id>{ recordId }, 1);
		if (shifts.isEmpty()) {
			return null;
		}
		Volunteer_Shift__c shift = shifts[0];
		Decimal left = VolunteerBooking.placesLeft(shift);
		Id formId = idOrNull(shift.Volunteer_Job__r.Signup_Form_Key__c);
		String registration = formId == null
			? 'None'
			: left > 0 || VolunteerSettings.waitlistEnabled() ? 'Open' : 'Closed';
		List<Object> facts = new List<Object>();
		String place = String.isNotBlank(shift.Location__c)
			? shift.Location__c
			: shift.Volunteer_Job__r.Location__c;
		if (String.isNotBlank(place)) {
			facts.add(fact(BarnHelp.text('Volunteers', 'Volunteers_Public_Where'), place));
		}
		facts.add(fact(BarnHelp.text('Volunteers', 'Volunteers_Public_Places'), placesText(left)));
		String message = BarnHelp.text('Volunteers', 'Volunteers_Public_SignUpOffline');
		if (registration == 'Open') {
			message = left > 0
				? BarnHelp.text('Volunteers', 'Volunteers_Public_SignUpOpen')
				: BarnHelp.text('Volunteers', 'Volunteers_Public_SignUpWaitlist');
		} else if (registration == 'Closed') {
			message = BarnHelp.text('Volunteers', 'Volunteers_Public_SignUpClosed');
		}
		return new Map<String, Object>{
			'kind' => KIND,
			'recordId' => shift.Id,
			'title' => shift.Volunteer_Job__r.Name,
			'description' => shift.Volunteer_Job__r.Description__c,
			'start' => shift.Start_Time__c,
			'end' => shift.End_Time__c,
			'timeZone' => UserInfo.getTimeZone().getID(),
			'facts' => facts,
			'sections' => new List<Object>(),
			'registration' => registration,
			'formId' => registration == 'None' ? null : formId,
			'message' => message,
			'offlineMessage' => BarnHelp.text('Volunteers', 'Volunteers_Public_SignUpOffline')
		};
	}

	public Map<String, Object> listPage() {
		List<Object> items = new List<Object>();
		for (Volunteer_Shift__c shift : publicShifts(null, LIST_LIMIT)) {
			items.add(
				new Map<String, Object>{
					'recordId' => shift.Id,
					'title' => shift.Volunteer_Job__r.Name,
					'subtitle' => String.isNotBlank(shift.Location__c)
						? shift.Location__c
						: shift.Volunteer_Job__r.Location__c,
					'start' => shift.Start_Time__c,
					'end' => shift.End_Time__c
				}
			);
		}
		return new Map<String, Object>{
			'kind' => KIND,
			'title' => BarnHelp.text('Volunteers', 'Volunteers_Public_ListTitle'),
			'empty' => BarnHelp.text('Volunteers', 'Volunteers_Public_ListEmpty'),
			'timeZone' => UserInfo.getTimeZone().getID(),
			'items' => items
		};
	}

	/** Open shifts still to come of public, active jobs: these, or the soonest when null. */
	private static List<Volunteer_Shift__c> publicShifts(Set<Id> onlyIds, Integer most) {
		// A fixed query with bound values only; the one optional condition is chosen here.
		String query =
			'SELECT Id, Start_Time__c, End_Time__c, Location__c, Volunteers_Needed__c,' +
			' Volunteer_Job__r.Name, Volunteer_Job__r.Description__c, Volunteer_Job__r.Location__c,' +
			' Volunteer_Job__r.Signup_Form_Key__c FROM Volunteer_Shift__c' +
			' WHERE Status__c = \'Open\' AND Start_Time__c > :now' +
			' AND Volunteer_Job__r.Public_Page__c = TRUE AND Volunteer_Job__r.Active__c = TRUE' +
			(onlyIds == null ? '' : ' AND Id IN :onlyIds') +
			' ORDER BY Start_Time__c LIMIT :most';
		return Database.queryWithBinds(
			query,
			new Map<String, Object>{
				'now' => Datetime.now(),
				'onlyIds' => onlyIds,
				'most' => most
			},
			AccessLevel.SYSTEM_MODE
		);
	}

	/** R-VU10: the person's own page, for the Contact the sign-up names. */
	private static Map<String, Object> personalPage(Id signupId) {
		List<Volunteer_Signup__c> signups = [
			SELECT
				Contact__c,
				Contact__r.Volunteer_Hours_This_Year__c,
				Contact__r.Volunteer_Hours_Total__c
			FROM Volunteer_Signup__c
			WHERE Id = :signupId AND Contact__c != NULL
			WITH SYSTEM_MODE
		];
		if (signups.isEmpty()) {
			return null;
		}
		Contact person = signups[0].Contact__r;
		Id personId = signups[0].Contact__c;
		Decimal total = person.Volunteer_Hours_Total__c == null
			? 0
			: person.Volunteer_Hours_Total__c;
		Decimal thisYear = person.Volunteer_Hours_This_Year__c == null
			? 0
			: person.Volunteer_Hours_This_Year__c;
		List<Object> facts = new List<Object>{
			fact(BarnHelp.text('Volunteers', 'Volunteers_Public_HoursThisYear'), thisYear.format()),
			fact(BarnHelp.text('Volunteers', 'Volunteers_Public_HoursTotal'), total.format())
		};
		String worth = VolunteerLetterService.money(total * VolunteerSettings.hourValue());
		if (worth != null) {
			facts.add(fact(BarnHelp.text('Volunteers', 'Volunteers_Public_HoursValue'), worth));
		}
		List<Object> sections = new List<Object>();
		addSection(
			sections,
			'upcoming',
			BarnHelp.text('Volunteers', 'Volunteers_Public_Upcoming'),
			upcoming(personId)
		);
		addSection(
			sections,
			'hours',
			BarnHelp.text('Volunteers', 'Volunteers_Public_RecentHours'),
			recentHours(personId)
		);
		Id formId = VolunteerSettings.profileFormId();
		return new Map<String, Object>{
			'kind' => KIND,
			'recordId' => signupId,
			'title' => BarnHelp.text('Volunteers', 'Volunteers_Public_MyTitle'),
			'timeZone' => UserInfo.getTimeZone().getID(),
			'facts' => facts,
			'sections' => sections,
			'registration' => formId == null ? 'None' : 'Open',
			'formId' => formId,
			'message' => formId == null
				? null
				: BarnHelp.text('Volunteers', 'Volunteers_Public_ProfileOpen'),
			'offlineMessage' => null
		};
	}

	private static List<Object> upcoming(Id personId) {
		Datetime now = Datetime.now();
		List<Object> items = new List<Object>();
		for (Volunteer_Signup__c booking : [
			SELECT
				Status__c,
				Volunteer_Shift__r.Start_Time__c,
				Volunteer_Shift__r.End_Time__c,
				Volunteer_Shift__r.Location__c,
				Volunteer_Shift__r.Volunteer_Job__r.Name
			FROM Volunteer_Signup__c
			WHERE
				Contact__c = :personId
				AND Status__c IN :UPCOMING
				AND Volunteer_Shift__r.Start_Time__c > :now
			WITH SYSTEM_MODE
			ORDER BY Volunteer_Shift__r.Start_Time__c
			LIMIT :LIST_LIMIT
		]) {
			items.add(
				new Map<String, Object>{
					'title' => booking.Volunteer_Shift__r.Volunteer_Job__r.Name,
					'subtitle' => booking.Volunteer_Shift__r.Location__c,
					'start' => booking.Volunteer_Shift__r.Start_Time__c,
					'end' => booking.Volunteer_Shift__r.End_Time__c,
					'badges' => new List<String>{ booking.Status__c }
				}
			);
		}
		return items;
	}

	private static List<Object> recentHours(Id personId) {
		String approved = VolunteerHoursService.STATUS_APPROVED;
		List<Object> items = new List<Object>();
		for (Volunteer_Hours__c entry : [
			SELECT Date_Worked__c, Hours__c, Volunteer_Job__r.Name
			FROM Volunteer_Hours__c
			WHERE Contact__c = :personId AND Status__c = :approved
			WITH SYSTEM_MODE
			ORDER BY Date_Worked__c DESC
			LIMIT 10
		]) {
			items.add(
				new Map<String, Object>{
					'title' => entry.Volunteer_Job__r.Name,
					'subtitle' => entry.Date_Worked__c == null
						? null
						: entry.Date_Worked__c.format(),
					'text' => BarnHelp.text(
						'Volunteers',
						'Volunteers_Public_HoursEntry',
						new List<Object>{ entry.Hours__c == null ? '0' : entry.Hours__c.format() }
					)
				}
			);
		}
		return items;
	}

	private static String placesText(Decimal left) {
		if (left >= 1000000) {
			return BarnHelp.text('Volunteers', 'Volunteers_Public_PlacesOpen');
		}
		if (left <= 0) {
			return BarnHelp.text('Volunteers', 'Volunteers_Public_Full');
		}
		return left == 1
			? BarnHelp.text('Volunteers', 'Volunteers_Public_PlacesLeftOne')
			: BarnHelp.text(
					'Volunteers',
					'Volunteers_Public_PlacesLeft',
					new List<Object>{ left.format() }
			  );
	}

	private static Map<String, Object> fact(String label, String value) {
		return new Map<String, Object>{ 'label' => label, 'value' => value };
	}

	private static void addSection(
		List<Object> sections,
		String key,
		String title,
		List<Object> items
	) {
		if (!items.isEmpty()) {
			sections.add(
				new Map<String, Object>{ 'key' => key, 'title' => title, 'items' => items }
			);
		}
	}

	private static Id idOrNull(String value) {
		try {
			return String.isBlank(value) ? null : Id.valueOf(value.trim());
		} catch (StringException notAnId) {
			return null;
		}
	}
}
