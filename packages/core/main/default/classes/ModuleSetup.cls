/**
 * A package's setup steps, the ones its post-install class runs at install and at every upgrade
 * (FS1). Core asks for them through `ModuleSetups` when an administrator presses Finish Setup,
 * for a package whose source was copied into an org by hand, so no install ever ran them. The
 * class is the package's post-install class, found by name, so it needs a public no-argument
 * constructor.
 */
@NamespaceAccessible
public interface ModuleSetup {
    /**
     * Runs the package's setup steps exactly as its install does, then adds the package's key to
     * the setup marker (`ModuleSetups.markRan`). Safe to run twice. Never throws: a failure is
     * written to the Error Log, as at an install.
     *
     * @param installerId the person who stands in for the installer, or null for none
     */
    void runSetup(Id installerId);
}
