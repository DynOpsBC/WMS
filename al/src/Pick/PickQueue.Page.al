page 72083 "DOPSWHS Pick Queue"
{
    PageType = ListPart;
    SourceTable = "Warehouse Activity Header";
    SourceTableView = where(Type = const(Pick));
    Caption = 'DOPSWHS Pick Queue';
    ApplicationArea = All;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Picks)
            {
                field("Pick No."; Rec."No.") { ApplicationArea = All; Caption = 'Pick No.'; }
                field("Source No."; SourceNo) { ApplicationArea = All; Caption = 'Source No.'; }
                field("Assigned User"; Rec."Assigned User ID") { ApplicationArea = All; Caption = 'Assigned User'; }
                field(Lines; LineCount) { ApplicationArea = All; Caption = 'Lines'; }
                field("% Complete"; PercentComplete) { ApplicationArea = All; Caption = '% Complete'; ExtendedDatatype = Ratio; }
                field(Created; Rec."Assignment Date") { ApplicationArea = All; Caption = 'Created'; }
                field("Due Date"; DueDate) { ApplicationArea = All; Caption = 'Due Date'; }
            }
            usercontrol(PickBoard; "DOPSWHS Pick Board")
            {
                ApplicationArea = All;
                trigger ControlReady()
                begin
                    CurrPage.PickBoard.SetLocale(Format(GlobalLanguage()));
                    CurrPage.PickBoard.SetData(BuildBoardJson());
                end;

                trigger Reassign(PickNo: Code[20]; UserId: Code[50])
                var
                    Pick: Record "Warehouse Activity Header";
                    PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                begin
                    Pick.Get(Pick.Type::Pick, PickNo);
                    PickMgmt.ReassignPick(Pick, UserId, 'Pick Board drag-drop');
                    CurrPage.Update(false);
                end;

                trigger RequestRefresh()
                begin
                    CurrPage.PickBoard.SetData(BuildBoardJson());
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action("Manual Reassign")
            {
                ApplicationArea = All;
                Caption = 'Manual Reassign';
                trigger OnAction()
                var
                    PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                    User: Record User;
                begin
                    if Page.RunModal(Page::"User Lookup", User) <> Action::LookupOK then
                        exit;
                    PickMgmt.ReassignPick(Rec, User."User Name", 'Manual queue action');
                    CurrPage.Update(false);
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        FillCalculatedFields();
    end;

    var
        SourceNo: Code[20];
        DueDate: Date;
        LineCount: Integer;
        PercentComplete: Integer;

    local procedure FillCalculatedFields()
    var
        PickLine: Record "Warehouse Activity Line";
        TotalQty: Decimal;
        HandledQty: Decimal;
    begin
        Clear(SourceNo);
        Clear(DueDate);
        Clear(LineCount);
        Clear(PercentComplete);
        PickLine.SetRange("Activity Type", Rec.Type);
        PickLine.SetRange("No.", Rec."No.");
        if PickLine.FindSet() then
            repeat
                if SourceNo = '' then begin
                    SourceNo := PickLine."Source No.";
                    DueDate := PickLine."Due Date";
                end;
                LineCount += 1;
                TotalQty += PickLine.Quantity;
                HandledQty += PickLine."Qty. Handled";
            until PickLine.Next() = 0;
        if TotalQty <> 0 then
            PercentComplete := Round(HandledQty / TotalQty * 100, 1);
    end;

    local procedure BuildBoardJson(): Text
    var
        BoardData: Codeunit "DOPSWHS Board Data";
    begin
        exit(BoardData.BuildPickBoardJson());
    end;
}
