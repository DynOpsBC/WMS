package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier

/** Existing thermal label actions retain the configured BC label design. */
@Composable
fun LabelsModule() {
    var tab by remember { mutableStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Bin Etiketi") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Ürün Etiketi") })
        }
        Box(Modifier.weight(1f)) {
            if (tab == 0) BinInquiryModule(labelsOnly = true) else ItemInquiryModule(labelsOnly = true)
        }
    }
}
