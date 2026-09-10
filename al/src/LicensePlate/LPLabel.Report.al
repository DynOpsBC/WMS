report 72091 "DOPSWHS LP Label"
{
    Caption = 'LP Label';
    UsageCategory = None;
    DefaultLayout = RDLC;
    RDLCLayout = './LPLabel.rdlc';

    dataset
    {
        dataitem(LP; "DOPSWHS LP Header")
        {
            column(No_; "No.") { }
            column(SSCC; SSCC) { }
            column(Location_Code; "Location Code") { }
            column(Bin_Code; "Bin Code") { }
            column(Built_DateTime; "Built DateTime") { }
            column(Weight_kg; "Weight kg") { }
            column(Length_cm; "Length cm") { }
            column(Width_cm; "Width cm") { }
            column(Height_cm; "Height cm") { }
            column(ZplText; BuildZpl(LP)) { }
        }
    }

    /// <summary>
    /// 4x2" (812x406 dots, 203 dpi) pallet label: header band with location /
    /// bin, large LP number, first item line, lot and extra-line count, pallet
    /// quantity, Code128 (SSCC when stopped, else LP No.) and a QR that always
    /// carries the LP number so the terminal reopens the exact record.
    /// </summary>
    procedure BuildZpl(var LP: Record "DOPSWHS LP Header"): Text
    var
        LPLine: Record "DOPSWHS LP Line";
        Item: Record Item;
        ZplEncoder: Codeunit "DOPSWHS ZPL Encoder";
        Footer: Text;
        ItemText: Text;
        LotText: Text;
        QtyText: Text;
        BarcodeData: Text;
        PlaceText: Text;
        LineCount: Integer;
        NoFont: Integer;
    begin
        LPLine.SetRange("LP No.", LP."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        if LPLine.FindSet() then begin
            repeat
                LineCount += 1;
                if LineCount = 1 then begin
                    ItemText := LPLine."Item No.";
                    if Item.Get(LPLine."Item No.") then
                        ItemText += '  ' + Item.Description;
                    QtyText := StrSubstNo('MİKTAR: %1 %2', LPLine.Quantity, LPLine."Unit of Measure");
                    if LPLine."Lot No." <> '' then
                        LotText := 'LOT: ' + LPLine."Lot No.";
                end;
            until LPLine.Next() = 0;
            if LineCount > 1 then begin
                if LotText <> '' then
                    LotText += '   ';
                LotText += StrSubstNo('+%1 DİĞER SATIR', LineCount - 1);
            end;
        end else
            QtyText := 'BOŞ TAŞIYICI';

        PlaceText := LP."Location Code";
        if LP."Bin Code" <> '' then
            PlaceText += ' / ' + LP."Bin Code";
        Footer := Format(LP."Built DateTime", 0, '<Day,2>.<Month,2>.<Year4> <Hours24>:<Minutes,2>');
        if LP."Weight kg" <> 0 then
            Footer += '   ' + Format(LP."Weight kg") + ' kg';
        if (LP."Length cm" <> 0) or (LP."Width cm" <> 0) or (LP."Height cm" <> 0) then
            Footer += '   ' + Format(LP."Length cm") + 'x' + Format(LP."Width cm") + 'x' + Format(LP."Height cm") + ' cm';
        if LP."Built By User" <> '' then
            Footer += '   Oluşturan: ' + LP."Built By User";

        // SSCC becomes the linear barcode once Stop generated it; the QR always
        // carries the LP number so a scan reopens the exact LP record either way.
        BarcodeData := LP.SSCC;
        if BarcodeData = '' then
            BarcodeData := LP."No.";

        NoFont := 76;
        if StrLen(LP."No.") > 13 then
            NoFont := 56;
        // ^CI28 = UTF-8 so Turkish characters (ç ğ ş ü ö İ) print correctly.
        exit(
            '^XA^CI28^PW812^LL406' +
            '^FO0,0^GB812,52,52^FS' +
            '^FO24,10^A0N,32,32^FR^FH_^FDPALET / LP ETİKETİ^FS' +
            '^FO470,12^A0N,26,26^FR^FH_^FB318,1,0,R^FD' + ZplEncoder.EncodeFieldData(CopyStr(PlaceText, 1, 24)) + '^FS' +
            '^FO24,62^A0N,' + Format(NoFont + 4) + ',' + Format(NoFont) + '^FH_^FD' + ZplEncoder.EncodeFieldData(LP."No.") + '^FS' +
            '^FO24,150^A0N,26,26^FH_^FB560,1,0,L^FD' + ZplEncoder.EncodeFieldData(CopyStr(ItemText, 1, 40)) + '^FS' +
            '^FO24,186^A0N,26,26^FH_^FB560,1,0,L^FD' + ZplEncoder.EncodeFieldData(CopyStr(LotText, 1, 40)) + '^FS' +
            '^FO24,222^A0N,44,44^FH_^FB560,1,0,L^FD' + ZplEncoder.EncodeFieldData(CopyStr(QtyText, 1, 26)) + '^FS' +
            '^FO24,274^BY' + Format(BarcodeModuleWidth(BarcodeData)) + '^BCN,84,N,N,N^FH_^FD' + ZplEncoder.EncodeFieldData(BarcodeData) + '^FS' +
            '^FO24,370^A0N,20,20^FH_^FB764,1,0,L^FD' + ZplEncoder.EncodeFieldData(CopyStr(Footer, 1, 80)) + '^FS' +
            '^FO604,62^BQN,2,7^FH_^FDLA,' + ZplEncoder.EncodeFieldData(LP."No.") + '^FS' +
            '^FO604,320^A0N,22,22^FH_^FDQR = LP NO^FS' +
            '^XZ');
    end;

    /// <summary>
    /// Code128 module width so the bars stay inside the 560-dot left column;
    /// an 18-digit SSCC needs module 2, short LP numbers get module 3.
    /// </summary>
    local procedure BarcodeModuleWidth(Data: Text): Integer
    begin
        if StrLen(Data) <= 10 then
            exit(3);
        if StrLen(Data) <= 22 then
            exit(2);
        exit(1);
    end;
}
