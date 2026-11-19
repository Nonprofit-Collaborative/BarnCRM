/**
 * Saved reports and dashboards (ADR-0231 advanced reporting, canonical model 29AR): each is a
 * Salesforce File whose latest version holds the definition as JSON, so Advanced Reporting adds
 * no object. A report is a file with the extension `barnreport`, a dashboard one with
 * `barndash`.
 *
 * Who may see one is Files sharing, enforced by the platform: the owner, and the people the
 * owner shares it with through a ContentDocumentLink to each person (Viewer, or Collaborator
 * when they may change it). Every version is saved with sharing restricted (SharingOption R), so
 * only the owner can share or unlink it, never a Collaborator from the Files tab. Sharing with a
 * public group links each of its direct members now. The owner's choices (`sharing`) are kept
 * with the file but only `share` writes them: `save` never takes them from the browser and
 * carries the stored ones forward, so a stale save cannot change who has access, and `share`
 * links a group's direct members again, adding newcomers and removing people who left. Every
 * read and write here runs in user mode, so nobody reaches a definition the platform would not
 * show them, and a definition never grants access to records: whoever opens it sees what their
 * own access allows (ReportingQueryService).
 */
public with sharing class ReportingLibrary {
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
			'ReportingLibrary',
			'Reporting',
			'Reporting_Error_Generic'
		)
		.showingDml();
	public static final String REPORT = 'barnreport';
	public static final String DASHBOARD = 'barndash';
	public static final String SAVE_PERMISSION = 'Reporting_Save';
	private static final Set<String> KINDS = new Set<String>{ REPORT, DASHBOARD };
	private static final Map<String, String> SHARE_TYPES = new Map<String, String>{
		'view' => 'V',
		'edit' => 'C'
	};
	private static final Integer MAX_DEFINITION = 1000000;
	private static final Integer MAX_PEOPLE = 500;

	/** A refusal written for the person, shown as it is. */
	public class ReportingLibraryException extends Exception {
	}

	/** What the person may do: save and share, and export (Salesforce's Export Reports). */
	@AuraEnabled
	public static Map<String, Object> getContext() {
		try {
			return new Map<String, Object>{
				'canSave' => FeatureManagement.checkPermission(SAVE_PERMISSION),
				'canExport' => ReportingQueryService.canExport(),
				'userId' => UserInfo.getUserId()
			};
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Every saved report and dashboard the person can open, by title, the first 1,000. */
	@AuraEnabled
	public static List<Map<String, Object>> listSaved() {
		try {
			List<ContentVersion> versions = [
				SELECT
					ContentDocumentId,
					Title,
					FileExtension,
					ContentDocument.OwnerId,
					ContentDocument.Owner.Name,
					LastModifiedDate
				FROM ContentVersion
				WHERE IsLatest = TRUE AND FileExtension IN :KINDS
				WITH USER_MODE
				ORDER BY Title
				LIMIT 1000
			];
			Map<Id, String> shareTypes = myShareTypes(versions);
			List<Map<String, Object>> rows = new List<Map<String, Object>>();
			for (ContentVersion version : versions) {
				rows.add(describe(version, shareTypes));
			}
			return rows;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * One saved report or dashboard, with its definition. The owner's sharing choices come apart
	 * from it (`sharing`, for the owner only), so the browser never sends them back with a save.
	 */
	@AuraEnabled
	public static Map<String, Object> load(Id documentId) {
		try {
			ContentVersion version = latest(documentId);
			Map<String, Object> row = describe(
				version,
				myShareTypes(new List<ContentVersion>{ version })
			);
			Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
				version.VersionData.toString()
			);
			Object sharing = definition.remove('sharing');
			row.put('definition', JSON.serialize(definition));
			row.put('sharing', row.get('mine') == true ? sharing : null);
			return row;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * Saves a report or dashboard: a new file when `documentId` is empty, otherwise a new version
	 * of one the person owns or may change. Sharing is never read from the browser: a new file is
	 * private, and a new version keeps the stored sharing and every link as they are (only
	 * `share` changes them). Returns the saved row.
	 */
	@AuraEnabled
	public static Map<String, Object> save(
		String kind,
		Id documentId,
		String title,
		String definitionJson
	) {
		try {
			requireSave();
			Map<String, Object> definition = parse(kind, title, definitionJson);
			definition.remove('sharing');
			if (documentId == null) {
				ContentVersion created = newVersion(null, kind, title, definition);
				insert as user created;
				documentId = [
					SELECT ContentDocumentId
					FROM ContentVersion
					WHERE Id = :created.Id
					WITH USER_MODE
				]
				.ContentDocumentId;
			} else {
				ContentVersion current = latest(documentId);
				Map<String, Object> row = describe(
					current,
					myShareTypes(new List<ContentVersion>{ current })
				);
				if (current.FileExtension != kind || row.get('canEdit') != true) {
					throw new ReportingLibraryException(
						BarnHelp.text('Reporting', 'Reporting_Error_NoEdit')
					);
				}
				Object sharing = sharingOf(current);
				if (sharing != null) {
					definition.put('sharing', sharing);
				}
				insert as user newVersion(documentId, kind, title, definition);
			}
			return load(documentId);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * The owner's sharing: `{users: [{id, name, access}], groups: [...]}`, access `view` or
	 * `edit`. Stored with the file and applied as one link per person, a group's direct members
	 * as they are now. The only place sharing changes.
	 */
	@AuraEnabled
	public static Map<String, Object> share(Id documentId, String sharingJson) {
		try {
			requireSave();
			ContentVersion current = latest(documentId);
			if (current.ContentDocument.OwnerId != UserInfo.getUserId()) {
				throw new ReportingLibraryException(
					BarnHelp.text('Reporting', 'Reporting_Error_OwnerOnly')
				);
			}
			Object sharing = JSON.deserializeUntyped(sharingJson);
			Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
				current.VersionData.toString()
			);
			definition.put('sharing', sharing);
			reconcile(documentId, sharing);
			insert as user newVersion(documentId, current.FileExtension, current.Title, definition);
			return load(documentId);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Deletes a saved report or dashboard; only its owner may. */
	@AuraEnabled
	public static void remove(Id documentId) {
		try {
			requireSave();
			ContentVersion current = latest(documentId);
			if (current.ContentDocument.OwnerId != UserInfo.getUserId()) {
				throw new ReportingLibraryException(
					BarnHelp.text('Reporting', 'Reporting_Error_OwnerOnly')
				);
			}
			delete as user new ContentDocument(Id = documentId);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Active people and public groups whose name holds the text, for Share. */
	@AuraEnabled
	public static List<Map<String, Object>> findPeople(String term) {
		try {
			List<Map<String, Object>> found = new List<Map<String, Object>>();
			if (String.isBlank(term) || term.trim().length() < 2) {
				return found;
			}
			String pattern = '%' + term.trim() + '%';
			for (User person : [
				SELECT Id, Name
				FROM User
				WHERE IsActive = TRUE AND UserType = 'Standard' AND Name LIKE :pattern
				WITH USER_MODE
				ORDER BY Name
				LIMIT 20
			]) {
				found.add(
					new Map<String, Object>{
						'id' => person.Id,
						'name' => person.Name,
						'kind' => 'user'
					}
				);
			}
			for (Group publicGroup : [
				SELECT Id, Name
				FROM Group
				WHERE Type = 'Regular' AND Name LIKE :pattern
				WITH USER_MODE
				ORDER BY Name
				LIMIT 20
			]) {
				found.add(
					new Map<String, Object>{
						'id' => publicGroup.Id,
						'name' => publicGroup.Name,
						'kind' => 'group'
					}
				);
			}
			return found;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * Links each wanted person to the file with their access and removes the links of people no
	 * longer wanted. Only person links are touched; the owner's own link is never changed.
	 */
	private static void reconcile(Id documentId, Object sharing) {
		Map<Id, String> wanted = new Map<Id, String>();
		Map<Id, String> groupAccess = new Map<Id, String>();
		Map<String, Object> chosen = sharing instanceof Map<String, Object>
			? (Map<String, Object>) sharing
			: new Map<String, Object>();
		readEntries(chosen.get('users'), User.SObjectType, wanted);
		readEntries(chosen.get('groups'), Group.SObjectType, groupAccess);
		for (GroupMember member : [
			SELECT GroupId, UserOrGroupId
			FROM GroupMember
			WHERE GroupId IN :groupAccess.keySet()
			WITH USER_MODE
		]) {
			if (member.UserOrGroupId.getSObjectType() == User.SObjectType) {
				grant(wanted, member.UserOrGroupId, groupAccess.get(member.GroupId));
			}
		}
		Set<Id> active = new Map<Id, User>(
				[
					SELECT Id
					FROM User
					WHERE Id IN :wanted.keySet() AND IsActive = TRUE
					WITH USER_MODE
				]
			)
			.keySet();
		wanted.keySet().retainAll(active);
		wanted.remove(UserInfo.getUserId());
		if (wanted.size() > MAX_PEOPLE) {
			throw new ReportingLibraryException(
				BarnHelp.text('Reporting', 'Reporting_Error_TooManyPeople')
			);
		}
		List<ContentDocumentLink> removed = new List<ContentDocumentLink>();
		List<ContentDocumentLink> changed = new List<ContentDocumentLink>();
		for (ContentDocumentLink link : [
			SELECT Id, LinkedEntityId, ShareType
			FROM ContentDocumentLink
			WHERE ContentDocumentId = :documentId
			WITH USER_MODE
		]) {
			Id person = link.LinkedEntityId;
			if (person.getSObjectType() != User.SObjectType || person == UserInfo.getUserId()) {
				continue;
			}
			String shareType = wanted.remove(person);
			if (shareType == null) {
				removed.add(link);
			} else if (shareType != link.ShareType) {
				changed.add(new ContentDocumentLink(Id = link.Id, ShareType = shareType));
			}
		}
		List<ContentDocumentLink> added = new List<ContentDocumentLink>();
		for (Id person : wanted.keySet()) {
			added.add(
				new ContentDocumentLink(
					ContentDocumentId = documentId,
					LinkedEntityId = person,
					ShareType = wanted.get(person),
					Visibility = 'AllUsers'
				)
			);
		}
		delete as user removed;
		update as user changed;
		insert as user added;
	}

	/** Reads `[{id, access}]` entries of one kind into Id to share type; anything else is refused. */
	private static void readEntries(Object raw, Schema.SObjectType kind, Map<Id, String> shares) {
		if (raw == null) {
			return;
		}
		for (Object entry : (List<Object>) raw) {
			Map<String, Object> item = (Map<String, Object>) entry;
			Id entryId = Id.valueOf(String.valueOf(item.get('id')));
			String shareType = SHARE_TYPES.get(String.valueOf(item.get('access')));
			if (entryId.getSObjectType() != kind || shareType == null) {
				throw new ReportingLibraryException(
					BarnHelp.text('Reporting', 'Reporting_Error_Definition')
				);
			}
			grant(shares, entryId, shareType);
		}
	}

	/** Collaborator wins over Viewer when a person is reached twice. */
	private static void grant(Map<Id, String> shares, Id key, String shareType) {
		if (shares.get(key) != 'C') {
			shares.put(key, shareType);
		}
	}

	/** Saving, sharing and deleting need the Advanced Reporting Staff or Admin permission set. */
	private static void requireSave() {
		if (!FeatureManagement.checkPermission(SAVE_PERMISSION)) {
			throw new ReportingLibraryException(BarnHelp.text('Reporting', 'Reporting_Error_NoSave'));
		}
	}

	private static Map<String, Object> parse(String kind, String title, String definitionJson) {
		Object parsed;
		try {
			parsed = String.isBlank(definitionJson) || definitionJson.length() > MAX_DEFINITION
				? null
				: JSON.deserializeUntyped(definitionJson);
		} catch (Exception unreadable) {
			parsed = null;
		}
		if (!KINDS.contains(kind) || !(parsed instanceof Map<String, Object>)) {
			throw new ReportingLibraryException(
				BarnHelp.text('Reporting', 'Reporting_Error_Definition')
			);
		}
		if (String.isBlank(title) || title.trim().length() > 255) {
			throw new ReportingLibraryException(
				BarnHelp.text('Reporting', 'Reporting_Error_Title')
			);
		}
		return (Map<String, Object>) parsed;
	}

	private static ContentVersion newVersion(
		Id documentId,
		String kind,
		String title,
		Map<String, Object> definition
	) {
		return new ContentVersion(
			ContentDocumentId = documentId,
			Title = title.trim(),
			PathOnClient = 'definition.' + kind,
			VersionData = Blob.valueOf(JSON.serialize(definition)),
			// Restricted: only the owner shares or unlinks it, never a Collaborator.
			SharingOption = 'R'
		);
	}

	private static ContentVersion latest(Id documentId) {
		List<ContentVersion> found = [
			SELECT
				ContentDocumentId,
				Title,
				FileExtension,
				ContentDocument.OwnerId,
				ContentDocument.Owner.Name,
				LastModifiedDate,
				VersionData
			FROM ContentVersion
			WHERE ContentDocumentId = :documentId AND IsLatest = TRUE AND FileExtension IN :KINDS
			WITH USER_MODE
			LIMIT 1
		];
		if (found.isEmpty()) {
			throw new ReportingLibraryException(
				BarnHelp.text('Reporting', 'Reporting_Error_NotFound')
			);
		}
		return found[0];
	}

	private static Object sharingOf(ContentVersion version) {
		return ((Map<String, Object>) JSON.deserializeUntyped(version.VersionData.toString()))
			.get('sharing');
	}

	/** The person's own link type for each file: V viewer, C collaborator, I owner or inferred. */
	private static Map<Id, String> myShareTypes(List<ContentVersion> versions) {
		Set<Id> documentIds = new Set<Id>();
		for (ContentVersion version : versions) {
			documentIds.add(version.ContentDocumentId);
		}
		Map<Id, String> types = new Map<Id, String>();
		if (documentIds.isEmpty()) {
			return types;
		}
		for (ContentDocumentLink link : [
			SELECT ContentDocumentId, ShareType
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :UserInfo.getUserId() AND ContentDocumentId IN :documentIds
			WITH USER_MODE
		]) {
			types.put(link.ContentDocumentId, link.ShareType);
		}
		return types;
	}

	private static Map<String, Object> describe(
		ContentVersion version,
		Map<Id, String> shareTypes
	) {
		Boolean mine = version.ContentDocument.OwnerId == UserInfo.getUserId();
		String shareType = shareTypes.get(version.ContentDocumentId);
		return new Map<String, Object>{
			'id' => version.ContentDocumentId,
			'kind' => version.FileExtension,
			'title' => version.Title,
			'ownerName' => version.ContentDocument.Owner.Name,
			'mine' => mine,
			'canEdit' => mine ||
			shareType == 'C' ||
			shareType == 'I',
			'modified' => version.LastModifiedDate
		};
	}
}
