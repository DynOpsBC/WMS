codeunit 72043 "DOPSWHS Receipt Mgmt"
{
    Access = Public;

    procedure PostReceipt(var WhseReceiptHeader: Record "Warehouse Receipt Header"; PrintReport: Boolean; Invoice: Boolean)
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        WhsePostReceipt: Codeunit "Whse.-Post Receipt";
        LpPropagation: Codeunit "DOPSWHS LP Propagation";
        LpNo: Code[20];
        PostedNo: Code[20];
    begin
        Log('Receipt.Post', WhseReceiptHeader."No.");
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        if WhseReceiptLine.FindFirst() then
            WhsePostReceipt.Run(WhseReceiptLine);

        PostedWhseReceiptHeader.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        if PostedWhseReceiptHeader.FindLast() then
            PostedNo := PostedWhseReceiptHeader."No.";

        LpPropagation.StampPostedReceiptHeader(WhseReceiptHeader."No.", PostedNo);
        LpPropagation.StampPostedReceiptLines(WhseReceiptHeader."No.", PostedNo);

        PostedWhseReceiptLine.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        if PostedWhseReceiptLine.FindSet(true) then
            repeat
                if LpNo <> '' then
                    AssignLP(LpNo, WhseReceiptHeader."No.");
            until PostedWhseReceiptLine.Next() = 0;
    end;

    procedure AssignUser(var WhseReceiptHeader: Record "Warehouse Receipt Header"; AssignedUserId: Code[50])
    begin
        Log('Receipt.AssignUser', WhseReceiptHeader."No.");
        WhseReceiptHeader.Validate("Assigned User ID", AssignedUserId);
        WhseReceiptHeader.Modify(true);
    end;

    procedure StartLP(var WhseReceiptHeader: Record "Warehouse Receipt Header"; TemplateCode: Code[20]): Code[20]
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        EffectiveTemplateCode: Code[20];
    begin
        Log('Receipt.StartLP', WhseReceiptHeader."No.");
        EffectiveTemplateCode := TemplateCode;
        if EffectiveTemplateCode = '' then
            EffectiveTemplateCode := 'PALLET-EUR';

        LPMgt.Build(EffectiveTemplateCode, WhseReceiptHeader."Location Code", '', LP);
        exit(LP."No.");
    end;

    procedure StopLP(var WhseReceiptHeader: Record "Warehouse Receipt Header"; LpNo: Code[20]; PrintLabel: Boolean)
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        Log('Receipt.StopLP', WhseReceiptHeader."No.");
        LP.Get(LpNo);
        LPMgt.Stop(LP, PrintLabel);
    end;

    procedure ConfirmLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; QtyToReceive: Decimal; LotNo: Code[50]; SerialNo: Code[50]; ExpiryDate: Date; LicensePlateNo: Code[20]; BinCode: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        Log('Receipt.ConfirmLine', WhseReceiptLine."No.");
        if BinCode <> '' then
            WhseReceiptLine.Validate("Bin Code", BinCode);
        WhseReceiptLine.Validate("Qty. to Receive", QtyToReceive);
        // TODO Sprint H+ post-deploy: persist lot/serial/expiry/package through item tracking APIs for this BC symbol set.
        WhseReceiptLine.Modify(true);

        if LicensePlateNo <> '' then begin
            LP.Get(LicensePlateNo);
            LPMgt.AddLine(LP, WhseReceiptLine."Item No.", WhseReceiptLine."Unit of Measure Code", QtyToReceive, LotNo, SerialNo, ExpiryDate);

            // Stamp the Whse Receipt Header with this LP so downstream posting can carry it
            // onto Posted Whse Receipt + Item Ledger Entry. Idempotent — only first LP wins.
            if WhseReceiptHeader.Get(WhseReceiptLine."No.") then
                if WhseReceiptHeader."DOPSWHS LP No." = '' then begin
                    WhseReceiptHeader."DOPSWHS LP No." := LicensePlateNo;
                    WhseReceiptHeader.Modify(true);
                end;
        end;
    end;

    local procedure AssignLP(LpNo: Code[20]; ReceiptNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        if not LP.Get(LpNo) then
            exit;
        if LP.Status = LP.Status::Built then
            LPMgt.Assign(LP, Enum::"DOPSWHS Assigned Doc Type"::WhseReceipt, ReceiptNo);
    end;

    local procedure Log(Category: Text; DocNo: Code[20])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(Category, DocNo);
    end;
}
