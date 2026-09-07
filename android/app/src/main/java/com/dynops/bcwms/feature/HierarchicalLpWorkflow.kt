package com.dynops.bcwms.feature

/** This optional customer extension is not part of the common WMS AL package. */
internal fun hierarchicalLpApiAvailable(metadata: String): Boolean {
    val actions = Regex("""<(?:\w+:)?Action\b[^>]*\bName=["']([^"']+)["']""")
        .findAll(metadata).map { it.groupValues[1].lowercase() }.toSet()
    return actions.containsAll(setOf("attachchild", "detachchild", "gethierarchy", "movehierarchy", "completeandprint", "reprinthierarchylabel"))
}
