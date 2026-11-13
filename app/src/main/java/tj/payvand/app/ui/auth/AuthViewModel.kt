package tj.payvand.app.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import tj.payvand.core.PayvandApi
import tj.payvand.core.PayvandException
import tj.payvand.core.SignUpResult

enum class AuthStep { WELCOME, SIGN_IN, SIGN_UP, SIGN_UP_CODE, RECOVERY, RECOVERY_CODE }

data class AuthUi(
    val step: AuthStep = AuthStep.WELCOME,
    val email: String = "",
    val password: String = "",
    val code: String = "",
    val loading: Boolean = false,
    val error: Throwable? = null,
    val resendIn: Int = 0,
)

class AuthViewModel(private val api: PayvandApi) : ViewModel() {
    private val _ui = MutableStateFlow(AuthUi())
    val ui: StateFlow<AuthUi> = _ui

    fun reset() { _ui.value = AuthUi() }
    fun go(step: AuthStep) = _ui.update { it.copy(step = step, error = null, code = "", loading = false) }
    fun email(v: String) = _ui.update { it.copy(email = v.trim(), error = null) }
    fun password(v: String) = _ui.update { it.copy(password = v, error = null) }
    fun code(v: String) = _ui.update { it.copy(code = v.filter(Char::isDigit).take(6), error = null) }

    fun back(): Boolean {
        val prev = when (_ui.value.step) {
            AuthStep.WELCOME -> return false
            AuthStep.SIGN_IN, AuthStep.SIGN_UP -> AuthStep.WELCOME
            AuthStep.SIGN_UP_CODE -> AuthStep.SIGN_UP
            AuthStep.RECOVERY -> AuthStep.SIGN_IN
            AuthStep.RECOVERY_CODE -> AuthStep.RECOVERY
        }
        go(prev); return true
    }

    private fun run(block: suspend (AuthUi) -> Unit) {
        val s = _ui.value
        if (s.loading) return
        _ui.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            try { block(s) } catch (e: PayvandException) { _ui.update { it.copy(error = e) } }
            finally { _ui.update { it.copy(loading = false) } }
        }
    }

    private fun validEmail(s: AuthUi): Boolean {
        val ok = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$").matches(s.email)
        if (!ok) _ui.update { it.copy(error = PayvandException(PayvandException.Code.INVALID_EMAIL)) }
        return ok
    }

    private fun validPassword(s: AuthUi): Boolean {
        val ok = s.password.length >= 8
        if (!ok) _ui.update { it.copy(error = PayvandException(PayvandException.Code.WEAK_PASSWORD)) }
        return ok
    }

    private fun startCooldown() {
        viewModelScope.launch {
            for (i in 60 downTo 0) { _ui.update { it.copy(resendIn = i) }; delay(1000) }
        }
    }

    fun signIn() { if (validEmail(_ui.value)) run { s ->
        try { api.signIn(s.email, s.password) }
        catch (e: PayvandException) {
            if (e.code == PayvandException.Code.EMAIL_NOT_CONFIRMED) {
                runCatching { api.resendSignUpCode(s.email) }
                _ui.update { it.copy(step = AuthStep.SIGN_UP_CODE, code = "") }; startCooldown()
            } else throw e
        }
    } }

    fun signUp() { if (validEmail(_ui.value) && validPassword(_ui.value)) run { s ->
        if (api.signUp(s.email, s.password) == SignUpResult.NeedsEmailCode) {
            _ui.update { it.copy(step = AuthStep.SIGN_UP_CODE, code = "") }; startCooldown()
        }
    } }

    fun confirmSignUp() = run { s -> api.confirmSignUp(s.email, s.code) }

    fun resend() = run { s ->
        if (s.step == AuthStep.SIGN_UP_CODE) api.resendSignUpCode(s.email) else api.requestPasswordRecovery(s.email)
        startCooldown()
    }

    fun requestRecovery() { if (validEmail(_ui.value)) run { s ->
        api.requestPasswordRecovery(s.email)
        _ui.update { it.copy(step = AuthStep.RECOVERY_CODE, code = "", password = "") }; startCooldown()
    } }

    fun confirmRecovery() { if (validPassword(_ui.value)) run { s -> api.confirmPasswordRecovery(s.email, s.code, s.password) } }
}
