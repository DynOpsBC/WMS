package com.dynops.bcwms.layout

/**
 * Terminal Ekran Tasarımcısı kataloğu. Anahtarlar BC "DOPSWHS Terminal Layout Mgt"
 * (codeunit 72384) kataloğu ile BİREBİR aynıdır; birini değiştirirken diğerini de
 * değiştirin. Varsayılan sıralar bugünkü ana menü sırasıdır (AppRoot.HomeCategories).
 *
 * Ana menü kutuları Screen enum adına göre eşlenir (enum'a bağımlı değildir):
 * böylece yalnız bazı sürümlerde olan ekranlar (ör. Kitoko/EMU "Labels") da aynı
 * katalogla çalışır.
 */
object TerminalLayoutCatalog {
    const val VERSION = "1"
    const val HOME = "HOME"

    /** Screen enum adı → katalog anahtarı ve varsayılan sıra. */
    private val tiles: List<Triple<String, String, Int>> = listOf(
        Triple("Receiving", "RECEIVING", 10),
        Triple("PutAway", "PUTAWAY", 20),
        Triple("Picking", "PICKING", 30),
        Triple("Packing", "PACKING", 40),
        Triple("Shipping", "SHIPPING", 50),
        Triple("LicensePlates", "LICENSE_PLATES", 60),
        Triple("HierarchicalLP", "HIERARCHICAL_LP", 70),
        Triple("AdHocMove", "ADHOC_MOVE", 80),
        Triple("DirectedMove", "DIRECTED_MOVE", 90),
        Triple("Count", "COUNT", 100),
        Triple("CountV2", "COUNT_V2", 110),
        // Kitoko (22 Eki 2026): İlk Sayım kutusu (yalnız Kitoko menüsünde).
        Triple("FirstCount", "FIRST_COUNT", 115),
        Triple("Production", "PRODUCTION", 120),
        Triple("Subcontracting", "SUBCONTRACTING", 130),
        Triple("Assembly", "ASSEMBLY", 140),
        Triple("Quality", "QUALITY", 150),
        Triple("QualityMgmt", "QUALITY_MGMT", 160),
        Triple("ItemInquiry", "ITEM_INQUIRY", 170),
        Triple("Labels", "LABELS", 180),
        Triple("BinInquiry", "BIN_INQUIRY", 190),
        Triple("WhseEntries", "WHSE_ENTRIES", 200),
        Triple("FieldSettings", "FIELD_SETTINGS", 210),
        Triple("SelfTest", "SELF_TEST", 220),
        Triple("Printers", "PRINTERS", 230),
        Triple("TestCenter", "TEST_CENTER", 240),
        Triple("PostingTest", "POSTING_TEST", 250),
        Triple("Connection", "CONNECTION", 260),
    )

    private val keyByScreenName: Map<String, String> = tiles.associate { it.first to it.second }
    private val defaultSortByKey: Map<String, Int> = tiles.associate { it.second to it.third }

    /** Gizlenemez: terminale erişim (hesap/şirket) için gereklidir. */
    val lockedTiles: Set<String> = setOf("CONNECTION")

    fun tileKey(screenName: String): String? = keyByScreenName[screenName]
    fun defaultTileSort(key: String): Int? = defaultSortByKey[key]
    val tileKeys: Set<String> get() = defaultSortByKey.keys

    /** Ekran düğmeleri: ekran anahtarı → düğme anahtarları. */
    object Buttons {
        const val LABELS = "LABELS"
        const val LABELS_LAYOUT_PICKER = "LABELS.LAYOUT_PICKER"
        const val LABELS_ALL_ITEMS = "LABELS.ALL_ITEMS"
        const val LABELS_RANGES = "LABELS.RANGES"
        const val LABELS_EXCEL = "LABELS.EXCEL"
        const val LABELS_PREPARED_LIST = "LABELS.PREPARED_LIST"

        const val PUTAWAY = "PUTAWAY"
        const val PUTAWAY_ALL_TO_ONE_BIN = "PUTAWAY.ALL_TO_ONE_BIN"

        const val LICENSE_PLATES = "LICENSE_PLATES"
        const val LP_CREATE_SINGLE = "LP.CREATE_SINGLE"
        const val LP_PRINT_MTE = "LP.PRINT_MTE"
        const val LP_BREAK = "LP.BREAK"

        const val COUNT = "COUNT"
        const val COUNT_CREATE_NEW = "COUNT.CREATE_NEW"
        const val COUNT_PRINT_LP_LABELS = "COUNT.PRINT_LP_LABELS"

        const val BIN_INQUIRY = "BIN_INQUIRY"
        const val BIN_INQUIRY_PRINT_LP_LABELS = "BIN_INQUIRY.PRINT_LP_LABELS"

        val all: Map<String, List<String>> = mapOf(
            LABELS to listOf(LABELS_LAYOUT_PICKER, LABELS_ALL_ITEMS, LABELS_RANGES, LABELS_EXCEL, LABELS_PREPARED_LIST),
            PUTAWAY to listOf(PUTAWAY_ALL_TO_ONE_BIN),
            LICENSE_PLATES to listOf(LP_CREATE_SINGLE, LP_PRINT_MTE, LP_BREAK),
            COUNT to listOf(COUNT_CREATE_NEW, COUNT_PRINT_LP_LABELS),
            BIN_INQUIRY to listOf(BIN_INQUIRY_PRINT_LP_LABELS),
        )
    }
}
