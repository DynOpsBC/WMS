page 72106 "DOPSWHS Svc Item Lines API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceItemLine';
    EntitySetName = 'serviceItemLines';
    SourceTable = "Service Item Line";
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
                field(documentNo; Rec."Document No.") { Caption = 'documentNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(serviceItemNo; Rec."Service Item No.") { Caption = 'serviceItemNo'; }
                field(serviceItemGroupCode; Rec."Service Item Group Code") { Caption = 'serviceItemGroupCode'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; }
                field(description; Rec."Description") { Caption = 'description'; }
                field(description2; Rec."Description 2") { Caption = 'description2'; }
                field(repairStatusCode; Rec."Repair Status Code") { Caption = 'repairStatusCode'; }
                field(responseDate; Rec."Response Date") { Caption = 'responseDate'; }
                field(responseTime; Rec."Response Time") { Caption = 'responseTime'; }
                field(startingDate; Rec."Starting Date") { Caption = 'startingDate'; }
                field(startingTime; Rec."Starting Time") { Caption = 'startingTime'; }
                field(finishingDate; Rec."Finishing Date") { Caption = 'finishingDate'; }
                field(finishingTime; Rec."Finishing Time") { Caption = 'finishingTime'; }
                field(faultAreaCode; Rec."Fault Area Code") { Caption = 'faultAreaCode'; }
                field(symptomCode; Rec."Symptom Code") { Caption = 'symptomCode'; }
                field(faultCode; Rec."Fault Code") { Caption = 'faultCode'; }
                field(resolutionCode; Rec."Resolution Code") { Caption = 'resolutionCode'; }
                field(faultReasonCode; Rec."Fault Reason Code") { Caption = 'faultReasonCode'; }
                field(warranty; Rec."Warranty") { Caption = 'warranty'; }
                field(locationOfServiceItem; Rec."Location of Service Item") { Caption = 'locationOfServiceItem'; }
                field(customerNo; Rec."Customer No.") { Caption = 'customerNo'; }
                field(priority; priorityValue) { Caption = 'priority'; }
                field(faultAreaText; faultAreaTextValue) { Caption = 'faultAreaText'; }
                field(symptomText; symptomTextValue) { Caption = 'symptomText'; }
                field(resolutionText; resolutionTextValue) { Caption = 'resolutionText'; }
                field(repairStatusText; repairStatusTextValue) { Caption = 'repairStatusText'; }
            }
        }
    }
    trigger OnAfterGetRecord()
    var
        FaultArea: Record "Fault Area";
        SymptomCode: Record "Symptom Code";
        ResolutionCode: Record "Resolution Code";
        RepairStatus: Record "Repair Status";
    begin
        priorityValue := Rec.Priority.Names.Get(Rec.Priority.Ordinals.IndexOf(Rec.Priority.AsInteger()));
        // Technicians read descriptions, not codes.
        Clear(faultAreaTextValue);
        Clear(symptomTextValue);
        Clear(resolutionTextValue);
        Clear(repairStatusTextValue);
        if FaultArea.Get(Rec."Fault Area Code") then
            faultAreaTextValue := FaultArea.Description;
        if SymptomCode.Get(Rec."Symptom Code") then
            symptomTextValue := SymptomCode.Description;
        if ResolutionCode.Get(Rec."Resolution Code") then
            resolutionTextValue := ResolutionCode.Description;
        if RepairStatus.Get(Rec."Repair Status Code") then
            repairStatusTextValue := RepairStatus.Description;
    end;
    var
        priorityValue: Text;
        faultAreaTextValue: Text;
        symptomTextValue: Text;
        resolutionTextValue: Text;
        repairStatusTextValue: Text;
}
