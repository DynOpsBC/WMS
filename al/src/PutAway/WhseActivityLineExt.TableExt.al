tableextension 72403 "DOPSWHS Whse Activity Line" extends "Warehouse Activity Line"
{
    fields
    {
        field(72403; "LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";

            trigger OnValidate()
            var
                LP: Record "DOPSWHS LP Header";
                MatchedLPLine: Record "DOPSWHS LP Line";
                Verification: Codeunit "DOPSWHS LP Verification";
            begin
                if ("LP No." <> '') and ("Source Type" = Database::"Prod. Order Component") then begin
                    if "Action Type" <> "Action Type"::Take then
                        Error('Üretim çekmesinde kaynak LP yalnız Al satırında seçilebilir.');
                    LP.Get("LP No.");
                    if not (LP.Status in [LP.Status::Built, LP.Status::Assigned]) then
                        Error('%1 LP numarası üretim çekmesinde kullanılamaz.', "LP No.");
                    Verification.VerifyScannedLp("LP No.", Rec, "Lot No.", "Serial No.", true, MatchedLPLine);
                    exit;
                end;
                FillActivityLinesFromLP();
            end;
        }
        field(72404; "Target LP No."; Code[20])
        {
            Caption = 'Target LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
        field(72405; "DOPSWHS Source LP Line No."; Integer)
        {
            Caption = 'Source LP Line No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = "DOPSWHS LP Line"."Line No." where("LP No." = field("LP No."));
        }
    }

    local procedure FillActivityLinesFromLP()
    var
        LPLine: Record "DOPSWHS LP Line";
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        if "LP No." = '' then
            exit;

        LPLine.SetRange("LP No.", "LP No.");
        if LPLine.IsEmpty() then
            exit;

        WhseActivityLine.SetRange("Activity Type", "Activity Type");
        WhseActivityLine.SetRange("No.", "No.");
        if WhseActivityLine.FindSet(true) then
            repeat
                LPLine.SetRange("Item No.", WhseActivityLine."Item No.");
                if not LPLine.IsEmpty() then
                    if WhseActivityLine."LP No." = '' then begin
                        WhseActivityLine."LP No." := "LP No.";
                        WhseActivityLine.Modify(true);
                    end;
                LPLine.SetRange("Item No.");
            until WhseActivityLine.Next() = 0;
    end;
}
