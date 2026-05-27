codeunit 72039 "DOPSWHS Bin Content Subscriber"
{
    Access = Public;

    procedure CalculateNestedLPQuantity(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]): Decimal
    var
        LP: Record "DOPSWHS LP Header";
        Total: Decimal;
    begin
        LP.SetRange("Location Code", LocationCode);
        LP.SetRange("Bin Code", BinCode);
        LP.SetRange(Status, LP.Status::Built);
        LP.SetRange("Parent LP No.", '');
        if LP.FindSet() then
            repeat
                Total += SumLeafItemLines(LP."No.", ItemNo);
            until LP.Next() = 0;
        exit(Total);
    end;

    local procedure SumLeafItemLines(LPNo: Code[20]; ItemNo: Code[20]): Decimal
    var
        LPLine: Record "DOPSWHS LP Line";
        Total: Decimal;
    begin
        LPLine.SetRange("LP No.", LPNo);
        if LPLine.FindSet() then
            repeat
                if LPLine."Child LP No." <> '' then
                    Total += SumLeafItemLines(LPLine."Child LP No.", ItemNo)
                else
                    if (ItemNo = '') or (LPLine."Item No." = ItemNo) then
                        Total += LPLine.Quantity;
            until LPLine.Next() = 0;
        exit(Total);
    end;
}
