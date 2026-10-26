allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Some plugins (tflite_flutter) set Java 11 but leave Kotlin at its default
// target, which fails Kotlin's JVM target check. Compile their Kotlin for the
// same target as their Java. Registered before any project is evaluated.
subprojects {
    afterEvaluate {
        val android =
            extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
                ?: return@afterEvaluate
        val target =
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(
                android.compileOptions.targetCompatibility.toString(),
            )
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
            compilerOptions.jvmTarget.set(target)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
