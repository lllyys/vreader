// Purpose: feature #106 WI-1 — the vreader Android app's entry Activity.
// A minimal Compose shell with the empty "Library" screen; WI-3/WI-4 fill the
// library list + reader. Kept deliberately tiny so the app-shell PR is the
// foundational slice (no persistence/reader/import yet).
//
// @coordinates-with: AndroidManifest.xml (the launcher activity),
//   dev-docs/plans/20260618-feature-106-android-foundation-bar.md (WI-1)
package com.vreader.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { LibraryScreen() } }
    }
}

/** The empty Library screen — WI-3 replaces the placeholder with the book list. */
@Composable
fun LibraryScreen() {
    Scaffold { innerPadding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = "Library")
        }
    }
}
