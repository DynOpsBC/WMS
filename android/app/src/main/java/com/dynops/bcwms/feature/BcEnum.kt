package com.dynops.bcwms.feature

/**
 * BC OData enum literal constants used in mobile composite-key strings.
 *
 * Hardcoding these inside calling code (e.g. "Put-away" in PutAwayShipModules) led to 404s
 * whenever the BC OData representation changed casing or spelling. Centralising them here
 * matches the way BC serialises Option/Enum members over OData v4 — exactly as published
 * by the page's source table.
 */
object BcEnum {

    /** Warehouse Activity Header.Type enum values as serialised over OData. */
    object WhseActivityType {
        const val PICK = "Pick"
        const val PUT_AWAY = "Put-away"   // Hyphen + lowercase 'a' matches BC's option caption.
        const val MOVEMENT = "Movement"
        const val INVT_PUT_AWAY = "Invt. Put-away"
        const val INVT_PICK = "Invt. Pick"
        const val INVT_MOVEMENT = "Invt. Movement"
    }

    /** Assembly Header.Document Type enum values. */
    object AssemblyDocType {
        const val QUOTE = "Quote"
        const val ORDER = "Order"
        const val BLANKET = "Blanket Order"
    }

    /** Prod. Order header status values used by Order Components / Routing Lines composite keys. */
    object ProdOrderStatus {
        const val SIMULATED = "Simulated"
        const val PLANNED = "Planned"
        const val FIRM_PLANNED = "Firm Planned"
        const val RELEASED = "Released"
        const val FINISHED = "Finished"
    }
}
