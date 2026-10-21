/// <summary>
/// Kitoko (21 Eki 2026): EMU'dan Excel'den sıralı ürün / göz etiketleri.
/// Uydurma ürünlerle; müşteri listesi kullanılmaz.
/// </summary>
codeunit 72199 "DOPSWHS Excel Label Tests"
{
    Subtype = Test;

    [Test]
    procedure RepeatedItemsKeepTheirBinOrder()
    var
        Item: Record Item;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Count: Integer;
        Zpl: Text;
    begin
        SeedItem(Item, 'EXCEL-TEST');
        Zpl := Dispatcher.BuildExcelItemLabels(
            '[{"order":1,"itemNo":"EXCEL-TEST","bin":"A2"},{"order":2,"itemNo":"EXCEL-TEST","bin":"A1"}]', Count);
        if Count <> 2 then
            Error('Repeated products must produce two labels.');
        if (StrPos(Zpl, 'A2') = 0) or (StrPos(Zpl, 'A2') >= StrPos(Zpl, 'A1')) then
            Error('Bin order must match the imported rows.');
        if StrPos(Zpl, '^FDLA,EXCEL-TEST^FS') = 0 then
            Error('QR must contain only the bare product number.');
        if (StrPos(Zpl, 'SIRA: 1') = 0) or (StrPos(Zpl, 'SIRA: 2') = 0) then
            Error('Each label must carry its sequence number.');
    end;

    [Test]
    procedure UnknownProductIsRejected()
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Count: Integer;
    begin
        asserterror Dispatcher.BuildExcelItemLabels('[{"order":1,"itemNo":"MISSING-EXCEL-TEST","bin":"A1"}]', Count);
        if StrPos(GetLastErrorText(), 'MISSING-EXCEL-TEST') = 0 then
            Error('Missing item error must identify the product.');
    end;

    [Test]
    procedure BrokenOrderIsRejected()
    var
        Item: Record Item;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Count: Integer;
    begin
        SeedItem(Item, 'EXCEL-TEST');
        asserterror Dispatcher.BuildExcelItemLabels('[{"order":1,"itemNo":"EXCEL-TEST","bin":"A1"},{"order":3,"itemNo":"EXCEL-TEST","bin":"A2"}]', Count);
        if StrPos(GetLastErrorText(), 'kesintisiz') = 0 then
            Error('Nonconsecutive sequence must fail before enqueue.');
    end;

    [Test]
    procedure BlockedProductIsRejected()
    var
        Item: Record Item;
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        Count: Integer;
    begin
        SeedItem(Item, 'EXCEL-TEST');
        Item.Blocked := true;
        Item.Modify();
        asserterror Dispatcher.BuildExcelItemLabels('[{"order":1,"itemNo":"EXCEL-TEST","bin":"A1"}]', Count);
    end;

    local procedure SeedItem(var Item: Record Item; ItemNo: Code[20])
    begin
        if Item.Get(ItemNo) then
            Item.Delete();
        Item.Init();
        Item."No." := ItemNo;
        Item.Description := 'Excel label test';
        Item.Insert();
    end;
}
