package com.dynops.bcwms.ui

/** JSON/BC quantities cannot represent NaN or infinity, including exponent overflow. */
internal fun String.toFiniteDoubleOrNull(): Double? = toDoubleOrNull()?.takeIf { it.isFinite() }
