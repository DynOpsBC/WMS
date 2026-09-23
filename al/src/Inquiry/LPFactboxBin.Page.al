page 72078 "DOPSWHS LP Factbox Bin"
{
    PageType = ListPart;
    SourceTable = "DOPSWHS LP Header";
    ApplicationArea = All;
    Caption = 'License Plates';
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("No."; Rec."No.") { ApplicationArea = All; Caption = 'LP No.'; }
                field(Contents; ContentsSummary)
                {
                    ApplicationArea = All;
                    Caption = 'Contents';
                    Editable = false;
                    ToolTip = 'Shows item, quantity and lot information stored in this LP.';
                }
                field("Total Quantity"; Rec."Total Quantity") { ApplicationArea = All; Caption = 'Total Quantity'; }
                field(Status; Rec.Status) { ApplicationArea = All; Caption = 'Status'; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; Caption = 'Bin Code'; }
                field("Line Count"; Rec."Line Count") { ApplicationArea = All; Caption = 'Line Count'; }
                field("LP Template Code"; Rec."LP Template Code") { ApplicationArea = All; Caption = 'Template'; }
            }
        }
    }

    trigger OnOpenPage()
    begin
        Rec.SetFilter(Status, '%1|%2|%3', Rec.Status::Open, Rec.Status::Built, Rec.Status::Assigned);
    end;

    procedure SetScope(LocationCode: Code[10]; BinCode: Code[20]; LPNo: Code[20])
    begin
        Rec.Reset();
        if (LocationCode = '') and (BinCode = '') and (LPNo = '') then
            Rec.SetRange("No.", '')
        else begin
            if LocationCode <> '' then
                Rec.SetRange("Location Code", LocationCode);
            if BinCode <> '' then
                Rec.SetRange("Bin Code", BinCode);
            if LPNo <> '' then
                Rec.SetRange("No.", LPNo);
        end;
        Rec.SetFilter(Status, '%1|%2|%3', Rec.Status::Open, Rec.Status::Built, Rec.Status::Assigned);
        CurrPage.Update(false);
    end;

    trigger OnAfterGetRecord()
    var
        BinContentSubscriber: Codeunit "DOPSWHS Bin Content Subscriber";
    begin
        Rec.CalcFields("Line Count", "Total Quantity");
        ContentsSummary := BinContentSubscriber.GetLPContentSummary(Rec."No.");
    end;

    var
        ContentsSummary: Text[250];
}
