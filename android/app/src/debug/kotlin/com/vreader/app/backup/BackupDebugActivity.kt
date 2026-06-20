// Purpose: feature #114 WI-2 (#110 Phase 3) — DEBUG-ONLY launcher for the backup/restore UI,
// so the designed surfaces are viewable on the emulator WITHOUT a production entry point
// (Gate-2 High-1/High-2: no production wiring, no fake data in release). In src/debug, hosts
// BackupRestoreScreen against the PreviewBackupService. Reachable via:
//   adb shell am start -n com.vreader.app/com.vreader.app.backup.BackupDebugActivity
package com.vreader.app.backup

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.compose.runtime.getValue

class BackupDebugActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val factory = viewModelFactory {
            initializer { BackupViewModel(PreviewBackupService(), activeServerId = "nas") }
        }
        setContent {
            BackupSurface {
                val vm: BackupViewModel = viewModel(factory = factory)
                val state by vm.state.collectAsStateWithLifecycle()
                BackupRestoreScreen(
                    state = state,
                    onBack = { finish() },
                    onBackUpNow = { vm.backUpNow() },
                    onErrorCta = { cause ->
                        // Route each error CTA to its designed action (Gate-4).
                        when (cause) {
                            WebDavError.auth401 -> vm.openServerSettings()
                            WebDavError.notFound404 -> vm.backUpNow()
                            WebDavError.offline, WebDavError.timeout -> vm.loadBackups()
                        }
                    },
                )
            }
        }
    }
}
