// Purpose: feature #114 WI-1 (#110 Phase 3) — the backup/restore state holder. Drives the
// designed BackupUiState from the UI-oriented BackupService, with the Gate-2 concurrency rules:
// ONE active backup job (repeated "Back Up Now" taps coalesce), a load that cancels its prior
// in-flight load (no stale list overwrites a newer one), and one-shot effects via a Channel
// (not the durable StateFlow). Constructor-injected service + dispatcher so it's JVM-testable.
package com.vreader.app.backup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class BackupViewModel(
    private val service: BackupService,
    private val activeServerId: String?,
    private val dispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {

    private val _state = MutableStateFlow(BackupUiState())
    val state: StateFlow<BackupUiState> = _state.asStateFlow()

    private val _events = Channel<BackupEvent>(Channel.BUFFERED)
    val events: Flow<BackupEvent> = _events.receiveAsFlow()

    // One active long job apiece — a second tap while running is ignored (coalesced).
    private var loadJob: Job? = null
    private var backupJob: Job? = null
    // Monotonic load id: a terminal write from a superseded load is dropped even if its
    // service call wasn't cooperatively cancellable (Gate-4).
    private var loadRequestId = 0

    init {
        loadActiveServer()
        loadBackups()
    }

    private fun loadActiveServer() {
        viewModelScope.launch(dispatcher) {
            val id = activeServerId ?: return@launch
            _state.update { it.copy(activeServer = service.listServers().firstOrNull { s -> s.id == id }) }
        }
    }

    /** Read the server's backups. Cancels a prior in-flight load so a stale result can't
     *  overwrite a newer one (Gate-2 concurrency). */
    fun loadBackups() {
        loadJob?.cancel()
        val requestId = ++loadRequestId
        loadJob = viewModelScope.launch(dispatcher) {
            _state.update { it.copy(list = BackupListUi.Loading) }
            val id = activeServerId
            if (id == null) {
                if (requestId == loadRequestId) _state.update { it.copy(list = BackupListUi.Error(WebDavError.notFound404)) }
                return@launch
            }
            val result = service.listBackups(id)
            // Drop a superseded / cancelled load's write — newer state wins.
            ensureActive()
            if (requestId != loadRequestId) return@launch
            _state.update {
                when (result) {
                    is BackupListResult.Ok ->
                        it.copy(list = if (result.backups.isEmpty()) BackupListUi.Empty else BackupListUi.Idle(result.backups))
                    is BackupListResult.Error -> it.copy(list = BackupListUi.Error(result.cause))
                }
            }
        }
    }

    /** "Back Up Now". Coalesces repeated taps: a second call while a backup runs is a no-op. */
    fun backUpNow() {
        if (backupJob?.isActive == true) return
        val id = activeServerId ?: return
        backupJob = viewModelScope.launch(dispatcher) {
            var failed = false
            try {
                service.startBackup(id).collect { p ->
                    _state.update { it.copy(syncing = Syncing(p.done, p.total)) }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                failed = true
                _events.send(BackupEvent.Toast("Backup failed"))
            } finally {
                // Always clear the in-progress state, even on failure (Gate-4) — never leave
                // the button stuck spinning.
                _state.update { it.copy(syncing = null) }
            }
            if (!failed) loadBackups()
        }
    }

    /** The 401 error block's CTA — surface a one-shot "open server settings" effect. */
    fun openServerSettings() {
        viewModelScope.launch { _events.send(BackupEvent.OpenServerSettings) }
    }
}
