/**
 * The seam a dependent package uses to tell Core which of its objects no data job may write
 * (canonical model R-IT14; ADR-NEXT `NEXT-import-load-one-object.md`), so Core's protected list
 * names no module's object, not even as text (ADR-0059: Core is neutral). The same shape as
 * `HealthCheckExtension`: Core looks an implementation up by name with `Type.forName`
 * (`DataProtectionExtensions`) and asks it only if it is installed.
 */
@NamespaceAccessible
public interface DataProtectionExtension {
    /**
     * The package's own bookkeeping objects, whose records no import or one-object load may
     * create or change, for example records that are an audit trail. Never null.
     */
    Set<Schema.SObjectType> protectedObjects();
}
