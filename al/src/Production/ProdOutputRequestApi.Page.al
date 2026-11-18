page 72234 "DOPSWHS Prod Output Req API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'productionOutputRequest';
    EntitySetName = 'productionOutputRequests';
    SourceTable = "DOPSWHS Prod Output Request";
    ODataKeyFields = "Request ID";
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
                field(requestId; Rec."Request ID") { }
                field(prodOrderNo; Rec."Prod. Order No.") { }
                field(lineNo; Rec."Prod. Order Line No.") { }
                field(itemNo; Rec."Item No.") { }
                field(quantity; Rec.Quantity) { }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { }
                field(lotNo; Rec."Lot No.") { }
                field(postingDate; Rec."Posting Date") { }
                field(expirationDate; Rec."Expiration Date") { }
                field(completed; Rec.Completed) { }
                field(cancelled; Rec.Cancelled) { }
                field(documentNo; Rec."Document No.") { }
                field(entryNo; Rec."Item Ledger Entry No.") { }
                field(quantityBase; Rec."Quantity (Base)") { }
                field(baseUnitOfMeasure; Rec."Base Unit of Measure") { }
            }
        }
    }
    trigger OnOpenPage()
    begin
        Rec.FilterGroup(2);
        Rec.SetRange("Created By", UserSecurityId());
        Rec.FilterGroup(0);
    end;
    [ServiceEnabled]
    procedure postOutput(): Text
    var
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
    begin
        exit(Mgmt.PostOutput(Rec."Request ID"));
    end;
    [ServiceEnabled]
    procedure cancelOutput(): Text
    var
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
    begin
        exit(Mgmt.CancelOutput(Rec."Request ID"));
    end;
}
