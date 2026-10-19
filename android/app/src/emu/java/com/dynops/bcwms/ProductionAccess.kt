package com.dynops.bcwms

import android.content.Context

/** This customer has no staged module access restriction. */
@Suppress("UNUSED_PARAMETER")
internal fun canOpenOperationalScreen(context: Context, screen: Screen): Boolean = true
