plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 从环境变量读取签名配置，支持优雅降级
fun getEnvOrProperty(name: String): String? {
    return System.getenv(name) ?: project.findProperty(name) as String?
}

android {
    namespace = "run.daodao.chatmcp"
    compileSdk = flutter.compileSdkVersion
    // Comment out NDK to avoid CI/CD issues
    // ndkVersion = flutter.ndkVersion
    // ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // 签名配置 - 只有在环境变量存在时才创建
    signingConfigs {
        create("release") {
            val storeFile = getEnvOrProperty("SIGNING_STORE_PATH")?.let { file(it) }
            val keyAlias = getEnvOrProperty("SIGNING_KEY_ALIAS")
            val storePassword = getEnvOrProperty("SIGNING_STORE_PASSWORD")
            val keyPassword = getEnvOrProperty("SIGNING_KEY_PASSWORD")
            
            // 只有在所有必要配置都存在时才设置签名
            if (storeFile != null && storeFile.exists() && 
                !keyAlias.isNullOrEmpty() && 
                !storePassword.isNullOrEmpty() && 
                !keyPassword.isNullOrEmpty()) {
                this.storeFile = storeFile
                this.keyAlias = keyAlias
                this.storePassword = storePassword
                this.keyPassword = keyPassword
                println("✅ Release signing config loaded successfully")
            } else {
                println("⚠️ Release signing config incomplete or missing, will use debug signing")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "run.daodao.chatmcp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk = flutter.minSdkVersion
        minSdkVersion(24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Hard requirement: release builds MUST be signed with a real keystore.
            // Falling back to the debug keystore produces APKs signed with a per-CI-runner
            // ephemeral key — every release then gets a different signature and Android
            // refuses to update an existing install (forces uninstall-reinstall).
            //
            // Required GitHub Actions secrets (set in
            // Settings → Secrets and variables → Actions):
            //   SIGNING_KEYSTORE       base64 of the .jks (run `base64 release.jks | pbcopy`)
            //   SIGNING_KEY_ALIAS      e.g. "chatmcp"
            //   SIGNING_STORE_PASSWORD keystore password
            //   SIGNING_KEY_PASSWORD   key password
            //
            // Generate a fresh keystore with: ./scripts/create_keystore.sh
            // Verify locally with: ./scripts/verify_signing.sh
            val releaseSigningConfig = signingConfigs.getByName("release")
            val hasValidSigning = try {
                releaseSigningConfig.storeFile != null &&
                releaseSigningConfig.storeFile!!.exists() &&
                !releaseSigningConfig.keyAlias.isNullOrEmpty() &&
                !releaseSigningConfig.storePassword.isNullOrEmpty() &&
                !releaseSigningConfig.keyPassword.isNullOrEmpty()
            } catch (e: Exception) {
                false
            }

            if (!hasValidSigning) {
                throw GradleException(
                    "Release build requires a valid signing configuration. " +
                    "Set SIGNING_KEYSTORE / SIGNING_KEY_ALIAS / SIGNING_STORE_PASSWORD / " +
                    "SIGNING_KEY_PASSWORD as GitHub Actions secrets (base64-encode the .jks for " +
                    "SIGNING_KEYSTORE), or run ./scripts/create_keystore.sh and configure them locally. " +
                    "Refusing to ship a debug-signed APK — every release was getting a different " +
                    "signature and breaking in-place updates for existing users."
                )
            }

            signingConfig = releaseSigningConfig
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }

        debug {
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
        }
    }
}

flutter {
    source = "../.."
}
