package com.dynops.bcwms.ui

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll

/**
 * A screen whose header (buttons, search, status, titles) scrolls away together with the
 * list below it, so small terminal screens are not left with a narrow list strip.
 *
 * Swiping up first moves the header off the screen and then scrolls the list; swiping down
 * scrolls the list back to its top and then brings the header back. The list receives
 * [content]'s `fullScreenList` modifier instead of `Modifier.weight(1f)`: at most the visible
 * height, shorter when it has only a few rows.
 */
@Composable
fun ScrollAwayColumn(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.(fullScreenList: Modifier) -> Unit,
) {
    val outer = rememberScrollState()
    val headerFirst = remember(outer) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Content moving up: hide the header before the list itself scrolls.
                if (available.y >= 0f || !outer.canScrollForward) return Offset.Zero
                val consumed = outer.dispatchRawDelta(-available.y)
                return Offset(0f, -consumed)
            }
        }
    }
    BoxWithConstraints(modifier) {
        val visibleHeight = maxHeight
        Column(Modifier.fillMaxWidth().nestedScroll(headerFirst).verticalScroll(outer)) {
            content(Modifier.heightIn(max = visibleHeight))
        }
    }
}
