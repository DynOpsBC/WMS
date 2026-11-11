page 72476 "DOPSWHS Field WO Line API"
{
    // Kitoko/Element4 #3338: açık saha iş emirlerinin satırları (ekip ve malzemeler).
    //   GET fieldWorkOrderLines?$filter=workOrderNo eq 'SIE-…'
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'fieldWorkOrderLine';
    EntitySetName = 'fieldWorkOrderLines';
    SourceTable = "DOPSWHS Field WO Line Buffer";
    SourceTableTemporary = true;
    ODataKeyFields = "Work Order No.", "Line No.";
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(workOrderNo; Rec."Work Order No.") { Caption = 'workOrderNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(type; Rec.Type) { Caption = 'type'; }
                field(isItem; Rec."Is Item") { Caption = 'isItem'; }
                field(no; Rec."No.") { Caption = 'no'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(actualQuantity; Rec."Actual Quantity") { Caption = 'actualQuantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
            }
        }
    }

    trigger OnOpenPage()
    var
        ProjectIssueMgmt: Codeunit "DOPSWHS Project Issue Mgmt";
    begin
        ProjectIssueMgmt.FillOpenWorkOrderLines(Rec);
    end;
}
