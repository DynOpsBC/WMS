package com.dynops.bcwms.feature

import android.content.Context

@Suppress("UNUSED_PARAMETER")
internal fun mteOptionsForCurrentOperator(context: Context, options: MteOptions, employees: List<Pair<String, String>>, companyScope: String): MteOptions = options

internal const val MTE_EMPTY_FIELDS_HINT = "Boş bırakılan alanlar etikette U.Y olarak çıkar. Tarihler gg.aa.yyyy."
internal const val MTE_EMPTY_FIELDS_BUTTON = "Alanları boş bırak, yazdır"

@Suppress("UNUSED_PARAMETER")
internal fun mteOptionsWithoutExtraFields(inspector: String): MteOptions = MteOptions()
