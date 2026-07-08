codeunit 50029016 "OSD Production Svc"
{
    Access = Public;

    /// <summary>
    /// Report-as-finished (with optional put-away) from the mobile device.
    /// </summary>
    procedure ReportAsFinished(ProductionOrderNo: Code[20]; ItemNo: Code[20]; Qty: Decimal; LocationCode: Code[10]; ToBin: Code[20]; CreatePutaway: Boolean; ReportedBy: Code[50]): Boolean
    var
        OutputLine: Record "Item Journal Line";
    begin
        // TODO[BC-sandbox]: open production journal (codeunit 5407 "Production Order-Output") and post.
        OutputLine.Init();
        OutputLine."Item No." := ItemNo;
        OutputLine."Order No." := ProductionOrderNo;
        OutputLine.Quantity := Qty;
        OutputLine."Location Code" := LocationCode;
        OutputLine."Bin Code" := ToBin;
        // TODO[BC-sandbox]: post line; if CreatePutaway, invoke "Create Put-away".
        exit(true);
    end;

    procedure ConsumeComponents(ProductionOrderNo: Code[20]; ComponentItemNo: Code[20]; Qty: Decimal; FromBin: Code[20]; ConsumedBy: Code[50]): Boolean
    var
        ConsumptionLine: Record "Item Journal Line";
    begin
        ConsumptionLine.Init();
        ConsumptionLine."Order No." := ProductionOrderNo;
        ConsumptionLine."Item No." := ComponentItemNo;
        ConsumptionLine.Quantity := Qty;
        ConsumptionLine."Bin Code" := FromBin;
        // TODO[BC-sandbox]: post consumption journal.
        exit(true);
    end;

    procedure RegisterKanban(KanbanNo: Code[20]; PutawayBin: Code[20]; CompletedBy: Code[50]): Boolean
    begin
        // TODO[BC-sandbox]: BC Manufacturing kanban flow if licensed.
        exit(true);
    end;
}
