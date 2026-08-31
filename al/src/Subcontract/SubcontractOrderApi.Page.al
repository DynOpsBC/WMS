page 72441 "DOPSWHS Subcontract Order API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'subcontractOrder';
    EntitySetName = 'subcontractOrders';
    SourceTable = "Prod. Order Routing Line";
    SourceTableView = where(Status = const(Released), Type = const("Work Center"));
    ODataKeyFields = Status, "Prod. Order No.", "Routing Reference No.", "Routing No.", "Operation No.";
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(status; Rec.Status) { }
                field(prodOrderNo; Rec."Prod. Order No.") { }
                field(routingReferenceNo; Rec."Routing Reference No.") { }
                field(routingNo; Rec."Routing No.") { }
                field(operationNo; Rec."Operation No.") { }
                field(routingLinkCode; Rec."Routing Link Code") { }
                field(workCenterNo; Rec."No.") { }
                field(description; Rec.Description) { }
                field(subcontractorNo; SubcontractorNo) { }
                field(subcontractorName; SubcontractorName) { }
                field(targetLocationCode; TargetLocationCode) { }
                field(targetLocationName; TargetLocationName) { }
                field(componentCount; ComponentCount) { }
                field(remainingDispatchQuantity; RemainingDispatchQuantity) { }
                field(startingDate; Rec."Starting Date") { }
                field(endingDate; Rec."Ending Date") { }
            }
        }
    }

    trigger OnOpenPage()
    var
        WorkCenter: Record "Work Center";
        WorkCenterFilter: Text;
    begin
        WorkCenter.SetFilter("Subcontractor No.", '<>%1', '');
        if WorkCenter.FindSet() then
            repeat
                if WorkCenterFilter <> '' then
                    WorkCenterFilter += '|';
                WorkCenterFilter += WorkCenter."No.";
            until WorkCenter.Next() = 0;
        if WorkCenterFilter = '' then
            Rec.SetRange("No.", '#DOPSWHS-NO-SUBCONTRACTOR#')
        else
            Rec.SetFilter("No.", WorkCenterFilter);
    end;

    trigger OnAfterGetRecord()
    var
        WorkCenter: Record "Work Center";
        Vendor: Record Vendor;
        Location: Record Location;
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
    begin
        Clear(SubcontractorNo);
        Clear(SubcontractorName);
        Clear(TargetLocationCode);
        Clear(TargetLocationName);
        Clear(ComponentCount);
        Clear(RemainingDispatchQuantity);
        if not WorkCenter.Get(Rec."No.") then
            exit;
        SubcontractorNo := WorkCenter."Subcontractor No.";
        TargetLocationCode := WorkCenter."Location Code";
        if Vendor.Get(SubcontractorNo) then
            SubcontractorName := Vendor.Name;
        if Location.Get(TargetLocationCode) then
            TargetLocationName := Location.Name;
        Mgmt.GetOperationSummary(Rec, ComponentCount, RemainingDispatchQuantity);
    end;

    [ServiceEnabled]
    procedure dispatch(linesJson: Text; idempotencyKey: Guid): Text
    var
        Mgmt: Codeunit "DOPSWHS Subcontract Mgmt";
        DispatchPermission: Record "DOPSWHS Subcontract Dispatch";
    begin
        if not DispatchPermission.WritePermission() then
            Error('Fason sevk kaydı oluşturma yetkiniz yok. Depo kullanıcı rolünü kontrol edin.');
        exit(Mgmt.Dispatch(Rec, LinesJson, IdempotencyKey));
    end;

    var
        SubcontractorNo: Code[20];
        SubcontractorName: Text[100];
        TargetLocationCode: Code[10];
        TargetLocationName: Text[100];
        ComponentCount: Integer;
        RemainingDispatchQuantity: Decimal;
}
