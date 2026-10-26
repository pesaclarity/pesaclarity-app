// Used by the dependency scan: records every resolved Gradle dependency in
// gradle.lockfile files so OSV-Scanner can check them. Not used for builds.
allprojects {
    dependencyLocking {
        lockAllConfigurations()
    }
}
