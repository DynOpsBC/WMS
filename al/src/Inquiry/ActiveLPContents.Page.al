page 72485 "DOPSWHS Active LP Contents"
{
    Caption = 'Güncel LP Dağılımı';
    PageType = List;
    SourceTable = "DOPSWHS LP Line";
    SourceTableTemporary = true;
    ApplicationArea = All;
    UsageCategory = Lists;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("LP No."; Rec."LP No.")
                {
                    ApplicationArea = All;
                    DrillDown = true;

                    trigger OnDrillDown()
                    var
                        LPHeader: Record "DOPSWHS LP Header";
                    begin
                        if LPHeader.Get(Rec."LP No.") then
                            Page.Run(Page::"DOPSWHS LP Card", LPHeader);
                    end;
                }
                field(LPStatus; LPStatus)
                {
                    ApplicationArea = All;
                    Caption = 'LP Durumu';
                    Editable = false;
                }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Unit of Measure"; Rec."Unit of Measure") { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("Source Item Ledger Entry No."; Rec."Source Item Ledger Entry No.")
                {
                    ApplicationArea = All;
                    Caption = 'Kaynak Madde Defter Giriş No.';
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        LPHeader: Record "DOPSWHS LP Header";
    begin
        Clear(LPStatus);
        if LPHeader.Get(Rec."LP No.") then
            LPStatus := LPHeader.Status;
    end;

    procedure LoadFromBin(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UomCode: Code[10])
    var
        LPHeader: Record "DOPSWHS LP Header";
        SourceLine: Record "DOPSWHS LP Line";
    begin
        Rec.Reset();
        Rec.DeleteAll();
        LPHeader.SetRange("Location Code", LocationCode);
        LPHeader.SetRange("Bin Code", BinCode);
        LPHeader.SetFilter(Status, '%1|%2|%3', LPHeader.Status::Open, LPHeader.Status::Built, LPHeader.Status::Assigned);
        if LPHeader.FindSet() then
            repeat
                SourceLine.Reset();
                SourceLine.SetRange("LP No.", LPHeader."No.");
                SourceLine.SetRange("Item No.", ItemNo);
                SourceLine.SetRange("Variant Code", VariantCode);
                if UomCode <> '' then
                    SourceLine.SetRange("Unit of Measure", UomCode);
                if SourceLine.FindSet() then
                    repeat
                        Rec := SourceLine;
                        Rec.Insert();
                    until SourceLine.Next() = 0;
            until LPHeader.Next() = 0;
        Rec.Reset();
    end;

    var
        LPStatus: Enum "DOPSWHS LP Status";
}
