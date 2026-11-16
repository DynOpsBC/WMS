page 72105 "DOPSWHS Service Orders API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceOrder';
    EntitySetName = 'serviceOrders';
    SourceTable = "Service Header";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    SourceTableView = where("Document Type" = const(Order));
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(no; Rec."No.") { Caption = 'no'; }
                field(customerNo; Rec."Customer No.") { Caption = 'customerNo'; }
                field(name; Rec."Name") { Caption = 'name'; }
                field(address; Rec."Address") { Caption = 'address'; }
                field(address2; Rec."Address 2") { Caption = 'address2'; }
                field(city; Rec."City") { Caption = 'city'; }
                field(postCode; Rec."Post Code") { Caption = 'postCode'; }
                field(phoneNo; Rec."Phone No.") { Caption = 'phoneNo'; }
                field(phoneNo2; Rec."Phone No. 2") { Caption = 'phoneNo2'; }
                field(eMail; Rec."E-Mail") { Caption = 'eMail'; }
                field(contactName; Rec."Contact Name") { Caption = 'contactName'; }
                field(shipToCode; Rec."Ship-to Code") { Caption = 'shipToCode'; }
                field(shipToName; Rec."Ship-to Name") { Caption = 'shipToName'; }
                field(shipToAddress; Rec."Ship-to Address") { Caption = 'shipToAddress'; }
                field(shipToCity; Rec."Ship-to City") { Caption = 'shipToCity'; }
                field(description; Rec."Description") { Caption = 'description'; }
                field(status; Rec."Status") { Caption = 'status'; }
                field(orderDate; Rec."Order Date") { Caption = 'orderDate'; }
                field(orderTime; Rec."Order Time") { Caption = 'orderTime'; }
                field(responseDate; Rec."Response Date") { Caption = 'responseDate'; }
                field(responseTime; Rec."Response Time") { Caption = 'responseTime'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(serviceOrderType; Rec."Service Order Type") { Caption = 'serviceOrderType'; }
                field(assignedUserId; Rec."Assigned User ID") { Caption = 'assignedUserId'; }
                field(statusText; statusTextValue) { Caption = 'statusText'; }
                field(priority; priorityValue) { Caption = 'priority'; }
                field(priorityText; priorityTextValue) { Caption = 'priorityText'; }
                field(releaseStatus; releaseStatusValue) { Caption = 'releaseStatus'; }
                field(technicianNames; technicianNamesValue) { Caption = 'technicianNames'; }
                field(allocatedHours; allocatedHoursValue) { Caption = 'allocatedHours'; }
                field(noOfServiceItemLines; noOfServiceItemLinesValue) { Caption = 'noOfServiceItemLines'; }
            }
        }
    }
    trigger OnAfterGetRecord()
    var
        ItemLine: Record "Service Item Line";
    begin
        statusTextValue := Rec.Status.Names.Get(Rec.Status.Ordinals.IndexOf(Rec.Status.AsInteger()));
        priorityValue := Rec.Priority.Names.Get(Rec.Priority.Ordinals.IndexOf(Rec.Priority.AsInteger()));
        priorityTextValue := priorityValue;
        releaseStatusValue := Rec."Release Status".Names.Get(Rec."Release Status".Ordinals.IndexOf(Rec."Release Status".AsInteger()));
        technicianNamesValue := Mgt.TechnicianNames(Rec."No.");
        allocatedHoursValue := Mgt.AllocatedHours(Rec."No.");
        ItemLine.SetRange("Document Type", Rec."Document Type");
        ItemLine.SetRange("Document No.", Rec."No.");
        noOfServiceItemLinesValue := ItemLine.Count();
    end;

    local procedure ResolveLine(serviceItemLineNo: Integer): Integer
    begin
        if serviceItemLineNo = 0 then
            exit(Mgt.FirstServiceItemLineNo(Rec."No."));
        exit(serviceItemLineNo);
    end;

    [ServiceEnabled]
    procedure assignTechnician(serviceItemLineNo: Integer; resourceNo: Code[20]; allocationDate: Date; hours: Decimal): Text
    begin
        exit(Format(Mgt.AssignTechnician(Rec."No.", ResolveLine(serviceItemLineNo), resourceNo, allocationDate, hours), 0, 9));
    end;

    [ServiceEnabled]
    procedure startWork(serviceItemLineNo: Integer): Text
    begin
        Mgt.StartWork(Rec."No.", ResolveLine(serviceItemLineNo));
        exit('OK');
    end;

    [ServiceEnabled]
    procedure setRepairStatus(serviceItemLineNo: Integer; repairStatusCode: Code[10]): Text
    begin
        Mgt.SetRepairStatus(Rec."No.", ResolveLine(serviceItemLineNo), repairStatusCode);
        exit('OK');
    end;

    [ServiceEnabled]
    procedure finishWork(serviceItemLineNo: Integer; faultAreaCode: Code[10]; symptomCode: Code[10]; faultCode: Code[10]; resolutionCode: Code[10]; resolutionNote: Text): Text
    begin
        Mgt.FinishWork(Rec."No.", ResolveLine(serviceItemLineNo), faultAreaCode, symptomCode, faultCode, resolutionCode, resolutionNote);
        exit('OK');
    end;

    [ServiceEnabled]
    procedure addLabor(serviceItemLineNo: Integer; hours: Decimal; workTypeCode: Code[10]; description: Text): Text
    begin
        exit(Format(Mgt.AddLabor(Rec."No.", ResolveLine(serviceItemLineNo), hours, workTypeCode, description), 0, 9));
    end;

    [ServiceEnabled]
    procedure addPart(serviceItemLineNo: Integer; itemNo: Code[20]; quantity: Decimal; locationCode: Code[10]): Text
    begin
        exit(Format(Mgt.AddPart(Rec."No.", ResolveLine(serviceItemLineNo), itemNo, quantity, locationCode), 0, 9));
    end;

    [ServiceEnabled]
    procedure deleteLine(lineNo: Integer): Text
    begin
        Mgt.DeleteLine(Rec."No.", lineNo);
        exit('OK');
    end;

    [ServiceEnabled]
    procedure addComment(serviceItemLineNo: Integer; commentType: Text; text: Text): Text
    begin
        Mgt.AddComment(Rec."No.", ResolveLine(serviceItemLineNo), commentType, text);
        exit('OK');
    end;

    [ServiceEnabled]
    procedure addAttachment(fileName: Text; base64Content: Text; kind: Text): Text
    begin
        exit(Format(Mgt.AddAttachment(Rec."No.", fileName, base64Content, kind), 0, 9));
    end;

    [ServiceEnabled]
    procedure postShipment(consume: Boolean): Text
    begin
        exit(Format(Mgt.PostShipment(Rec."No.", consume), 0, 9));
    end;
    var
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
        statusTextValue: Text;
        priorityValue: Text;
        priorityTextValue: Text;
        releaseStatusValue: Text;
        technicianNamesValue: Text;
        allocatedHoursValue: Decimal;
        noOfServiceItemLinesValue: Integer;
}
