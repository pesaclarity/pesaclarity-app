package com.pesaclarity.app

import android.app.Activity
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Google sign-in for the play build, through Android's Credential Manager.
 * Returns a Google ID token for the server to verify; the foss build has a
 * stand-in with the same name and no Google dependencies.
 */
class GoogleSignInChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/google_sign_in")
    private val credentials = CredentialManager.create(activity)

    init {
        methods.setMethodCallHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(true)
            "requestIdToken" -> {
                val serverClientId = call.argument<String>("serverClientId")
                if (serverClientId.isNullOrBlank()) {
                    result.error("argument", "serverClientId is required", null)
                    return
                }
                requestIdToken(serverClientId, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestIdToken(serverClientId: String, result: MethodChannel.Result) {
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(GetSignInWithGoogleOption.Builder(serverClientId).build())
            .build()
        credentials.getCredentialAsync(
            activity,
            request,
            CancellationSignal(),
            ContextCompat.getMainExecutor(activity),
            object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                override fun onResult(response: GetCredentialResponse) {
                    val credential = response.credential
                    if (credential !is CustomCredential ||
                        credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
                    ) {
                        result.error("failed", "Unexpected credential type", null)
                        return
                    }
                    try {
                        result.success(GoogleIdTokenCredential.createFrom(credential.data).idToken)
                    } catch (e: GoogleIdTokenParsingException) {
                        result.error("failed", "Could not read the Google credential", null)
                    }
                }

                override fun onError(e: GetCredentialException) {
                    when (e) {
                        is GetCredentialCancellationException -> result.success(null)
                        is NoCredentialException ->
                            result.error("no_account", "No Google account on this phone", null)
                        else -> result.error("failed", e.type, null)
                    }
                }
            },
        )
    }
}
