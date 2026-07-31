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
                field(pickMode; Rec."DOPSWHS Pick Mode") { Caption = 'pickMode'; }
                // ELOG: araç bilgisini sorumlu masadan girer; terminal salt-okunur gösterir.
                field(vehicleNo; Rec."DOPSWHS Vehicle No.") { Caption = 'vehicleNo'; Editable = false; }
                // Ana sepet: terminal toplamaya başlarken PATCH'ler; ekrandan
                // çıkıp girince kaybolmasın diye kalıcı. Paketleme de okur.
                field(mainLpNo; Rec."DOPSWHS Main LP No.") { Caption = 'mainLpNo'; }
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

    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::Pick);
        RecRef.SetTable(Rec);
    end;

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

    // ELOG: sipariş başına tote (sepet) bağlama — bkz. "DOPSWHS Pick Tote Assignment".
    [ServiceEnabled]
    procedure assignTote(sourceOrderNo: Code[20]; lpNo: Code[20])
    var
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        PickMgmt.AssignTote(Rec, sourceOrderNo, lpNo);
    end;

    [ServiceEnabled]
    procedure toteForOrder(sourceOrderNo: Code[20]): Code[20]
    var
        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
    begin
        exit(PickMgmt.GetToteForOrder(Rec."No.", sourceOrderNo));
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
        PickLine.SetRange("Action Type", PickLine."Action Type"::Take);
        if PickLine.FindSet() then
            repeat
                if SourceNo = '' then begin
                    SourceNo := PickLine."Source No.";
                    DueDate := PickLine."Due Date";
                end;
                TotalQty += PickLine.Quantity;
                HandledQty += PickLine."Qty. to Handle";
            until PickLine.Next() = 0;

        if TotalQty <> 0 then
            PercentComplete := Round(HandledQty / TotalQty * 100, 1);
    end;
}
