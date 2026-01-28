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

subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.application") || plugins.hasPlugin("com.android.library")) {
            configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(36)
                defaultConfig {
                    targetSdk = 36
                }
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// --- FIX FOR ISAR v3 ON ANDROID GRADLE 8+ (Kotlin DSL) ---
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        
        if (android != null) {
            if (project.name == "isar_flutter_libs") {
                android.namespace = "dev.isar.isar_flutter_libs"
            }
            if (project.name == "usb_serial") {
                android.namespace = "com.github.mjdev.libaums.usb"
            }
        }
    }
}