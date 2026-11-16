package io.fingerly.sdk.flutter

import io.fingerly.sdk.AppChecksProvider
import io.fingerly.sdk.PlayIntegrityProvider
import io.fingerly.sdk.appchecks.FingerlyAppChecks
import io.fingerly.sdk.playintegrity.FingerlyPlayIntegrity

/**
 * The optional `io.fingerly:fingerly-app-checks` and
 * `io.fingerly:fingerly-play-integrity` providers, found the same way the
 * React Native module finds them.
 *
 * Both artifacts are `compileOnly` here, so the host app decides whether they
 * ship. When the app links one, the constructor runs; when it does not, the
 * class is missing at run time and the constructor throws a [LinkageError]
 * (`NoClassDefFoundError`), which reads as "not installed".
 */
internal object OptionalProviders {

    const val PLAY_INTEGRITY_UNAVAILABLE = "play_integrity_unavailable"

    const val PLAY_INTEGRITY_UNAVAILABLE_MESSAGE =
        "playIntegrityCloudProjectNumber was set but the io.fingerly:fingerly-play-integrity " +
            "artifact is not on the classpath"

    val appChecks: AppChecksProvider? by lazy(LazyThreadSafetyMode.PUBLICATION) {
        try {
            FingerlyAppChecks()
        } catch (_: LinkageError) {
            null
        }
    }

    val playIntegrity: PlayIntegrityProvider? by lazy(LazyThreadSafetyMode.PUBLICATION) {
        try {
            FingerlyPlayIntegrity()
        } catch (_: LinkageError) {
            null
        }
    }

    /**
     * The configuration error for a project number that no provider can use,
     * or null when the configuration is complete. A project number needs the
     * artifact's [provider] or one the app registered by hand
     * ([registeredByHand]). No project number is always complete: Play
     * Integrity is simply off.
     */
    fun playIntegrityError(
        projectNumber: Long?,
        provider: PlayIntegrityProvider?,
        registeredByHand: Boolean,
    ): String? =
        if (projectNumber != null && provider == null && !registeredByHand) {
            PLAY_INTEGRITY_UNAVAILABLE_MESSAGE
        } else {
            null
        }
}
