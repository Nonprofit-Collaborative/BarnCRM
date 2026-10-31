/**
 * R-EN7 and R-SD6 (P-08): shares each new or undeleted enrollment and service delivery with the
 * Programs Participant Records group, so the Participant Privacy preset decides who sees it. Run
 * by the Core trigger dispatcher through the registry rows `Enrollment_Sharing` and
 * `Service_Delivery_Sharing`, which always run: a record with no share would vanish from staff
 * while the preset is Shared.
 */
@NamespaceAccessible
public with sharing class ProgramsSharingHandler extends TriggerHandler {
    @NamespaceAccessible
    public ProgramsSharingHandler() {
        return;
    }

    public override String getName() {
        return 'ProgramsSharingHandler';
    }

    public override void afterInsert() {
        ProgramsSharing.share(Trigger.new);
    }

    public override void afterUndelete() {
        ProgramsSharing.share(Trigger.new);
    }
}
