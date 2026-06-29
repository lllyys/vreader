package com.vreader.app.reader.foliate

import com.vreader.app.reader.foliate.FoliateAssetServer.SHELL_ORIGIN
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #126 WI-3 — the pure WebView security decisions. */
class FoliateBridgePolicyTest {

    // --- isTrustedMessage: only the main frame of the shell origin ---

    @Test fun trustedMessage_onlyMainFrameOfShellOrigin() {
        assertTrue(FoliateBridgePolicy.isTrustedMessage(SHELL_ORIGIN, true))
    }

    @Test fun trustedMessage_rejectsSubFrame() {
        assertFalse(FoliateBridgePolicy.isTrustedMessage(SHELL_ORIGIN, false))
    }

    @Test fun trustedMessage_rejectsForeignOrigin() {
        assertFalse(FoliateBridgePolicy.isTrustedMessage("https://evil.example", true))
        assertFalse(FoliateBridgePolicy.isTrustedMessage("https://appassets.androidplatform.net.evil.com", true))
        assertFalse(FoliateBridgePolicy.isTrustedMessage(null, true))
    }

    // --- isSameOrigin: exact origin or a path under it; sibling-host bypass blocked ---

    @Test fun sameOrigin_exactAndUnderPath() {
        assertTrue(FoliateBridgePolicy.isSameOrigin(SHELL_ORIGIN))
        assertTrue(FoliateBridgePolicy.isSameOrigin("$SHELL_ORIGIN/assets/foliate/reader.html"))
    }

    @Test fun sameOrigin_rejectsSiblingHostAndUserinfoBypass() {
        assertFalse(FoliateBridgePolicy.isSameOrigin("https://appassets.androidplatform.net.evil.com/x"))
        assertFalse(FoliateBridgePolicy.isSameOrigin("https://appassets.androidplatform.net@evil.com/x"))
        assertFalse(FoliateBridgePolicy.isSameOrigin("https://evil.example/x"))
        assertFalse(FoliateBridgePolicy.isSameOrigin(null))
    }

    // --- isAllowedNavigation: only within the shell origin ---

    @Test fun navigation_allowsShellOrigin() {
        assertTrue(FoliateBridgePolicy.isAllowedNavigation(SHELL_ORIGIN))
        assertTrue(FoliateBridgePolicy.isAllowedNavigation("$SHELL_ORIGIN/assets/foliate/reader.html"))
        assertTrue(FoliateBridgePolicy.isAllowedNavigation("$SHELL_ORIGIN/book/book"))
    }

    @Test fun navigation_blocksEverythingElse() {
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("https://evil.example/x"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("javascript:alert(1)"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("data:text/html,<script>1</script>"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("blob:$SHELL_ORIGIN/abc")) // top-level blob nav
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("file:///etc/hosts"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation("https://appassets.androidplatform.net.evil.com/x"))
        assertFalse(FoliateBridgePolicy.isAllowedNavigation(null))
    }

    // --- shouldBlockRequest: block remote http(s); allow same-origin; pass blob/data through ---

    @Test fun request_allowsSameOriginAssetsAndBook() {
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("$SHELL_ORIGIN/assets/foliate/foliate-bundle.js"))
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("$SHELL_ORIGIN/book/book"))
    }

    @Test fun request_blocksRemoteHttpResources() {
        // passive exfil: remote img / css url() / font / media a hostile book could trigger w/o script
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("https://tracker.example/pixel.gif"))
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("http://insecure.example/a.css"))
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("https://appassets.androidplatform.net.evil.com/x.png"))
        assertTrue(FoliateBridgePolicy.shouldBlockRequest("HTTPS://Tracker.Example/p")) // case-insensitive
    }

    @Test fun request_passesNonHttpThrough() {
        // blob:/data: section docs are handled internally by the WebView; the loader/WebView own these.
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("blob:$SHELL_ORIGIN/uuid"))
        assertFalse(FoliateBridgePolicy.shouldBlockRequest("data:image/png;base64,AAAA"))
        assertFalse(FoliateBridgePolicy.shouldBlockRequest(null))
    }
}
