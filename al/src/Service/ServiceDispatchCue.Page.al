page 72104 "DOPSWHS Service Dispatch Cue"
{
    PageType = CardPart;
    SourceTable = "DOPSWHS Service Cue";
    SourceTableTemporary = true;
    Caption = 'Service Overview';
    Editable = false;
    layout
    {
        area(Content)
        {
            cuegroup(ServiceOrders)
            {
                Caption = 'Service Orders';
                field(Pending; Rec."Pending")
                {
                    ApplicationArea = All;
                    Caption = 'Pending';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(0);
                    end;
                }
                field(InProcess; Rec."In Process")
                {
                    ApplicationArea = All;
                    Caption = 'In Process';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(1);
                    end;
                }
                field(OnHold; Rec."On Hold")
                {
                    ApplicationArea = All;
                    Caption = 'On Hold';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(2);
                    end;
                }
                field(Finished; Rec."Finished")
                {
                    ApplicationArea = All;
                    Caption = 'Finished';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(3);
                    end;
                }
                field(Overdue; Rec."Overdue")
                {
                    ApplicationArea = All;
                    Caption = 'Overdue';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(5);
                    end;
                }
            }
        }
    }
    trigger OnOpenPage()
    begin
        Rec.Init();
        Rec.Insert();
        // Blank response dates are not overdue.
        Rec.SetRange("Date Filter", DMY2Date(1, 1, 2000), Mgt.LocalToday() - 1);
    end;
    local procedure OpenOrders(Kind: Integer)
    var
        Header: Record "Service Header";
        Dispatch: Page "DOPSWHS Service Dispatch";
    begin
        Header.SetRange("Document Type", Header."Document Type"::Order);
        case Kind of
            0: Header.SetRange(Status, Header.Status::Pending);
            1: Header.SetRange(Status, Header.Status::"In Process");
            2: Header.SetRange(Status, Header.Status::"On Hold");
            3: Header.SetRange(Status, Header.Status::Finished);
            5:
                begin
                    Header.SetFilter(Status, '<>%1', Header.Status::Finished);
                    Header.SetRange("Response Date", DMY2Date(1, 1, 2000), Mgt.LocalToday() - 1);
                end;
        end;
        Dispatch.SetTableView(Header);
        Dispatch.Run();
    end;
    var
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
}
