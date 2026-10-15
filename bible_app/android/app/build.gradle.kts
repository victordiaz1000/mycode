import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de publication, lue hors du dépôt.
//
// `android/key.properties` porte le chemin du keystore et les mots de passe ;
// il est dans `.gitignore`, comme le keystore lui-même. Voir `SIGNATURE.md` à
// la racine du dépôt (bym3/) pour le créer.
//
// Absent, la release retombe sur la clé de debug — pour qu'un clone frais
// continue de construire — mais en l'annonçant bruyamment : un APK signé en
// debug s'installe et tourne, mais n'est pas publiable, et la signature
// changera le jour où la vraie clé arrivera, ce qui interdit toute mise à jour
// par-dessus.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKey) FileInputStream(keystorePropertiesFile).use { load(it) }
}

android {
    namespace = "com.bym.bible_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bym.bible_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "\n*** BYM : android/key.properties absent — la release est " +
                        "signee avec la cle de DEBUG.\n" +
                        "*** Installable et testable, mais NI publiable, NI " +
                        "remplacable par une version signee plus tard.\n" +
                        "*** Voir SIGNATURE.md.\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
