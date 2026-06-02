page 72230 "DOPSWHS Assembly Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'assemblyLine';
    EntitySetName = 'assemblyLines';
    SourceTable = "Assembly Line";
    DelayedInsert = true;
    ODataKeyFields = "Document Type", "Document No.", "Line No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(documentNo; Rec."Document No.") { Caption = 'documentNo'; }
                field(documentType; Rec."Document Type") { Caption = 'documentType'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(type; Rec.Type) { Caption = 'type'; }
                field(itemNo; Rec."No.") { Caption = 'itemNo'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(consumedQuantity; Rec."Consumed Quantity") { Caption = 'consumedQuantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
            }
        }
    }
    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::AssemblyLine);
        RecRef.SetTable(Rec);
    end;

}
