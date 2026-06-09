codeunit 50114 "WMS Movement Svc"
{
    Access = Public;

    procedure RegisterMovement(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; FromBin: Code[20]; ToBin: Code[20]; Qty: Decimal; LpNo: Code[20]; MovedBy: Code[50]): Boolean
    var
        ReclassLine: Record "Item Reclassification Journal Line";
        TemplateName: Code[10];
        BatchName: Code[10];
    begin
        TemplateName := 'ITEM';
        BatchName := 'DEFAULT';
        // TODO[BC-sandbox]: ensure templates exist; otherwise create transient journal name.
        ReclassLine.Init();
        ReclassLine."Journal Template Name" := TemplateName;
        ReclassLine."Journal Batch Name" := BatchName;
        ReclassLine."Item No." := ItemNo;
        ReclassLine."Variant Code" := VariantCode;
        ReclassLine."Location Code" := LocationCode;
        ReclassLine."Bin Code" := FromBin;
        ReclassLine."New Bin Code" := ToBin;
        ReclassLine.Quantity := Qty;
        // TODO[BC-sandbox]: codeunit 23 "Item Jnl.-Post Line" or worksheet flow.
        exit(true);
    end;

    procedure RegisterTransfer(FromLocation: Code[10]; ToLocation: Code[10]; ItemNo: Code[20]; Qty: Decimal): Boolean
    begin
        // TODO[BC-sandbox]: Transfer Order create + post.
        exit(true);
    end;
}
