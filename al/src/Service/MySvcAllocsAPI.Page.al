page 72108 "DOPSWHS My Svc Allocs API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'myServiceAllocation';
    EntitySetName = 'myServiceAllocations';
    SourceTable = "Service Order Allocation";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    SourceTableView = where("Document Type" = const(Order), Posted = const(false));
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(entryNo; Rec."Entry No.") { Caption = 'entryNo'; }
                field(documentNo; Rec."Document No.") { Caption = 'documentNo'; }
                field(serviceItemLineNo; Rec."Service Item Line No.") { Caption = 'serviceItemLineNo'; }
                field(resourceNo; Rec."Resource No.") { Caption = 'resourceNo'; }
                field(allocationDate; Rec."Allocation Date") { Caption = 'allocationDate'; }
                field(allocatedHours; Rec."Allocated Hours") { Caption = 'allocatedHours'; }
                field(status; Rec."Status") { Caption = 'status'; }
                field(startingTime; Rec."Starting Time") { Caption = 'startingTime'; }
                field(finishingTime; Rec."Finishing Time") { Caption = 'finishingTime'; }
                field(serviceStarted; Rec."Service Started") { Caption = 'serviceStarted'; }
                field(serviceItemNo; Rec."Service Item No.") { Caption = 'serviceItemNo'; }
                field(serviceItemDescription; Rec."Service Item Description") { Caption = 'serviceItemDescription'; }
                field(serviceItemSerialNo; Rec."Service Item Serial No.") { Caption = 'serviceItemSerialNo'; }
                field(repairStatus; Rec."Repair Status") { Caption = 'repairStatus'; }
                field(statusText; statusTextValue) { Caption = 'statusText'; }
                field(customerName; customerNameValue) { Caption = 'customerName'; }
                field(address; addressValue) { Caption = 'address'; }
                field(city; cityValue) { Caption = 'city'; }
                field(phoneNo; phoneNoValue) { Caption = 'phoneNo'; }
                field(contactName; contactNameValue) { Caption = 'contactName'; }
                field(orderDescription; orderDescriptionValue) { Caption = 'orderDescription'; }
                field(orderStatus; orderStatusValue) { Caption = 'orderStatus'; }
                field(orderStatusText; orderStatusTextValue) { Caption = 'orderStatusText'; }
                field(priority; priorityValue) { Caption = 'priority'; }
                field(priorityText; priorityTextValue) { Caption = 'priorityText'; }
                field(responseDate; responseDateValue) { Caption = 'responseDate'; }
                field(responseTime; responseTimeValue) { Caption = 'responseTime'; }
                field(orderSystemId; orderSystemIdValue) { Caption = 'orderSystemId'; }
            }
        }
    }
    trigger OnOpenPage()
    var
        Tech: Record "DOPSWHS Service Technician";
    begin
        Mgt.CurrentTechnician(Tech);
        Rec.FilterGroup(2);
        Rec.SetRange("Resource No.", Tech."Resource No.");
        Rec.SetFilter(Status, '%1|%2', Rec.Status::Active, Rec.Status::Finished);
        Rec.FilterGroup(0);
    end;
    trigger OnAfterGetRecord()
    var
        Header: Record "Service Header";
        AllocationRef: RecordRef;
        StatusField: FieldRef;
    begin
        // Option members are invariant; captions depend on the session language.
        AllocationRef.GetTable(Rec);
        StatusField := AllocationRef.Field(Rec.FieldNo(Status));
        statusTextValue := SelectStr(Rec.Status + 1, StatusField.OptionMembers);
        Clear(Header);
        if Header.Get(Header."Document Type"::Order, Rec."Document No.") then;
        customerNameValue := Header.Name;
        addressValue := Header.Address;
        cityValue := Header.City;
        phoneNoValue := Header."Phone No.";
        contactNameValue := Header."Contact Name";
        orderDescriptionValue := Header.Description;
        orderStatusValue := Header.Status.Names.Get(Header.Status.Ordinals.IndexOf(Header.Status.AsInteger()));
        orderStatusTextValue := orderStatusValue;
        priorityValue := Header.Priority.Names.Get(Header.Priority.Ordinals.IndexOf(Header.Priority.AsInteger()));
        priorityTextValue := priorityValue;
        responseDateValue := Header."Response Date";
        responseTimeValue := Header."Response Time";
        orderSystemIdValue := Header.SystemId;
    end;
    var
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
        statusTextValue: Text;
        customerNameValue: Text;
        addressValue: Text;
        cityValue: Text;
        phoneNoValue: Text;
        contactNameValue: Text;
        orderDescriptionValue: Text;
        orderStatusValue: Text;
        orderStatusTextValue: Text;
        priorityValue: Text;
        priorityTextValue: Text;
        responseDateValue: Date;
        responseTimeValue: Time;
        orderSystemIdValue: Guid;
}
