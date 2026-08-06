enum 72343 "DOPSWHS Pack Mode"
{
    Extensible = true;

    // ELOG akışları: Solo = tek siparişlik sepet (kutu ürünler fiş);
    // Bulk = aynı ürün birden çok siparişe bölünmüş (her pay: kutu ürünler fiş);
    // Batch = tek ürünlük siparişler (ürün kutu fiş döngüsü).
    value(0; Solo) { Caption = 'Solo'; }
    value(1; Bulk) { Caption = 'Bulk'; }
    value(2; Batch) { Caption = 'Batch'; }
}
