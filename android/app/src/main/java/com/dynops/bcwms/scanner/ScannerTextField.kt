package com.dynops.bcwms.scanner

import android.text.InputType
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.editableText
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.focused
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.widget.doAfterTextChanged

/** A real editable InputConnection accepts scanner IME commits and key events.
 * showSoftInputOnFocus=false hides manual keyboard entry without making scanner
 * input read-only. Keyboard-wedge data cannot prove physical scanner provenance.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ScannerTextField(
    label: String,
    enabled: Boolean,
    focusRequester: FocusRequester,
    interactionSource: MutableInteractionSource,
    modifier: Modifier = Modifier,
    onScanned: (String) -> Unit,
) {
    var editor by remember { mutableStateOf<EditText?>(null) }
    var buffer by remember { mutableStateOf("") }
    var nativeFocused by remember { mutableStateOf(false) }
    var focusInteraction by remember { mutableStateOf<FocusInteraction.Focus?>(null) }
    val currentOnScanned by rememberUpdatedState(onScanned)
    val currentEnabled by rememberUpdatedState(enabled)
    val textColor = MaterialTheme.colorScheme.onSurface.toArgb()
    val keyboard = LocalSoftwareKeyboardController.current
    val keyboardHeight = WindowInsets.ime.getBottom(LocalDensity.current)
    // Compose may finish opening the previous quantity editor's keyboard after
    // native focus changed. Observe the actual IME instead of racing that show.
    LaunchedEffect(nativeFocused, keyboardHeight) {
        if (nativeFocused && keyboardHeight > 0) keyboard?.hide()
    }
    val submit by rememberUpdatedState<() -> Unit>({
        val raw = editor?.text?.toString().orEmpty().trim()
        editor?.text?.clear()
        if (currentEnabled && raw.isNotBlank()) currentOnScanned(raw)
    })
    LaunchedEffect(enabled) { if (!enabled) editor?.text?.clear() }
    DisposableEffect(interactionSource) {
        onDispose { focusInteraction?.let { interactionSource.tryEmit(FocusInteraction.Unfocus(it)) } }
    }
    Box(
        modifier.heightIn(min = 56.dp)
            .pointerInput(enabled) { detectTapGestures { if (enabled) editor?.requestFocus() } }
            .semantics(mergeDescendants = true) {
                editableText = AnnotatedString(buffer)
                focused = nativeFocused
                if (!enabled) disabled()
                onClick { if (enabled) editor?.requestFocus(); enabled }
            },
    ) {
        OutlinedTextFieldDefaults.DecorationBox(
            value = buffer,
            enabled = enabled,
            singleLine = true,
            visualTransformation = VisualTransformation.None,
            interactionSource = interactionSource,
            label = { Text(label) },
            innerTextField = {
                AndroidView(
                    modifier = Modifier.fillMaxWidth().heightIn(min = 24.dp).focusRequester(focusRequester),
                    factory = { context ->
                        EditText(context).apply {
                            hint = ""
                            contentDescription = label
                            setSingleLine(true)
                            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                            imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
                            showSoftInputOnFocus = false
                            isLongClickable = false
                            isFocusable = true
                            isFocusableInTouchMode = true
                            setPadding(0, 0, 0, 0)
                            background = null
                            textSize = 16f
                            setTextColor(textColor)
                            setOnFocusChangeListener { _, hasFocus ->
                                nativeFocused = hasFocus
                                focusInteraction?.let { interactionSource.tryEmit(FocusInteraction.Unfocus(it)) }
                                focusInteraction = if (hasFocus) FocusInteraction.Focus().also { interactionSource.tryEmit(it) } else null
                                // The quantity editor may already have opened the IME before
                                // the modal finished expanding. Suppressing a new keyboard is
                                // not enough: also close that previous editor's keyboard.
                                if (hasFocus) post {
                                    if (isFocused) {
                                        context.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                                            .hideSoftInputFromWindow(windowToken, 0)
                                    }
                                }
                            }
                            setOnEditorActionListener { _, action, event ->
                                if (action == EditorInfo.IME_ACTION_DONE || event?.keyCode == KeyEvent.KEYCODE_ENTER) {
                                    if (event == null || event.action == KeyEvent.ACTION_DOWN) {
                                        submit()
                                    }
                                    true
                                } else false
                            }
                            setOnKeyListener { _, code, event ->
                                if (currentEnabled && code in listOf(KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_TAB)) {
                                    if (event.action == KeyEvent.ACTION_DOWN) {
                                        submit()
                                    }
                                    true // The suffix must not move focus or activate warehouse confirmation.
                                } else false
                            }
                            doAfterTextChanged { text ->
                                buffer = text?.toString().orEmpty()
                                if (buffer.endsWith('\r') || buffer.endsWith('\n') || buffer.endsWith('\t')) submit()
                            }
                            editor = this
                        }
                    },
                    // The label is a workflow step ("1. raf" → "2. palet"); keep the native description in sync.
                    update = { it.isEnabled = enabled; it.setTextColor(textColor); it.contentDescription = label },
                )
            },
        )
    }
    if (enabled && buffer.isNotBlank()) {
        TextButton(onClick = { submit(); editor?.requestFocus() }) { Text("Okunan Paleti Doğrula") }
    }
}

/**
 * Kitoko (22 Eki 2026): değer bağlı, klavyesiz okutma alanı. Yerel EditText
 * (showSoftInputOnFocus=false) giriş bağlantısını açık tutar: klavye-kama
 * tarayıcı metni doğrudan yazar, ekran klavyesi hiç açılmaz (aç-kapa titremesi
 * yok). [manualKeyboard] true iken klavye açılır ve elle yazılır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun KeyboardlessTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    enabled: Boolean,
    focusRequester: FocusRequester,
    interactionSource: MutableInteractionSource,
    manualKeyboard: Boolean,
    onSubmit: (String) -> Unit,
    modifier: Modifier = Modifier,
    trailingIcon: (@Composable () -> Unit)? = null,
) {
    var editor by remember { mutableStateOf<EditText?>(null) }
    var focusInteraction by remember { mutableStateOf<FocusInteraction.Focus?>(null) }
    val currentOnValueChange by rememberUpdatedState(onValueChange)
    val currentOnSubmit by rememberUpdatedState(onSubmit)
    val currentEnabled by rememberUpdatedState(enabled)
    val currentManual by rememberUpdatedState(manualKeyboard)
    val textColor = MaterialTheme.colorScheme.onSurface.toArgb()
    DisposableEffect(interactionSource) {
        onDispose { focusInteraction?.let { interactionSource.tryEmit(FocusInteraction.Unfocus(it)) } }
    }
    LaunchedEffect(manualKeyboard) {
        val e = editor ?: return@LaunchedEffect
        val imm = e.context.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
        e.showSoftInputOnFocus = manualKeyboard
        if (manualKeyboard) {
            e.requestFocus()
            e.post { imm.showSoftInput(e, 0) }
        } else if (e.isFocused) imm.hideSoftInputFromWindow(e.windowToken, 0)
    }
    Box(
        modifier.heightIn(min = 56.dp)
            .pointerInput(enabled) { detectTapGestures { if (enabled) editor?.requestFocus() } }
            .semantics(mergeDescendants = true) {
                editableText = AnnotatedString(value)
                if (!enabled) disabled()
                onClick { if (enabled) editor?.requestFocus(); enabled }
            },
    ) {
        OutlinedTextFieldDefaults.DecorationBox(
            value = value,
            enabled = enabled,
            singleLine = true,
            visualTransformation = VisualTransformation.None,
            interactionSource = interactionSource,
            label = { Text(label) },
            trailingIcon = trailingIcon,
            innerTextField = {
                AndroidView(
                    modifier = Modifier.fillMaxWidth().heightIn(min = 24.dp).focusRequester(focusRequester),
                    factory = { context ->
                        EditText(context).apply {
                            contentDescription = label
                            setSingleLine(true)
                            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                            imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
                            showSoftInputOnFocus = currentManual
                            isFocusable = true
                            isFocusableInTouchMode = true
                            setPadding(0, 0, 0, 0)
                            background = null
                            textSize = 16f
                            setTextColor(textColor)
                            setText(value)
                            setOnFocusChangeListener { _, hasFocus ->
                                focusInteraction?.let { interactionSource.tryEmit(FocusInteraction.Unfocus(it)) }
                                focusInteraction = if (hasFocus) FocusInteraction.Focus().also { interactionSource.tryEmit(it) } else null
                                // Önceki alanın (ör. miktar penceresi) açık bıraktığı klavyeyi kapat.
                                if (hasFocus && !currentManual) post {
                                    if (isFocused) context.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                                        .hideSoftInputFromWindow(windowToken, 0)
                                }
                            }
                            setOnEditorActionListener { _, action, event ->
                                if (action == EditorInfo.IME_ACTION_DONE || event?.keyCode == KeyEvent.KEYCODE_ENTER) {
                                    if (currentEnabled && (event == null || event.action == KeyEvent.ACTION_DOWN)) currentOnSubmit(text.toString())
                                    true
                                } else false
                            }
                            setOnKeyListener { _, code, event ->
                                if (code in listOf(KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_TAB)) {
                                    if (currentEnabled && event.action == KeyEvent.ACTION_DOWN) currentOnSubmit(text.toString())
                                    true // Sonek odağı kaydırmasın.
                                } else false
                            }
                            doAfterTextChanged { text ->
                                val raw = text?.toString().orEmpty()
                                val ended = raw.endsWith('\r') || raw.endsWith('\n') || raw.endsWith('\t')
                                val clean = raw.trimEnd('\r', '\n', '\t')
                                if (ended) { setText(clean); setSelection(clean.length) }
                                if (clean != (tag as? String)) { tag = clean; currentOnValueChange(clean) }
                                if (ended && currentEnabled) currentOnSubmit(clean)
                            }
                            tag = value
                            editor = this
                        }
                    },
                    update = {
                        it.isEnabled = enabled
                        it.setTextColor(textColor)
                        it.contentDescription = label
                        if (it.text.toString() != value) {
                            it.tag = value
                            it.setText(value)
                            it.setSelection(value.length)
                        }
                    },
                )
            },
        )
    }
}
