package com.dynops.bcwms.feature

import android.content.Context
import com.dynops.bcwms.BcApi

/** Explicit selection wins. Employee numbers are resolved only from the active company's list. */
internal fun mteOptionsWithOperator(
    options: MteOptions,
    operatorName: String,
    employees: List<Pair<String, String>>,
    documentPrinter: Boolean,
): MteOptions {
    if (options.inspectorEmployeeNo.isNotBlank()) return options
    val name = operatorName.trim()
    require(name.isNotBlank()) { "Giriş yapan kullanıcı belirlenemedi. PIN ile yeniden giriş yapın." }
    val matches = employees.filter { it.second.trim().equals(name, ignoreCase = true) }
    val employeeNo = matches.singleOrNull()?.first?.trim().orEmpty()
    // Customer PDF report 60150 only accepts a real Employee No. (Code[20]).
    // The installed ZPL builder also accepts a literal name when no Employee matches.
    require(!documentPrinter || employeeNo.isNotBlank()) {
        "PIN kullanıcısının bu şirketteki çalışan kaydı bulunamadı veya birden fazla eşleşme var. PDF MTE için Giriş Yapan seçin; etiket yazıcısında kullanıcı adı otomatik yazılır."
    }
    return options.copy(inspectorEmployeeNo = employeeNo.ifBlank { name })
}

internal fun mteOptionsForCurrentOperator(
    context: Context, options: MteOptions, employees: List<Pair<String, String>>, companyScope: String,
): MteOptions {
    check(TerminalSession.authenticated(context) && TerminalSession.scope(context) == companyScope) {
        "Oturum süresi doldu veya şirket değişti. PIN ile yeniden giriş yapın."
    }
    return mteOptionsWithOperator(
        options, BcApi.getOperatorDisplayName(context), employees,
        documentPrinter = getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT).isNotBlank(),
    )
}

internal const val MTE_EMPTY_FIELDS_HINT =
    "Giriş Yapan boşsa PIN ile giriş yapan kullanıcı yazılır. Diğer boş alanlar U.Y olarak çıkar. Tarihler gg.aa.yyyy."

internal const val MTE_EMPTY_FIELDS_BUTTON = "Diğer alanları boş bırak, yazdır"

internal fun mteOptionsWithoutExtraFields(inspector: String): MteOptions = MteOptions(inspectorEmployeeNo = inspector)
