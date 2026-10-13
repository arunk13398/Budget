

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    configurations.all {
        resolutionStrategy {
            force("androidx.glance:glance-appwidget:1.1.1")
            force("androidx.glance:glance:1.1.1")
            force("androidx.glance:glance-appwidget-proto:1.1.1")
            force("androidx.glance:glance-appwidget-external-protobuf:1.1.1")
            force("androidx.compose.remote:remote-creation-android:1.0.0-alpha10") // Wait, remote-creation didn't exist in 1.1.1 probably. Let's see if just forcing glance is enough.
        }
    }
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            try {
                val setCompileSdk = androidExt.javaClass.methods.firstOrNull { 
                    it.name == "setCompileSdk" && it.parameterCount == 1 
                }
                setCompileSdk?.invoke(androidExt, 36)
            } catch (_: Exception) {}
            try {
                val compileSdkVersion = androidExt.javaClass.methods.firstOrNull { 
                    it.name == "compileSdkVersion" && it.parameterCount == 1 && it.parameterTypes[0] == Integer.TYPE 
                }
                compileSdkVersion?.invoke(androidExt, 36)
            } catch (_: Exception) {}
            try {
                val getCompileOptions = androidExt.javaClass.methods.firstOrNull { it.name == "getCompileOptions" }
                val compileOptions = getCompileOptions?.invoke(androidExt)
                if (compileOptions != null) {
                    val setSource = compileOptions.javaClass.methods.firstOrNull { it.name == "setSourceCompatibility" && it.parameterCount == 1 }
                    setSource?.invoke(compileOptions, JavaVersion.VERSION_17)
                    val setTarget = compileOptions.javaClass.methods.firstOrNull { it.name == "setTargetCompatibility" && it.parameterCount == 1 }
                    setTarget?.invoke(compileOptions, JavaVersion.VERSION_17)
                }
            } catch (_: Exception) {}
        }
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
    project.evaluationDependsOn(":app")
}

subprojects {
    val fixNamespace = {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            val getNamespace = try {
                androidExt.javaClass.methods.firstOrNull { it.name == "getNamespace" && it.parameterCount == 0 }
            } catch (_: Exception) { null }
            val currentNamespace = getNamespace?.invoke(androidExt)
            if (currentNamespace == null) {
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val manifestXml = manifestFile.readText()
                    val packageMatch = Regex("package=\"([^\"]+)\"").find(manifestXml)
                    if (packageMatch != null) {
                        try {
                            val setNamespace = androidExt.javaClass.methods.firstOrNull {
                                it.name == "setNamespace" && it.parameterCount == 1
                            }
                            setNamespace?.invoke(androidExt, packageMatch.groupValues[1])
                        } catch (_: Exception) {}
                    }
                }
            }
        }
    }
    if (project.state.executed) {
        fixNamespace()
    } else {
        afterEvaluate { fixNamespace() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
