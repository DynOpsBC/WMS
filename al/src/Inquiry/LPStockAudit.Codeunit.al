codeunit 72403 "DOPSWHS LP Stock Audit"
{
    Permissions =
        tabledata "DOPSWHS LP Header" = R,
        tabledata "DOPSWHS LP Line" = R,
        tabledata "Warehouse Entry" = R,
        tabledata Item = R,
        tabledata "Item Unit of Measure" = R;

    // Read-only comparison. An LP line is a claim on stock; only Warehouse
    // Entries establish the registered quantity in a bin. Never post an
    // adjustment from this report because a bin can also hold loose stock.
    procedure DownloadBinAudit(LocationCode: Code[10]; BinCode: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        LPLine: Record "DOPSWHS LP Line";
        WarehouseEntry: Record "Warehouse Entry";
        Item: Record Item;
        ItemUoM: Record "Item Unit of Measure";
        TempBlob: Codeunit "Temp Blob";
        Output: OutStream;
        Input: InStream;
        Claims: Dictionary of [Text, Decimal];
        GroupId: Text;
        LineBaseQty: Decimal;
        ClaimBaseQty: Decimal;
        WarehouseBaseQty: Decimal;
        ShortageBaseQty: Decimal;
        FileName: Text;
    begin
        if (LocationCode = '') or (BinCode = '') then
            Error('Önce bir konum ve depo gözü seçin.');

        LP.SetRange("Location Code", LocationCode);
        LP.SetRange("Bin Code", BinCode);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        if LP.FindSet() then
            repeat
                LPLine.SetRange("LP No.", LP."No.");
                LPLine.SetFilter("Item No.", '<>%1', '');
                LPLine.SetFilter(Quantity, '>0');
                if LPLine.FindSet() then
                    repeat
                        GroupId := GroupKey(LPLine);
                        LineBaseQty := BaseQuantity(LPLine, Item, ItemUoM);
                        if Claims.Get(GroupId, ClaimBaseQty) then
                            Claims.Set(GroupId, ClaimBaseQty + LineBaseQty)
                        else
                            Claims.Add(GroupId, LineBaseQty);
                    until LPLine.Next() = 0;
            until LP.Next() = 0;

        TempBlob.CreateOutStream(Output, TextEncoding::UTF8);
        Output.WriteText('LP No.;Madde No.;Varyant;Lot No.;Seri No.;LP Satır Miktarı (Temel);Raftaki Tüm LP Miktarı (Temel);BC Raf Miktarı (Temel);LP Fazlası (Temel);Konum;Depo Gözü;LP Satır Kaynak Gözü;Kaynak Madde Defter Giriş No.');
        Output.WriteText();

        LP.Reset();
        LP.SetRange("Location Code", LocationCode);
        LP.SetRange("Bin Code", BinCode);
        LP.SetFilter(Status, '%1|%2|%3', LP.Status::Open, LP.Status::Built, LP.Status::Assigned);
        if LP.FindSet() then
            repeat
                LPLine.Reset();
                LPLine.SetRange("LP No.", LP."No.");
                LPLine.SetFilter("Item No.", '<>%1', '');
                LPLine.SetFilter(Quantity, '>0');
                if LPLine.FindSet() then
                    repeat
                        GroupId := GroupKey(LPLine);
                        Claims.Get(GroupId, ClaimBaseQty);
                        LineBaseQty := BaseQuantity(LPLine, Item, ItemUoM);
                        WarehouseEntry.Reset();
                        WarehouseEntry.SetRange("Location Code", LocationCode);
                        WarehouseEntry.SetRange("Bin Code", BinCode);
                        WarehouseEntry.SetRange("Item No.", LPLine."Item No.");
                        WarehouseEntry.SetRange("Variant Code", LPLine."Variant Code");
                        WarehouseEntry.SetRange("Lot No.", LPLine."Lot No.");
                        WarehouseEntry.SetRange("Serial No.", LPLine."Serial No.");
                        WarehouseEntry.CalcSums("Qty. (Base)");
                        WarehouseBaseQty := WarehouseEntry."Qty. (Base)";
                        ShortageBaseQty := ClaimBaseQty - WarehouseBaseQty;
                        if ShortageBaseQty < 0 then
                            ShortageBaseQty := 0;
                        Output.WriteText(
                            StrSubstNo('%1;%2;%3;%4;%5;%6;%7;%8;%9',
                                LP."No.", LPLine."Item No.", LPLine."Variant Code", LPLine."Lot No.",
                                LPLine."Serial No.", LineBaseQty, ClaimBaseQty, WarehouseBaseQty,
                                ShortageBaseQty) + ';' + LocationCode + ';' + BinCode + ';' +
                            LPLine."Source Bin Code" + ';' + Format(LPLine."Source Item Ledger Entry No."));
                        Output.WriteText();
                    until LPLine.Next() = 0;
            until LP.Next() = 0;

        TempBlob.CreateInStream(Input, TextEncoding::UTF8);
        FileName := StrSubstNo('LP-stok-mutabakati-%1-%2.csv', LocationCode, BinCode);
        DownloadFromStream(Input, '', '', '', FileName);
    end;

    local procedure GroupKey(LPLine: Record "DOPSWHS LP Line"): Text
    begin
        exit(StrSubstNo('%1|%2|%3|%4',
            LPLine."Item No.", LPLine."Variant Code", LPLine."Lot No.", LPLine."Serial No."));
    end;

    local procedure BaseQuantity(LPLine: Record "DOPSWHS LP Line"; var Item: Record Item; var ItemUoM: Record "Item Unit of Measure"): Decimal
    var
        EffectiveUoM: Code[10];
        QuantityPerUoM: Decimal;
    begin
        Item.Get(LPLine."Item No.");
        EffectiveUoM := LPLine."Unit of Measure";
        if EffectiveUoM = '' then
            EffectiveUoM := Item."Base Unit of Measure";
        QuantityPerUoM := 1;
        if EffectiveUoM <> Item."Base Unit of Measure" then begin
            ItemUoM.Get(LPLine."Item No.", EffectiveUoM);
            QuantityPerUoM := ItemUoM."Qty. per Unit of Measure";
            if QuantityPerUoM <= 0 then
                Error('%1 / %2 ölçü birimi dönüşümü geçersiz.', LPLine."Item No.", EffectiveUoM);
        end;
        exit(Round(LPLine.Quantity * QuantityPerUoM, 0.00001));
    end;
}
