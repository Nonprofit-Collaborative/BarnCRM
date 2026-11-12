/**
 * Volunteer hour letters and certificates (V-08, ADR-0129, canonical model Section 29U).
 *
 * A letter is a template's HTML with its closed set of tokens merged (R-VL2), counting the
 * person's approved hours in a period read in the user's own access (R-VL3), rendered to a PDF
 * and saved as one file linked to the person and to nothing else (R-VL4). Every person's letter
 * in one call is read with the same handful of queries and saved with one insert, so a batch
 * chunk costs the same whether it holds one person or ten.
 */
public with sharing class VolunteerLetterService {
	/** The file name every generated letter is saved with; erasure finds the letters by it. */
	public static final String FILE_NAME = 'volunteer-letter.pdf';

	/** The renderer; a bulk test stands in one that skips the PDF service. */
	@TestVisible
	private static VolunteerLetterRenderer renderer = new VolunteerLetterRenderer();

	public class VolunteerLetterException extends Exception {
	}

	/** One person's merged letter, or why they get none. */
	public class Letter {
		public Id personId;
		public String personName;
		/** The merged template: the inside of the document's body. */
		public String body;
		/** Null when the letter can be made. */
		public String skipReason;
	}

	/** What a generation did: the files made, and each person skipped with the reason. */
	public class Outcome {
		public List<Id> versionIds = new List<Id>();
		public Map<Id, String> skipped = new Map<Id, String>();
	}

	/**
	 * Merges the letter for each person without saving anything, for a preview or before a
	 * generation. A person who cannot get a letter has a skip reason instead of a body.
	 */
	public static List<Letter> mergeLetters(
		List<Id> personIds,
		Id templateId,
		Date fromDate,
		Date toDate
	) {
		return mergeWith(personIds, loadTemplate(templateId), fromDate, toDate);
	}

	private static Volunteer_Letter_Template__c loadTemplate(Id templateId) {
		requireManage();
		Volunteer_Letter_Template__c template = templateId == null
			? null
			: VolunteerLetterSelector.template(templateId);
		if (template == null || String.isBlank(template.Body__c)) {
			throw new VolunteerLetterException(
				BarnHelp.text('Volunteers', 'Volunteers_Letter_TemplateNotFound')
			);
		}
		if (template.Active__c != true) {
			throw new VolunteerLetterException(
				String.format(
					BarnHelp.text('Volunteers', 'Volunteers_Letter_TemplateInactive'),
					new List<Object>{ template.Name }
				)
			);
		}
		return template;
	}

	/**
	 * The one active template of a letter type, for a flow that names a type (R-VL6). Refused
	 * with a readable message when the type is blank, unknown or has no active template.
	 */
	public static Id activeTemplateIdForType(String letterType) {
		requireManage();
		if (String.isBlank(letterType)) {
			throw new VolunteerLetterException(
				BarnHelp.text('Volunteers', 'Volunteers_Letter_TypeRequired')
			);
		}
		Volunteer_Letter_Template__c template = VolunteerLetterSelector.activeTemplateOfType(
			letterType.trim()
		);
		if (template == null || String.isBlank(template.Body__c)) {
			throw new VolunteerLetterException(
				String.format(
					BarnHelp.text('Volunteers', 'Volunteers_Letter_NoActiveTemplateForType'),
					new List<Object>{ letterType.trim() }
				)
			);
		}
		return template.Id;
	}

	/**
	 * Checks everything a generation would refuse for, without making anything: the permission,
	 * the template (found, with a body, active) and the period. A job calls this before it
	 * starts, so the person who asked is told at once instead of by an Error Log entry later.
	 */
	public static void validate(Id templateId, Date fromDate, Date toDate) {
		loadTemplate(templateId);
		requirePeriod(fromDate, toDate);
	}

	private static void requirePeriod(Date fromDate, Date toDate) {
		if (fromDate == null || toDate == null || fromDate > toDate) {
			throw new VolunteerLetterException(
				BarnHelp.text('Volunteers', 'Volunteers_Letter_BadPeriod')
			);
		}
	}

	private static List<Letter> mergeWith(
		List<Id> personIds,
		Volunteer_Letter_Template__c template,
		Date fromDate,
		Date toDate
	) {
		requirePeriod(fromDate, toDate);
		Set<Id> people = new Set<Id>(personIds == null ? new List<Id>() : personIds);
		people.remove(null);
		Map<Id, Person> found = readPeople(people);
		Map<Id, Decimal> totals = new Map<Id, Decimal>();
		Map<Id, String> jobLists = new Map<Id, String>();
		Map<Id, Set<Id>> brandsByPerson = new Map<Id, Set<Id>>();
		collectHours(people, fromDate, toDate, totals, jobLists, brandsByPerson);

		String organizationName = escape(
			BarnCRM_Settings__c.getOrgDefaults().Organization_Legal_Name__c
		);
		Map<String, String> shared = new Map<String, String>{
			'OrganizationName' => organizationName,
			'OrganizationAddress' => escape(OrganizationAddress.oneLine()),
			'BrandName' => organizationName,
			'BrandPhone' => '',
			'BrandWebsite' => '',
			'BrandSignature' => '',
			'BrandLogo' => '',
			'FromDate' => escape(fromDate.format()),
			'ToDate' => escape(toDate.format()),
			'Today' => escape(Date.today().format())
		};
		// V-12 (R-VP5, R-VL2): the value of an hour and of the person's hours; empty at 0.
		Decimal rate = VolunteerSettings.hourValue();
		shared.put('HourValue', escape(money(rate)));
		Map<Id, Map<String, String>> brandTokens = brandTokens(brandsByPerson);

		List<Letter> letters = new List<Letter>();
		for (Id personId : people) {
			Letter letter = new Letter();
			letter.personId = personId;
			Person person = found.get(personId);
			if (person == null) {
				letter.skipReason = personId.getSObjectType() == Account.SObjectType
					? BarnHelp.text('Volunteers', 'Volunteers_Letter_NotAPerson')
					: BarnHelp.text('Volunteers', 'Volunteers_Letter_PersonNotVisible');
			} else if (!totals.containsKey(personId)) {
				letter.personName = person.name;
				letter.skipReason = BarnHelp.text('Volunteers', 'Volunteers_Letter_NoHours');
			} else {
				letter.personName = person.name;
				Map<String, String> values = new Map<String, String>(shared);
				if (brandTokens.containsKey(personId)) {
					values.putAll(brandTokens.get(personId));
				}
				values.put('PersonName', escape(person.name));
				values.put('FirstName', escape(person.firstName));
				values.put('Hours', escape(totals.get(personId).format()));
				values.put('HoursValue', escape(money(totals.get(personId) * rate)));
				values.put('JobList', jobLists.get(personId) + '</ul>');
				letter.body = mergeTokens(template.Body__c, values);
			}
			letters.add(letter);
		}
		return letters;
	}

	/**
	 * Makes and saves the letters: one PDF file per person with approved hours, linked to the
	 * person (R-VL4). Saved in user mode, so the file is the user's, on a person they can see.
	 */
	public static Outcome generate(List<Id> personIds, Id templateId, Date fromDate, Date toDate) {
		Volunteer_Letter_Template__c template = loadTemplate(templateId);
		Outcome outcome = new Outcome();
		List<ContentVersion> files = new List<ContentVersion>();
		for (Letter letter : mergeWith(personIds, template, fromDate, toDate)) {
			if (letter.skipReason != null) {
				outcome.skipped.put(letter.personId, letter.skipReason);
				continue;
			}
			String title = String.format(
					Label.Volunteers_Letter_FileTitle,
					new List<Object>{
						template.Name,
						letter.personName,
						fromDate.format(),
						toDate.format()
					}
				)
				.left(255);
			files.add(
				new ContentVersion(
					Title = title,
					PathOnClient = FILE_NAME,
					VersionData = renderer.render(document(letter.body)),
					FirstPublishLocationId = letter.personId
				)
			);
		}
		Database.insert(files, true, AccessLevel.USER_MODE);
		for (ContentVersion file : files) {
			outcome.versionIds.add(file.Id);
		}
		return outcome;
	}

	/**
	 * The start of the title of every letter made from this template: the title up to the
	 * person's name (`Volunteers_Letter_FileTitle`), which erasure matches a generated letter by.
	 */
	public static String titlePrefix(String templateName) {
		String marker = '<<person>>';
		return String.format(
				Label.Volunteers_Letter_FileTitle,
				new List<Object>{ templateName, marker, '', '' }
			)
			.substringBefore(marker);
	}

	/** The whole HTML document the PDF service renders around a merged body. */
	public static String document(String body) {
		return '<html><head><style>body { font-family: sans-serif; font-size: 12pt; }' +
			'</style></head><body>' +
			body +
			'</body></html>';
	}

	public static void requireManage() {
		if (!VolunteerHoursService.canManage()) {
			throw new VolunteerLetterException(
				BarnHelp.text('Volunteers', 'Volunteers_Letter_NeedManagePermission')
			);
		}
	}

	// ----------------------------------------------------------------------- internals

	private class Person {
		String name;
		String firstName;

		Person(String name, String firstName, String preferredName) {
			this.name = name;
			this.firstName = String.isNotBlank(preferredName)
				? preferredName
				: String.isNotBlank(firstName) ? firstName : name;
		}
	}

	private static Map<Id, Person> readPeople(Set<Id> people) {
		Set<Id> contactIds = new Set<Id>();
		Set<Id> accountIds = new Set<Id>();
		for (Id personId : people) {
			if (personId.getSObjectType() == Contact.SObjectType) {
				contactIds.add(personId);
			} else if (personId.getSObjectType() == Account.SObjectType) {
				accountIds.add(personId);
			}
		}
		Map<Id, Person> found = new Map<Id, Person>();
		if (!contactIds.isEmpty()) {
			for (Contact person : VolunteerLetterSelector.contacts(contactIds)) {
				found.put(
					person.Id,
					new Person(person.Name, person.FirstName, person.Preferred_Name__c)
				);
			}
		}
		for (Account person : VolunteerLetterSelector.personAccounts(accountIds)) {
			found.put(
				person.Id,
				new Person(person.Name, (String) person.get('FirstName'), person.Preferred_Name__c)
			);
		}
		return found;
	}

	/** Fills each person's total and the opening of their job list (closed by the caller). */
	private static void collectHours(
		Set<Id> people,
		Date fromDate,
		Date toDate,
		Map<Id, Decimal> totals,
		Map<Id, String> jobLists,
		Map<Id, Set<Id>> brandsByPerson
	) {
		if (people.isEmpty()) {
			return;
		}
		for (
			AggregateResult row : VolunteerLetterSelector.approvedHoursByJob(
				people,
				fromDate,
				toDate
			)
		) {
			Id personId = (Id) row.get('Contact__c');
			if (personId == null || !people.contains(personId)) {
				personId = (Id) row.get('Account__c');
			}
			Decimal hours = (Decimal) row.get('total');
			if (personId == null || hours == null) {
				continue;
			}
			String job = (String) row.get('jobName');
			if (!brandsByPerson.containsKey(personId)) {
				brandsByPerson.put(personId, new Set<Id>());
			}
			brandsByPerson.get(personId).add((Id) row.get('brandId'));
			totals.put(personId, (totals.containsKey(personId) ? totals.get(personId) : 0) + hours);
			String opening = jobLists.containsKey(personId) ? jobLists.get(personId) : '<ul>';
			jobLists.put(
				personId,
				opening +
					'<li>' +
					escape(
						String.format(
							Label.Volunteers_Letter_JobLine,
							new List<Object>{
								String.isBlank(job) ? Label.Volunteers_Letter_NoJob : job,
								hours.format()
							}
						)
					) +
					'</li>'
			);
		}
	}

	/**
	 * C-47b, R-BR5: the letterhead tokens of each person whose hours in the period are all for
	 * jobs of one brand (no brand reads as the default brand). A person whose jobs span brands, or
	 * any person while brands are off, keeps the organization's identity. Read once per call.
	 */
	private static Map<Id, Map<String, String>> brandTokens(Map<Id, Set<Id>> brandsByPerson) {
		Map<Id, Map<String, String>> result = new Map<Id, Map<String, String>>();
		if (!BrandService.isEnabled()) {
			return result;
		}
		Set<Id> brandIds = new Set<Id>();
		for (Set<Id> brands : brandsByPerson.values()) {
			brandIds.addAll(brands);
		}
		brandIds.remove(null);
		Map<Id, BrandService.Profile> profiles = BrandService.profilesFor(brandIds);
		profiles.put(null, BrandService.profileFor(null));
		Map<String, String> logos = new Map<String, String>();
		for (Id personId : brandsByPerson.keySet()) {
			Set<Id> brands = brandsByPerson.get(personId);
			BrandService.Profile brand = brands.size() == 1
				? profiles.get(new List<Id>(brands)[0])
				: null;
			if (brand == null) {
				continue;
			}
			Map<String, String> tokens = new Map<String, String>{
				'BrandName' => escape(brand.brandName),
				'BrandPhone' => escape(brand.phone),
				'BrandWebsite' => escape(brand.website),
				'BrandSignature' => escape(brand.signature).replace('\n', '<br/>')
			};
			if (String.isNotBlank(brand.legalName)) {
				tokens.put('OrganizationName', escape(brand.legalName));
			}
			if (!brand.addressLines.isEmpty()) {
				tokens.put('OrganizationAddress', escape(String.join(brand.addressLines, ', ')));
			}
			String logoId = brand.logoDocumentId;
			if (String.isNotBlank(logoId) && !logos.containsKey(logoId)) {
				String path = BrandService.logoPath(logoId);
				logos.put(
					logoId,
					path == null ? '' : '<img class="logo" src="' + escape(path) + '" alt=""/>'
				);
			}
			tokens.put('BrandLogo', String.isBlank(logoId) ? '' : logos.get(logoId));
			result.put(personId, tokens);
		}
		return result;
	}

	private static final Pattern TOKEN = Pattern.compile('\\{(\\w+)\\}');

	/**
	 * R-VL2: known tokens only, so a typo is left as typed and shows on the proof. One pass over
	 * the template, so a merged value that happens to look like a token is never merged again.
	 */
	private static String mergeTokens(String body, Map<String, String> values) {
		Matcher found = TOKEN.matcher(body);
		List<String> parts = new List<String>();
		Integer copied = 0;
		while (found.find()) {
			String value = values.get(found.group(1));
			if (value != null) {
				parts.add(body.substring(copied, found.start()));
				parts.add(value);
				copied = found.end();
			}
		}
		parts.add(body.substring(copied));
		return String.join(parts, '');
	}

	private static String escape(String value) {
		return value == null ? '' : value.escapeHtml4();
	}

	private static final Map<String, String> SYMBOLS = new Map<String, String>{
		'USD' => '$',
		'CAD' => '$',
		'AUD' => '$',
		'NZD' => '$',
		'GBP' => '£',
		'EUR' => '€'
	};

	/**
	 * An amount in the org's default currency, such as $1,043.70: the common symbols, else the
	 * ISO code. Null for nothing or 0, so the token merges as empty (R-VP5). The personal page
	 * (`VolunteerPublicPage`) shows the value of hours the same way.
	 */
	public static String money(Decimal amount) {
		if (amount == null || amount <= 0) {
			return null;
		}
		Decimal rounded = amount.setScale(2, System.RoundingMode.HALF_UP);
		Long whole = rounded.longValue();
		String cents = String.valueOf(((rounded - whole) * 100).intValue()).leftPad(2, '0');
		String code = UserInfo.getDefaultCurrency();
		String symbol = SYMBOLS.containsKey(code) ? SYMBOLS.get(code) : code + ' ';
		return symbol + whole.format() + '.' + cents;
	}
}
