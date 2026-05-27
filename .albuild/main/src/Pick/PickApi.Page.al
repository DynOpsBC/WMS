page 72092 "DOPSWHS Pick API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'pick';
    EntitySetName = 'picks';
    SourceTable = "Warehouse Activity Header";
    SourceTableView = where(Type = const(Pick));
    DelayedInsert = true;
    ODataKeyFields = "No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(assignedUserId; Rec."Assigned User ID") { Caption = 'assignedUserId'; }
                field(sourceNo; SourceNo) { Caption = 'sourceNo'; }
                // TODO Sprint H+ post-deploy: bind to activity status if exposed by the target BC app.
                field(status; StatusText) { Caption = 'status'; }
                field(dueDate; DueDate) { Caption = 'dueDate'; }
                field(percentComplete; PercentComplete) { Caption = 'percentComplete'; }
                part(lines; "DOPSWHS Pick Line API")
                {
                    Caption = 'lines';
                    EntityName = 'pickLine';
                    EntitySetName = 'pickLines';
                    SubPageLink = "Activity Type" = field(Type), "No." = field("No.");
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        FillCalculatedFields();
    end;

    [ServiceEnabled]
    procedure assignToMe()
    var
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PickMgmt.AssignToMe(Rec);
    end;

    [ServiceEnabled]
    procedure startShippingLP(lpTemplateCode: Code[20]): Code[20]
    var
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        exit(PickMgmt.StartShippingLP(Rec, lpTemplateCode));
    end;

    [ServiceEnabled]
    procedure stopShippingLP(lpNo: Code[20]; printLabel: Boolean): Code[18]
    var
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        exit(PickMgmt.StopShippingLP(Rec, lpNo, printLabel));
    end;

    [ServiceEnabled]
    procedure markShort(lineNo: Integer; qty: Decimal; reasonCode: Code[20])
    var
        PickLine: Record "Warehouse Activity Line";
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PickLine.Get(Rec.Type, Rec."No.", lineNo);
        PickMgmt.RegisterShortPick(PickLine, qty, reasonCode);
    end;

    [ServiceEnabled]
    procedure register()
    var
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PickMgmt.RegisterPick(Rec);
    end;

    [ServiceEnabled]
    procedure reassign(userId: Code[50]; reason: Text[250])
    var
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PickMgmt.ReassignPick(Rec, userId, reason);
    end;

    var
        SourceNo: Code[20];
        DueDate: Date;
        PercentComplete: Decimal;
        StatusText: Text[30];

    local procedure FillCalculatedFields()
    var
        PickLine: Record "Warehouse Activity Line";
        TotalQty: Decimal;
        HandledQty: Decimal;
    begin
        Clear(SourceNo);
        Clear(DueDate);
        Clear(PercentComplete);

        PickLine.SetRange("Activity Type", Rec.Type);
        PickLine.SetRange("No.", Rec."No.");
        if PickLine.FindSet() then
            repeat
                if SourceNo = '' then begin
                    SourceNo := PickLine."Source No.";
                    DueDate := PickLine."Due Date";
                end;
                TotalQty += PickLine.Quantity;
                HandledQty += PickLine."Qty. Handled";
            until PickLine.Next() = 0;

        if TotalQty <> 0 then
            PercentComplete := Round(HandledQty / TotalQty * 100, 1);
    end;
}
