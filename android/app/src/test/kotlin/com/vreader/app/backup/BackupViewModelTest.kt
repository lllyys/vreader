package com.vreader.app.backup

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Feature #114 WI-1 — the backup-screen state machine + the Gate-2 concurrency rules, driven
 * by a fake BackupService (the UI seam). Pure JVM (no Room): StandardTestDispatcher as both
 * Main and the injected dispatcher.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BackupViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = kotlinx.coroutines.Dispatchers.setMain(dispatcher)
    @After fun tearDown() = kotlinx.coroutines.Dispatchers.resetMain()

    private class FakeService(
        private val backupsResult: BackupListResult,
        private val servers: List<ServerSummary> = emptyList(),
    ) : BackupService {
        var startBackupCount = 0
        override suspend fun listServers() = servers
        override suspend fun testConnection(draft: ServerDraft) = TestResult.Ok("")
        override suspend fun listBackups(serverId: String) = backupsResult
        override fun startBackup(serverId: String): Flow<BackupProgress> = flow {
            startBackupCount++
            emit(BackupProgress(1, 3))
            emit(BackupProgress(3, 3))
        }
        override suspend fun loadManifest(backupId: String) = emptyList<ManifestBook>()
        override fun restore(backupId: String, selection: Set<String>): Flow<RestoreProgress> = emptyFlow()
        override suspend fun retryBook(backupId: String, bookId: String) = BookRestoreResult.restored
    }

    private val oneBackup = listOf(
        BackupSummary("b1", "Today, 9:14 AM", "4.2 MB", "Pixel 8", 12, latest = true),
    )

    @Test fun loadBackups_populated_isIdle() = runTest(dispatcher) {
        val vm = BackupViewModel(FakeService(BackupListResult.Ok(oneBackup)), "nas", dispatcher)
        advanceUntilIdle()
        val list = vm.state.value.list
        assertTrue(list is BackupListUi.Idle)
        assertEquals(1, (list as BackupListUi.Idle).backups.size)
    }

    @Test fun loadBackups_empty_isEmpty() = runTest(dispatcher) {
        val vm = BackupViewModel(FakeService(BackupListResult.Ok(emptyList())), "nas", dispatcher)
        advanceUntilIdle()
        assertTrue(vm.state.value.list is BackupListUi.Empty)
    }

    @Test fun loadBackups_error_carriesCause() = runTest(dispatcher) {
        val vm = BackupViewModel(FakeService(BackupListResult.Error(WebDavError.auth401)), "nas", dispatcher)
        advanceUntilIdle()
        val list = vm.state.value.list
        assertTrue(list is BackupListUi.Error)
        assertEquals(WebDavError.auth401, (list as BackupListUi.Error).cause)
    }

    @Test fun loadBackups_noActiveServer_is404() = runTest(dispatcher) {
        val vm = BackupViewModel(FakeService(BackupListResult.Ok(oneBackup)), activeServerId = null, dispatcher)
        advanceUntilIdle()
        val list = vm.state.value.list
        assertTrue(list is BackupListUi.Error)
        assertEquals(WebDavError.notFound404, (list as BackupListUi.Error).cause)
    }

    @Test fun backUpNow_runsThenClearsSyncing_andReloads() = runTest(dispatcher) {
        val svc = FakeService(BackupListResult.Ok(oneBackup))
        val vm = BackupViewModel(svc, "nas", dispatcher)
        advanceUntilIdle()
        vm.backUpNow()
        advanceUntilIdle()
        assertEquals(1, svc.startBackupCount)
        assertNull("syncing cleared when the backup completes", vm.state.value.syncing)
        assertTrue(vm.state.value.list is BackupListUi.Idle)
    }

    @Test fun backUpNow_doubleTap_coalescesToOneJob() = runTest(dispatcher) {
        val svc = FakeService(BackupListResult.Ok(oneBackup))
        val vm = BackupViewModel(svc, "nas", dispatcher)
        advanceUntilIdle()
        vm.backUpNow()
        vm.backUpNow()   // second tap while the first job is active → coalesced
        advanceUntilIdle()
        assertEquals("only one backup job runs", 1, svc.startBackupCount)
    }

    /** A service whose listBackups/startBackup suspend on caller-controlled gates, to prove the
     *  cancel/coalesce concurrency rules deterministically (Gate-4). */
    private class GatedService(
        private val listGates: List<kotlinx.coroutines.CompletableDeferred<BackupListResult>>,
        private val backupGate: kotlinx.coroutines.CompletableDeferred<Unit>? = null,
    ) : BackupService {
        var listCall = 0
        var startBackupCount = 0
        override suspend fun listServers() = emptyList<ServerSummary>()
        override suspend fun testConnection(draft: ServerDraft) = TestResult.Ok("")
        override suspend fun listBackups(serverId: String) = listGates[listCall++].await()
        override fun startBackup(serverId: String): Flow<BackupProgress> = flow {
            startBackupCount++
            emit(BackupProgress(1, 3))
            backupGate?.await()
            emit(BackupProgress(3, 3))
        }
        override suspend fun loadManifest(backupId: String) = emptyList<ManifestBook>()
        override fun restore(backupId: String, selection: Set<String>): Flow<RestoreProgress> = emptyFlow()
        override suspend fun retryBook(backupId: String, bookId: String) = BookRestoreResult.restored
    }

    @Test fun loadBackups_staleResult_doesNotOverwriteNewer() = runTest(dispatcher) {
        val gInit = kotlinx.coroutines.CompletableDeferred<BackupListResult>()
        val gA = kotlinx.coroutines.CompletableDeferred<BackupListResult>()
        val gB = kotlinx.coroutines.CompletableDeferred<BackupListResult>()
        val svc = GatedService(listOf(gInit, gA, gB))
        val vm = BackupViewModel(svc, "nas", dispatcher)
        gInit.complete(BackupListResult.Ok(emptyList()))   // settle the init load
        advanceUntilIdle()

        vm.loadBackups()         // load A
        advanceUntilIdle()       // A suspended on gA
        vm.loadBackups()         // load B — cancels A
        advanceUntilIdle()       // B suspended on gB
        gA.complete(BackupListResult.Ok(oneBackup))                 // stale A result (A cancelled)
        gB.complete(BackupListResult.Ok(oneBackup + oneBackup[0].copy(id = "b2")))  // B result (2)
        advanceUntilIdle()

        val list = vm.state.value.list
        assertTrue("newer load B wins, stale A dropped", list is BackupListUi.Idle)
        assertEquals(2, (list as BackupListUi.Idle).backups.size)
    }

    @Test fun backUpNow_whileFirstSuspended_coalesces() = runTest(dispatcher) {
        val gInit = kotlinx.coroutines.CompletableDeferred<BackupListResult>().apply { complete(BackupListResult.Ok(oneBackup)) }
        val gReload = kotlinx.coroutines.CompletableDeferred<BackupListResult>().apply { complete(BackupListResult.Ok(oneBackup)) }
        val backupGate = kotlinx.coroutines.CompletableDeferred<Unit>()
        val svc = GatedService(listOf(gInit, gReload), backupGate)
        val vm = BackupViewModel(svc, "nas", dispatcher)
        advanceUntilIdle()

        vm.backUpNow()           // job 1 starts, suspends mid-flow on backupGate
        advanceUntilIdle()
        assertTrue("backing up", vm.state.value.syncing != null)
        vm.backUpNow()           // second tap while suspended → coalesced
        advanceUntilIdle()
        backupGate.complete(Unit)
        advanceUntilIdle()
        assertEquals("only one backup job ran", 1, svc.startBackupCount)
        assertNull(vm.state.value.syncing)
    }

    @Test fun openServerSettings_emitsOneShotEvent() = runTest(dispatcher) {
        val vm = BackupViewModel(FakeService(BackupListResult.Ok(oneBackup)), "nas", dispatcher)
        advanceUntilIdle()
        val received = mutableListOf<BackupEvent>()
        val collector = launch(dispatcher) { vm.events.collect { received.add(it) } }
        vm.openServerSettings()
        advanceUntilIdle()
        collector.cancel()
        assertEquals(1, received.size)
        assertTrue(received[0] is BackupEvent.OpenServerSettings)
    }
}
