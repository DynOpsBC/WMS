codeunit 50115 "WMS Cycle Count Svc"
{
    Access = Public;

    procedure RecordCount(PlanNo: Code[20]; ItemNo: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; CountedQty: Decimal; CountedBy: Code[50]): Boolean
    var
        V: Record "WMS Count Variance";
        BinContent: Record "Bin Content";
        NextLineNo: Integer;
        SystemQty: Decimal;
    begin
        if BinContent.Get(LocationCode, BinCode, ItemNo) then
            SystemQty := BinContent."Quantity (Base)";

        V.SetRange("Plan No.", PlanNo);
        if V.FindLast() then NextLineNo := V."Line No." + 10000 else NextLineNo := 10000;

        V.Init();
        V."Plan No." := PlanNo;
        V."Line No." := NextLineNo;
        V."Item No." := ItemNo;
        V."Location Code" := LocationCode;
        V."Bin Code" := BinCode;
        V."System Quantity" := SystemQty;
        V."Counted Quantity" := CountedQty;
        V.Variance := CountedQty - SystemQty;
        V."Counted By" := CountedBy;
        V."Counted At" := CurrentDateTime();
        V.Insert();
        exit(true);
    end;

    procedure ApproveVariance(PlanNo: Code[20]; LineNo: Integer; ApprovedBy: Code[50]): Boolean
    var
        V: Record "WMS Count Variance";
    begin
        if not V.Get(PlanNo, LineNo) then exit(false);
        V."Approved By" := ApprovedBy;
        V."Approved At" := CurrentDateTime();
        V.Modify();
        // TODO[BC-sandbox]: post Item Journal adjustment for V.Variance.
        exit(true);
    end;
}
