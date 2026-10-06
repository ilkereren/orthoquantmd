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
    val java8PluginProjects = setOf("desktop_drop", "receive_sharing_intent")
    val projectJavaVersion = if (name in java8PluginProjects) {
        JavaVersion.VERSION_1_8
    } else {
        JavaVersion.VERSION_17
    }
    val projectKotlinTarget = if (name in java8PluginProjects) {
        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
    } else {
        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(projectKotlinTarget)
        }
    }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = projectJavaVersion.toString()
        targetCompatibility = projectJavaVersion.toString()
    }
    plugins.withType<com.android.build.gradle.BasePlugin>().configureEach {
        extensions.configure<com.android.build.gradle.BaseExtension>("android") {
            compileOptions {
                sourceCompatibility = projectJavaVersion
                targetCompatibility = projectJavaVersion
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
