package com.dynops.bcwms.feature

import org.junit.Assert.*
import org.junit.Test

class HierarchicalLpWorkflowTest {
    private val actions = listOf("attachChild", "detachChild", "getHierarchy", "moveHierarchy", "completeAndPrint", "reprintHierarchyLabel")

    @Test
    fun `common or partially upgraded BC package cannot enable unsupported hierarchy writes`() {
        assertFalse(hierarchicalLpApiAvailable("<Schema><Action Name=\"nest\"/></Schema>"))
        assertFalse(hierarchicalLpApiAvailable(actions.dropLast(1).joinToString("") { "<Action Name=\"$it\"/>" }))
    }

    @Test
    fun `matching action names in properties or an error response are not capabilities`() {
        assertFalse(hierarchicalLpApiAvailable(actions.joinToString(" ")))
        assertFalse(hierarchicalLpApiAvailable(actions.joinToString("") { "<Property Name=\"$it\"/>" }))
    }

    @Test
    fun `complete customer extension enables hierarchy operations`() {
        assertTrue(hierarchicalLpApiAvailable(actions.joinToString("") { "<edm:Action IsBound=\"true\" Name=\"$it\"/>" }))
    }
}
